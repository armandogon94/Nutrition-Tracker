"""Meal-log endpoint tests (backend hardening, Task 5).

Covers the iOS ``MealService`` contract:

- ``POST /api/v1/meals/log`` — combined create-meal + add-item with a nutrition
  snapshot; returns the iOS ``MealDTO`` shape (snapshot items)
- find-or-create: a second log of the same type/day attaches to one meal
- idempotency: replaying the same ``client_item_id`` does not duplicate
- nutrition totals reflect the logged grams/servings correctly
- ``DELETE /api/v1/meals/items/{item_id}`` — item-only delete, idempotent,
  cross-user protected
"""

import asyncio
import uuid
from datetime import date

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.api.v1.meals import (
    _find_or_create_meal,
    _resolve_product_for_log,
)
from app.main import app
from app.models.meal import Meal, MealItem
from app.models.product import Product
from app.schemas.meal import MealLogRequest


def _log_body(**overrides) -> dict:
    body = {
        "meal_type": "lunch",
        "meal_date": "2026-06-25",
        "product_id": str(uuid.uuid4()),
        "product_name": "Grilled Chicken",
        "brand": "Generic",
        "servings": 2.0,
        "calories": 330.0,  # 165/serving * 2
        "protein_g": 62.0,
        "carbs_g": 0.0,
        "fat_g": 7.2,
        "client_item_id": str(uuid.uuid4()),
    }
    body.update(overrides)
    return body


async def test_log_requires_auth(client):
    resp = await client.post("/api/v1/meals/log", json=_log_body())
    assert resp.status_code == 401


async def test_log_creates_meal_and_returns_ios_shape(auth_client):
    body = _log_body()
    resp = await auth_client.post("/api/v1/meals/log", json=body)
    assert resp.status_code == 201, resp.text
    data = resp.json()

    # MealDTO shape.
    assert set(data.keys()) == {"id", "user_id", "meal_type", "meal_date", "items"}
    assert data["meal_type"] == "lunch"
    assert data["meal_date"] == "2026-06-25"
    assert len(data["items"]) == 1

    item = data["items"][0]
    # MealItemDTO shape (snapshot fields, not a nested product).
    assert set(item.keys()) == {
        "id",
        "product_id",
        "product_name",
        "brand",
        "servings",
        "calories",
        "protein_g",
        "carbs_g",
        "fat_g",
    }
    assert item["product_name"] == "Grilled Chicken"
    assert item["servings"] == 2.0
    # Totals echo back what was sent.
    assert item["calories"] == 330.0
    assert item["protein_g"] == 62.0


async def test_log_second_item_attaches_to_same_meal(auth_client, db_session):
    first = await auth_client.post("/api/v1/meals/log", json=_log_body())
    meal_id = first.json()["id"]

    second = await auth_client.post(
        "/api/v1/meals/log",
        json=_log_body(product_name="Rice", calories=200.0, servings=1.0),
    )
    assert second.status_code == 201
    data = second.json()
    # Same parent meal, now two items.
    assert data["id"] == meal_id
    assert len(data["items"]) == 2

    # Exactly one Meal row for this type/day.
    count = await db_session.scalar(
        select(func.count()).select_from(Meal).where(Meal.meal_type == "lunch")
    )
    assert count == 1


async def test_log_is_idempotent_on_client_item_id(auth_client, db_session):
    body = _log_body()
    first = await auth_client.post("/api/v1/meals/log", json=body)
    assert first.status_code == 201
    first_item_id = first.json()["items"][0]["id"]

    # Replay the exact same payload (same client_item_id) — e.g. offline retry.
    replay = await auth_client.post("/api/v1/meals/log", json=body)
    assert replay.status_code == 201
    data = replay.json()
    assert len(data["items"]) == 1
    assert data["items"][0]["id"] == first_item_id

    # Only one MealItem persisted.
    item_count = await db_session.scalar(
        select(func.count()).select_from(MealItem)
    )
    assert item_count == 1


