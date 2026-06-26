import asyncio
import uuid
from datetime import date

from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.main import app
from app.models.meal import Meal
from app.models.product import Product


async def _create_product(db_session, suffix=""):
    """Helper to create a test product in the database."""
    product = Product(
        barcode=f"TEST-{uuid.uuid4().hex[:8]}{suffix}",
        name=f"Test Product {suffix}".strip(),
        brand="TestBrand",
        serving_size_g=100.0,
        calories=250.0,
        protein_g=20.0,
        carbs_g=30.0,
        fat_g=8.0,
        fiber_g=3.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()
    return product


async def test_create_meal(auth_client, db_session):
    response = await auth_client.post(
        "/api/v1/meals",
        json={
            "meal_type": "breakfast",
            "meal_date": "2026-04-01",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["meal_type"] == "breakfast"
    assert data["meal_date"] == "2026-04-01"
    assert data["items"] == []
    assert "id" in data


async def test_get_meals_by_date(auth_client, db_session):
    # Create two meals on the same date
    await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "breakfast", "meal_date": "2026-04-02"},
    )
    await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "lunch", "meal_date": "2026-04-02"},
    )

    response = await auth_client.get("/api/v1/meals/2026-04-02")
    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 2
    meal_types = [m["meal_type"] for m in data]
    assert "breakfast" in meal_types
    assert "lunch" in meal_types


async def test_get_meals_empty_date(auth_client):
    response = await auth_client.get("/api/v1/meals/2020-01-01")
    assert response.status_code == 200
    data = response.json()
    assert data == []


async def test_add_meal_item(auth_client, db_session):
    product = await _create_product(db_session, "item-add")

    # Create a meal
    meal_resp = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "dinner", "meal_date": "2026-04-03"},
    )
    meal_id = meal_resp.json()["id"]

    # Add item to meal
    response = await auth_client.post(
        f"/api/v1/meals/{meal_id}/items",
        json={
            "product_id": str(product.id),
            "quantity_servings": 1.5,
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["product_id"] == str(product.id)
    assert data["quantity_servings"] == 1.5


async def test_add_meal_item_meal_not_found(auth_client, db_session):
    product = await _create_product(db_session, "not-found-meal")
    fake_id = str(uuid.uuid4())

    response = await auth_client.post(
        f"/api/v1/meals/{fake_id}/items",
        json={
            "product_id": str(product.id),
            "quantity_servings": 1.0,
        },
    )
    assert response.status_code == 404
    assert "meal not found" in response.json()["detail"].lower()


async def test_remove_meal_item(auth_client, db_session):
    product = await _create_product(db_session, "remove")

    # Create meal and add item
    meal_resp = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "snack", "meal_date": "2026-04-04"},
    )
    meal_id = meal_resp.json()["id"]

    item_resp = await auth_client.post(
        f"/api/v1/meals/{meal_id}/items",
        json={"product_id": str(product.id), "quantity_servings": 1.0},
    )
    item_id = item_resp.json()["id"]

    # Remove item
    response = await auth_client.delete(f"/api/v1/meals/{meal_id}/items/{item_id}")
    assert response.status_code == 204


async def test_remove_meal_item_not_found(auth_client, db_session):
    # Create a meal first
    meal_resp = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "lunch", "meal_date": "2026-04-05"},
    )
    meal_id = meal_resp.json()["id"]
    fake_item_id = str(uuid.uuid4())

    response = await auth_client.delete(
        f"/api/v1/meals/{meal_id}/items/{fake_item_id}"
    )
    assert response.status_code == 404


async def test_delete_meal(auth_client, db_session):
    meal_resp = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "breakfast", "meal_date": "2026-04-06"},
    )
    meal_id = meal_resp.json()["id"]

    response = await auth_client.delete(f"/api/v1/meals/{meal_id}")
    assert response.status_code == 204


async def test_delete_meal_not_found(auth_client):
    fake_id = str(uuid.uuid4())
    response = await auth_client.delete(f"/api/v1/meals/{fake_id}")
    assert response.status_code == 404


async def test_unauthorized_access(client):
    response = await client.post(
        "/api/v1/meals",
        json={"meal_type": "breakfast", "meal_date": "2026-04-01"},
    )
    assert response.status_code == 401


# ---- Legacy POST /meals duplicate natural-key handling (Codex review-5 P2) ----
#
# The uq_meals_user_type_date UNIQUE constraint means a second POST for the same
# (user_id, meal_type, meal_date) must NOT raise an unhandled IntegrityError
# (which surfaced as a 500). The route is now find-or-create: a duplicate POST
# converges on the single existing meal.


async def test_create_meal_duplicate_natural_key_no_500(auth_client, db_session):
    """A second POST for the same (type, date) returns the existing meal, not 500."""
    first = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "breakfast", "meal_date": "2026-05-01"},
    )
    assert first.status_code == 201, first.text
    first_id = first.json()["id"]

    # Duplicate natural key — previously raised IntegrityError -> 500.
    second = await auth_client.post(
        "/api/v1/meals",
        json={"meal_type": "breakfast", "meal_date": "2026-05-01"},
    )
    assert second.status_code == 201, second.text
    assert second.json()["id"] == first_id

    # Exactly one Meal row persisted for that natural key.
    count = await db_session.scalar(
        select(func.count())
        .select_from(Meal)
        .where(Meal.meal_type == "breakfast", Meal.meal_date == date(2026, 5, 1))
    )
    assert count == 1


async def test_concurrent_create_meal_same_slot_no_500(auth_token, db_session):
    """Concurrent legacy POSTs for the same slot all succeed -> one meal, no 500.

    Each client gets its own get_db() transaction, so asyncio.gather races them
    on uq_meals_user_type_date. The ON CONFLICT DO NOTHING + re-select path must
    converge them all on a single parent meal with no IntegrityError 500.
    """
    clients = [
        AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers={"Authorization": f"Bearer {auth_token}"},
        )
        for _ in range(5)
    ]
    payload = {"meal_type": "dinner", "meal_date": "2026-05-02"}
    try:
        responses = await asyncio.gather(
            *(c.post("/api/v1/meals", json=payload) for c in clients)
        )
    finally:
        await asyncio.gather(*(c.aclose() for c in clients))

    statuses = [r.status_code for r in responses]
    assert all(s == 201 for s in statuses), statuses

    # All responses converge on the same single meal id.
    meal_ids = {r.json()["id"] for r in responses}
    assert len(meal_ids) == 1

    count = await db_session.scalar(
        select(func.count())
        .select_from(Meal)
        .where(Meal.meal_type == "dinner", Meal.meal_date == date(2026, 5, 2))
    )
    assert count == 1
