import uuid
from datetime import date

import pytest

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