async def test_logged_item_feeds_daily_nutrition(auth_client):
    """A grams-free, servings-based log shows up in the daily nutrition totals."""
    await auth_client.post(
        "/api/v1/meals/log",
        json=_log_body(
            calories=330.0, protein_g=62.0, carbs_g=10.0, fat_g=7.0, servings=2.0
        ),
    )
    daily = await auth_client.get("/api/v1/nutrition/daily/2026-06-25")
    assert daily.status_code == 200
    totals = daily.json()
    assert totals["total_calories"] == 330.0
    assert totals["total_protein_g"] == 62.0
    assert totals["meals_count"] == 1


async def test_delete_item_by_id(auth_client, db_session):
    logged = await auth_client.post("/api/v1/meals/log", json=_log_body())
    item_id = logged.json()["items"][0]["id"]

    resp = await auth_client.delete(f"/api/v1/meals/items/{item_id}")
    assert resp.status_code == 204

    count = await db_session.scalar(select(func.count()).select_from(MealItem))
    assert count == 0


async def test_delete_item_is_idempotent(auth_client):
    """Deleting an unknown / already-deleted item returns 204 (retry-safe)."""
    resp = await auth_client.delete(f"/api/v1/meals/items/{uuid.uuid4()}")
    assert resp.status_code == 204


async def test_delete_item_requires_auth(client):
    resp = await client.delete(f"/api/v1/meals/items/{uuid.uuid4()}")
    assert resp.status_code == 401


async def test_cannot_delete_another_users_item(auth_client, auth_client_b):
    """User B must not be able to delete user A's item."""
    logged = await auth_client.post("/api/v1/meals/log", json=_log_body())
    item_id = logged.json()["items"][0]["id"]

    # User B attempts the delete.
    resp = await auth_client_b.delete(f"/api/v1/meals/items/{item_id}")
    assert resp.status_code == 404

    # The item is still there for user A.
    again = await auth_client.delete(f"/api/v1/meals/items/{item_id}")
    assert again.status_code == 204


# ---- Concurrency / atomicity (Codex review-4 #4) -------------------------
#
# Idempotency must hold under genuinely concurrent traffic, not just sequential
# replays. Each request runs through its own get_db() session/transaction, so
# asyncio.gather races them on the DB unique constraints. Without the constraints
# (select-then-insert), these duplicate.


def _concurrent_clients(auth_token: str, n: int) -> list[AsyncClient]:
    """n independent authed clients so requests truly run in parallel (each gets
    its own get_db transaction) rather than sharing one connection."""
    return [
        AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {auth_token}"},
        )
        for _ in range(n)
    ]


async def test_concurrent_same_client_item_id_inserts_one_row(
    auth_token, db_session
):
    """Concurrent retries with the SAME client_item_id -> exactly one MealItem.

    Simulates the offline-retry queue firing the same mutation several times at
    once (e.g. on reconnect). The (meal_id, client_item_id) partial unique index
    must collapse them to a single row; every response echoes that same item.
    """
    body = _log_body()  # one fixed client_item_id shared by all racers
    clients = _concurrent_clients(auth_token, 5)
    try:
        responses = await asyncio.gather(
            *(c.post("/api/v1/meals/log", json=body) for c in clients)
        )
    finally:
        await asyncio.gather(*(c.aclose() for c in clients))

    statuses = [r.status_code for r in responses]
    assert all(s == 201 for s in statuses), statuses

    # All responses converge on the same single item id.
    item_ids = {r.json()["items"][0]["id"] for r in responses}
    assert len(item_ids) == 1

    # Exactly one MealItem and one parent Meal persisted.
    item_count = await db_session.scalar(select(func.count()).select_from(MealItem))
    assert item_count == 1
    meal_count = await db_session.scalar(select(func.count()).select_from(Meal))
    assert meal_count == 1


