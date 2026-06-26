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

from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.main import app
from app.models.meal import Meal, MealItem


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