async def test_concurrent_first_logs_same_slot_share_one_meal(
    auth_token, db_session
):
    """Concurrent FIRST logs (distinct items, same type/day) -> one parent meal.

    Without UNIQUE (user_id, meal_type, meal_date), two simultaneous first logs
    each create their own parent meal. The constraint forces them to converge on
    a single meal that owns both items.
    """
    bodies = [
        _log_body(
            product_name=f"Item {i}",
            client_item_id=str(uuid.uuid4()),  # distinct items
        )
        for i in range(5)
    ]
    clients = _concurrent_clients(auth_token, len(bodies))
    try:
        responses = await asyncio.gather(
            *(c.post("/api/v1/meals/log", json=b) for c, b in zip(clients, bodies))
        )
    finally:
        await asyncio.gather(*(c.aclose() for c in clients))

    statuses = [r.status_code for r in responses]
    assert all(s == 201 for s in statuses), statuses

    # Every response references the SAME parent meal.
    meal_ids = {r.json()["id"] for r in responses}
    assert len(meal_ids) == 1

    # Exactly one Meal, and all five distinct items landed on it.
    meal_count = await db_session.scalar(select(func.count()).select_from(Meal))
    assert meal_count == 1
    item_count = await db_session.scalar(select(func.count()).select_from(MealItem))
    assert item_count == 5


# ---- Product-snapshot concurrency (Codex review-5 P1 incomplete) ----------
#
# _resolve_product_for_log() used select-then-insert/flush for a client-supplied
# product_id. Product.id and Product.barcode (= "log:{id}") are unique, so two
# concurrent replays carrying the SAME new product_id both miss the read, both
# try to INSERT the same product, and the loser's flush hit a unique violation
# that poisoned the session -> 500. Snapshot creation is now upsert-safe.


async def test_concurrent_same_new_product_and_client_item_id_converges(
    auth_token, db_session
):
    """Same NEW product_id + same client_item_id, fired concurrently.

    The exact P1 race: every racer would create the same snapshot product AND
    the same meal item. Must converge on ONE meal item / ONE product with NO 500
    (no IntegrityError leaking from the product insert).
    """
    shared_product_id = str(uuid.uuid4())
    shared_client_item_id = str(uuid.uuid4())
    body = _log_body(
        product_id=shared_product_id,
        client_item_id=shared_client_item_id,
    )
    clients = _concurrent_clients(auth_token, 6)
    try:
        responses = await asyncio.gather(
            *(c.post("/api/v1/meals/log", json=body) for c in clients)
        )
    finally:
        await asyncio.gather(*(c.aclose() for c in clients))

    statuses = [r.status_code for r in responses]
    assert all(s == 201 for s in statuses), statuses

    # All responses converge on the same single item id.
    item_ids = {r.json()["items"][0]["id"] for r in responses}
    assert len(item_ids) == 1

    # Exactly one MealItem, one Meal, and one snapshot Product persisted.
    item_count = await db_session.scalar(select(func.count()).select_from(MealItem))
    assert item_count == 1
    meal_count = await db_session.scalar(select(func.count()).select_from(Meal))
    assert meal_count == 1
    product_count = await db_session.scalar(
        select(func.count())
        .select_from(Product)
        .where(Product.id == uuid.UUID(shared_product_id))
    )
    assert product_count == 1


async def test_concurrent_same_new_product_distinct_items_no_500(
    auth_token, db_session
):
    """Same NEW product_id, DISTINCT client_item_ids, fired concurrently.

    Stresses the product-creation race in isolation: each racer logs a different
    item but all reference the same not-yet-existing product_id, so they all try
    to create that one snapshot product at once. The product insert must be
    conflict-safe (no 500), and all items must point at the single product row.
    """
    shared_product_id = str(uuid.uuid4())
    bodies = [
        _log_body(
            product_id=shared_product_id,
            product_name="Shared Product",
            client_item_id=str(uuid.uuid4()),  # distinct items
        )
        for _ in range(5)
    ]
    clients = _concurrent_clients(auth_token, len(bodies))
    try:
        responses = await asyncio.gather(
            *(c.post("/api/v1/meals/log", json=b) for c, b in zip(clients, bodies))
        )
    finally:
        await asyncio.gather(*(c.aclose() for c in clients))

    statuses = [r.status_code for r in responses]
    assert all(s == 201 for s in statuses), statuses

    # Five distinct items, all pointing at the one shared product.
    item_count = await db_session.scalar(select(func.count()).select_from(MealItem))
    assert item_count == 5
    product_count = await db_session.scalar(
        select(func.count())
        .select_from(Product)
        .where(Product.id == uuid.UUID(shared_product_id))
    )
    assert product_count == 1

    item_product_ids = {
        str(r.json()["items"][-1]["product_id"]) for r in responses
    }
    # Note: response items are sorted by created_at; the just-logged item is the
    # one each racer cares about. They all share the single product id.
    assert item_product_ids == {shared_product_id}


# ---- Deterministic barrier test for the product-snapshot race -------------
#
# The HTTP-level concurrency tests above don't *reliably* trigger the product
# insert race: requests serialize on earlier awaits (the meal ON CONFLICT insert
# and the existence SELECT), so the two product INSERTs rarely overlap in the
# window where one is uncommitted and another is issued. The buggy
# select-then-insert/flush code therefore passed those tests intermittently.
#
# This test pins the failure deterministically: two independent sessions are
# forced (via two asyncio.Barriers) into the exact dangerous interleaving —
# BOTH read "product absent", THEN both insert. Under the old code the loser's
# flush raised IntegrityError on Product.id/Product.barcode and poisoned the
# session; the upsert-safe (ON CONFLICT DO NOTHING + re-select) version converges
# both on a single shared snapshot row with no error.


def _log_request(product_id: str, client_item_id: str) -> MealLogRequest:
    return MealLogRequest(
        meal_type="lunch",
        meal_date=date(2026, 6, 25),
        product_id=product_id,
        product_name="Snapshot Food",
        brand="Generic",
        servings=2.0,
        calories=330.0,
        protein_g=62.0,
        carbs_g=0.0,
        fat_g=7.2,
        client_item_id=client_item_id,
    )


async def test_resolve_product_race_converges_no_integrity_error(setup_db):
    """Two sessions forced into read-then-insert of the SAME new product_id.

    The barrier interleaving is exactly the one that made the old code 500. The
    upsert-safe resolver must let BOTH sessions return the single converged
    snapshot product with no IntegrityError and exactly one Product row.
    """
    _engine, session_factory = setup_db
    shared_product_id = str(uuid.uuid4())

    read_done = asyncio.Barrier(2)  # both confirm "absent" before any insert
    pre_insert = asyncio.Barrier(2)  # both issue their INSERT together

    async def racer(client_item_id: str) -> tuple[str, str]:
        data = _log_request(shared_product_id, client_item_id)
        async with session_factory() as session:
            # 1. Race the existence read: both must see "absent" first.
            existing = await session.get(
                Product, uuid.UUID(shared_product_id)
            )
            assert existing is None
            await read_done.wait()
            # 2. Now both drive the real resolver (insert-or-conflict path)
            #    at the same time — the interleaving that broke select+flush.
            await pre_insert.wait()
            try:
                product, _created = await _resolve_product_for_log(session, data)
                await session.commit()
                return ("ok", str(product.id))
            except Exception as exc:  # pragma: no cover - asserted absent below
                await session.rollback()
                return ("ERR", type(exc).__name__)

    results = await asyncio.gather(racer(str(uuid.uuid4())), racer(str(uuid.uuid4())))

    # No session was poisoned: both succeeded (no IntegrityError -> no 500).
    assert all(status == "ok" for status, _ in results), results
    # Both converged on the single client-supplied snapshot id.
    assert {value for _, value in results} == {shared_product_id}

    # Exactly one Product row persisted for that id.
    async with session_factory() as session:
        count = await session.scalar(
            select(func.count())
            .select_from(Product)
            .where(Product.id == uuid.UUID(shared_product_id))
        )
    assert count == 1


# ---- B4: meal-log conflict cleanup must not delete a catalog product ----------
#
# Race two /meals/log with the SAME client_item_id but DIFFERENT product_ids.
# The loser loads the winning item, sees existing.product_id != product.id, and
# the OLD code ran `await db.delete(product)`. If the loser's product_id was a
# pre-existing SHARED catalog product, that row was deleted for EVERY user. The
# fix gates the delete on created_new (this request newly created the snapshot)
# AND it being a `log:` manual orphan — so a catalog row is never deleted.
#
# The dangerous branch only runs when the fast-path existence SELECT MISSES but
# the subsequent INSERT then LOSES the ON CONFLICT race (a true TOCTOU window).
# We reproduce that deterministically by forcing the loser's *first*
# (fast-path) existence lookup to return None even though the winning item is
# already committed; its INSERT then conflicts and it falls into the cleanup
# branch with the catalog product in hand.


async def test_log_conflict_does_not_delete_catalog_product(setup_db, monkeypatch):
    """Losing-race cleanup must NOT delete a pre-existing catalog product (B4)."""
    import app.api.v1.meals as meals_mod
    from app.core.security import hash_password
    from app.models.user import User

    _engine, session_factory = setup_db
    user_id = uuid.UUID("00000000-0000-0000-0000-000000000099")
    catalog_id = uuid.uuid4()
    shared_client_item_id = str(uuid.uuid4())

    # Seed the user, a parent meal, the winning item (pointing at a SNAPSHOT
    # product), and a pre-existing SHARED catalog product the loser references.
    async with session_factory() as session:
        session.add(
            User(
                id=user_id,
                email="b4user@test.dev",
                password_hash=hash_password("x"),
                display_name="B4",
            )
        )
        await session.commit()
        meal = await _find_or_create_meal(
            session, user_id=user_id, meal_type="lunch", meal_date=date(2026, 6, 25)
        )
        meal_id = meal.id

        snapshot_pid = uuid.uuid4()
        session.add(
            Product(
                id=snapshot_pid,
                barcode=f"log:{snapshot_pid}",
                name="Winning Snapshot",
                serving_size_g=100.0,
                calories=100.0,
                source="manual",
            )
        )
        # The pre-existing SHARED catalog product (real barcode, trusted source).
        session.add(
            Product(
                id=catalog_id,
                barcode="7501055309999",
                name="Shared Catalog Cola",
                brand="Coca-Cola",
                serving_size_g=355.0,
                calories=140.0,
                carbs_g=39.0,
                source="open_food_facts",
            )
        )
        await session.commit()
        # The WINNER's item, already committed under this client_item_id.
        winning_item = MealItem(
            meal_id=meal_id,
            product_id=snapshot_pid,
            quantity_servings=1.0,
            client_item_id=shared_client_item_id,
        )
        session.add(winning_item)
        await session.commit()

    # Force the loser's FAST-PATH existence lookup to miss, so it proceeds to the
    # INSERT (which then loses on the unique index) and enters the cleanup branch.
    real_select = meals_mod._select_item_by_client_id
    calls = {"n": 0}

    async def flaky_select(db, *, meal_id, client_item_id):
        calls["n"] += 1
        if calls["n"] == 1:
            return None  # simulate the TOCTOU: not yet visible on fast path
        return await real_select(db, meal_id=meal_id, client_item_id=client_item_id)

    monkeypatch.setattr(meals_mod, "_select_item_by_client_id", flaky_select)

    data = MealLogRequest(
        meal_type="lunch",
        meal_date=date(2026, 6, 25),
        product_id=str(catalog_id),  # loser references the CATALOG product
        product_name="Catalog Item",
        brand="Coca-Cola",
        servings=1.0,
        calories=140.0,
        protein_g=0.0,
        carbs_g=39.0,
        fat_g=0.0,
        client_item_id=shared_client_item_id,
    )
    async with session_factory() as session:
        item, _product = await meals_mod._get_or_create_item(
            session, meal_id=meal_id, data=data
        )
        await session.commit()

    # The loser converged on the winner's item (idempotent).
    assert str(item.client_item_id) == shared_client_item_id

    # The pre-existing catalog product MUST still exist (the bug deleted it).
    async with session_factory() as session:
        survived = await session.get(Product, catalog_id)
    assert survived is not None, "catalog product was wrongly deleted on losing race"
    assert survived.source == "open_food_facts"


# ---- B5 / Flash A1+A7: meal-quantity validation + servings clamp --------------
#
# `servings` must be > 0 and bounded; negative/zero/huge values are rejected at
# the schema boundary (422) so they can never produce negative or NaN macros.
# A tiny-but-positive servings (e.g. 1e-300) must not blow up the per-serving
# macro division — it is clamped to >= 0.01 in _resolve_product_for_log.


async def test_log_rejects_negative_servings(auth_client):
    resp = await auth_client.post(
        "/api/v1/meals/log", json=_log_body(servings=-1000000.0)
    )
    assert resp.status_code == 422


async def test_log_rejects_zero_servings(auth_client):
    resp = await auth_client.post("/api/v1/meals/log", json=_log_body(servings=0.0))
    assert resp.status_code == 422


async def test_log_rejects_huge_servings(auth_client):
    resp = await auth_client.post(
        "/api/v1/meals/log", json=_log_body(servings=1e9)
    )
    assert resp.status_code == 422


async def test_log_tiny_servings_does_not_blow_up_macros(auth_token, db_session):
    """A tiny positive servings is accepted (passes Pydantic gt=0) but the
    per-serving macro division must be clamped, never producing inf/NaN.

    Drives the resolver directly so we can pass 1e-300 (which JSON would render
    awkwardly) and assert the stored per-serving macros are finite.
    """
    import math

    from app.api.v1.meals import _resolve_product_for_log

    data = MealLogRequest(
        meal_type="lunch",
        meal_date=date(2026, 6, 25),
        product_id=str(uuid.uuid4()),
        product_name="Tiny Servings Food",
        brand="Generic",
        servings=1e-300,  # tiny but > 0
        calories=300.0,
        protein_g=30.0,
        carbs_g=10.0,
        fat_g=5.0,
        client_item_id=str(uuid.uuid4()),
    )
    product, created_new = await _resolve_product_for_log(db_session, data)
    assert created_new is True
    # Clamped divisor (>= 0.01): 300 / 0.01 = 30000, finite — not inf/NaN.
    assert math.isfinite(product.calories)
    assert math.isfinite(product.protein_g)
    assert product.calories == pytest.approx(300.0 / 0.01, rel=1e-6)


async def test_add_meal_item_rejects_negative_servings(auth_client, db_session):
    """The legacy POST /meals/{id}/items route also rejects bad quantities."""
    from app.models.product import Product as ProductModel

    product = ProductModel(
        barcode=f"B5-{uuid.uuid4().hex[:8]}",
        name="Item",
        serving_size_g=100.0,
        calories=100.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()

    meal = await auth_client.post(
        "/api/v1/meals", json={"meal_type": "lunch", "meal_date": "2026-06-25"}
    )
    meal_id = meal.json()["id"]

    resp = await auth_client.post(
        f"/api/v1/meals/{meal_id}/items",
        json={"product_id": str(product.id), "quantity_servings": -5.0},
    )
    assert resp.status_code == 422

    resp_zero = await auth_client.post(
        f"/api/v1/meals/{meal_id}/items",
        json={"product_id": str(product.id), "quantity_grams": 0.0},
    )
    assert resp_zero.status_code == 422
