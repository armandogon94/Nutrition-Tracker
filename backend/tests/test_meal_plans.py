import uuid

import pytest

from app.models.product import Product


async def _create_product(db_session, suffix=""):
    """Helper to create a test product for meal plan tests."""
    product = Product(
        barcode=f"MP-{uuid.uuid4().hex[:8]}{suffix}",
        name=f"Meal Plan Product {suffix}".strip(),
        brand="TestBrand",
        serving_size_g=100.0,
        calories=200.0,
        protein_g=15.0,
        carbs_g=25.0,
        fat_g=6.0,
        fiber_g=2.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()
    return product


async def test_create_meal_plan(auth_client):
    response = await auth_client.post(
        "/api/v1/meal-plans",
        json={
            "name": "Week 1 Plan",
            "week_start_date": "2026-04-06",
            "notes": "High protein week",
            "is_template": False,
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Week 1 Plan"
    assert data["week_start_date"] == "2026-04-06"
    assert data["notes"] == "High protein week"
    assert data["is_template"] is False
    assert "id" in data


async def test_list_meal_plans(auth_client):
    # Create two plans
    await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Plan A", "week_start_date": "2026-04-13"},
    )
    await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Plan B", "week_start_date": "2026-04-20"},
    )

    response = await auth_client.get("/api/v1/meal-plans")
    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 2


async def test_list_meal_plans_filtered_by_week(auth_client):
    """`?week_start_date=` returns only the plan(s) for that exact week so the
    iOS client can fetch the right week instead of guessing the latest
    (Codex cycle-3 finding #1 — week-scoped meal-plan contract)."""
    await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Week of Apr 13", "week_start_date": "2026-04-13"},
    )
    await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Week of Apr 20", "week_start_date": "2026-04-20"},
    )

    response = await auth_client.get(
        "/api/v1/meal-plans", params={"week_start_date": "2026-04-20"}
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 1
    assert data[0]["week_start_date"] == "2026-04-20"
    assert data[0]["name"] == "Week of Apr 20"


async def test_list_meal_plans_filtered_by_week_empty(auth_client):
    """A week with no plan returns an empty list (not another week's plan)."""
    await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Some Plan", "week_start_date": "2026-04-13"},
    )

    response = await auth_client.get(
        "/api/v1/meal-plans", params={"week_start_date": "2026-05-25"}
    )
    assert response.status_code == 200
    assert response.json() == []


async def test_list_meal_plans_week_filter_is_user_scoped(auth_client, auth_client_b):
    """The week filter must not leak another user's plan for the same week."""
    # User A and user B both have a plan for the same week.
    await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "A's week", "week_start_date": "2026-04-20"},
    )
    await auth_client_b.post(
        "/api/v1/meal-plans",
        json={"name": "B's week", "week_start_date": "2026-04-20"},
    )

    resp_a = await auth_client.get(
        "/api/v1/meal-plans", params={"week_start_date": "2026-04-20"}
    )
    assert resp_a.status_code == 200
    data_a = resp_a.json()
    assert len(data_a) == 1
    assert data_a[0]["name"] == "A's week"


async def test_get_meal_plan(auth_client):
    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Get Plan Test", "week_start_date": "2026-04-27"},
    )
    plan_id = create_resp.json()["id"]

    response = await auth_client.get(f"/api/v1/meal-plans/{plan_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Get Plan Test"
    assert data["id"] == plan_id


async def test_get_meal_plan_not_found(auth_client):
    fake_id = str(uuid.uuid4())
    response = await auth_client.get(f"/api/v1/meal-plans/{fake_id}")
    assert response.status_code == 404


async def test_delete_meal_plan(auth_client):
    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Delete Me", "week_start_date": "2026-05-04"},
    )
    plan_id = create_resp.json()["id"]

    response = await auth_client.delete(f"/api/v1/meal-plans/{plan_id}")
    assert response.status_code == 204

    # Verify it's gone
    get_resp = await auth_client.get(f"/api/v1/meal-plans/{plan_id}")
    assert get_resp.status_code == 404


async def test_add_meal_plan_item(auth_client, db_session):
    product = await _create_product(db_session, "plan-item")

    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Item Plan", "week_start_date": "2026-05-11"},
    )
    plan_id = create_resp.json()["id"]

    response = await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 0,
            "meal_type": "breakfast",
            "quantity_servings": 2.0,
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["product_id"] == str(product.id)
    assert data["day_of_week"] == 0
    assert data["meal_type"] == "breakfast"
    assert data["quantity_servings"] == 2.0


# ---- Schema bounds (B5 / Flash A4, A5) ----


@pytest.mark.parametrize(
    "payload_overrides",
    [
        {"quantity_servings": -1000000},  # negative servings
        {"quantity_servings": 0},  # zero servings (gt=0)
        {"quantity_servings": 10001},  # above le=10000
        {"quantity_grams": -500},  # negative grams
        {"quantity_grams": 0},  # zero grams (gt=0)
        {"quantity_grams": 100001},  # above le=100000
    ],
)
async def test_add_meal_plan_item_rejects_out_of_bounds_quantity(
    auth_client, db_session, payload_overrides
):
    """MealPlanItemCreate must reject negative/zero/overflow quantities so that
    shopping-list aggregation can't produce negative or absurd grocery totals."""
    product = await _create_product(db_session, "bounds")
    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Bounds Plan", "week_start_date": "2026-05-11"},
    )
    plan_id = create_resp.json()["id"]

    payload = {
        "product_id": str(product.id),
        "day_of_week": 0,
        "meal_type": "breakfast",
        **payload_overrides,
    }
    response = await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items", json=payload
    )
    assert response.status_code == 422


@pytest.mark.parametrize("bad_name", ["", "   ", "\t\n"])
async def test_create_meal_plan_rejects_blank_name(auth_client, bad_name):
    """MealPlanCreate.name must reject blank / whitespace-only names."""
    response = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": bad_name, "week_start_date": "2026-05-11"},
    )
    assert response.status_code == 422


async def test_remove_meal_plan_item(auth_client, db_session):
    product = await _create_product(db_session, "plan-remove")

    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Remove Item Plan", "week_start_date": "2026-05-18"},
    )
    plan_id = create_resp.json()["id"]

    item_resp = await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 1,
            "meal_type": "lunch",
            "quantity_servings": 1.0,
        },
    )
    item_id = item_resp.json()["id"]

    response = await auth_client.delete(
        f"/api/v1/meal-plans/{plan_id}/items/{item_id}"
    )
    assert response.status_code == 204


async def test_generate_shopping_list(auth_client, db_session):
    product = await _create_product(db_session, "shopping")

    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Shopping Plan", "week_start_date": "2026-05-25"},
    )
    plan_id = create_resp.json()["id"]

    # Add items to the plan
    await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 0,
            "meal_type": "breakfast",
            "quantity_servings": 1.0,
        },
    )
    await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 2,
            "meal_type": "lunch",
            "quantity_servings": 2.0,
        },
    )

    response = await auth_client.get(
        f"/api/v1/meal-plans/{plan_id}/shopping-list"
    )
    assert response.status_code == 200
    data = response.json()
    assert "id" in data
    assert "items" in data
    assert len(data["items"]) >= 1
    # Total should be aggregated: (1.0 * 100g) + (2.0 * 100g) = 300g
    total_qty = sum(item["quantity"] for item in data["items"])
    assert total_qty == pytest.approx(300.0, rel=0.01)


async def test_generate_shopping_list_is_idempotent(auth_client, db_session):
    """Generating twice for the same plan must not accumulate duplicate lists
    (regression test for the Codex cycle-3 idempotency fix)."""
    from uuid import UUID

    from sqlalchemy import select

    from app.models.shopping_list import ShoppingList

    product = await _create_product(db_session, "idem")
    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Idem Plan", "week_start_date": "2026-06-01"},
    )
    plan_id = create_resp.json()["id"]
    await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 0,
            "meal_type": "breakfast",
            "quantity_servings": 1.0,
        },
    )

    r1 = await auth_client.get(f"/api/v1/meal-plans/{plan_id}/shopping-list")
    assert r1.status_code == 200
    r2 = await auth_client.get(f"/api/v1/meal-plans/{plan_id}/shopping-list")
    assert r2.status_code == 200

    # Exactly one ShoppingList row should exist for this plan after two generations.
    result = await db_session.execute(
        select(ShoppingList).where(ShoppingList.meal_plan_id == UUID(plan_id))
    )
    assert len(result.scalars().all()) == 1


async def test_generate_shopping_list_concurrent_does_not_500(auth_client, db_session, setup_db):
    """Two concurrent generations for the same plan converge to ONE list without
    raising. Regression: B11's uq_shopping_lists_user_plan + a non-conflict-safe
    delete-then-insert writer would 500 (IntegrityError + poisoned session) under
    concurrency; the FOR UPDATE row-lock on the plan serializes them instead.
    (Self-review Wave 9.)"""
    import asyncio
    from uuid import UUID

    from sqlalchemy import select

    from app.models.shopping_list import ShoppingList
    from app.services.shopping_list import generate_shopping_list
    from tests.conftest import TEST_USER_ID

    product = await _create_product(db_session, "concurrent")
    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Concurrent Plan", "week_start_date": "2026-06-08"},
    )
    plan_id = UUID(create_resp.json()["id"])
    await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 0,
            "meal_type": "breakfast",
            "quantity_servings": 1.0,
        },
    )

    _engine, session_factory = setup_db

    async def gen():
        async with session_factory() as s:
            sl = await generate_shopping_list(s, plan_id, TEST_USER_ID)
            lid = sl.id  # capture before commit
            await s.commit()
            return lid

    # Run concurrently — the plan row-lock serializes them, so neither 500s.
    results = await asyncio.gather(gen(), gen())
    assert all(r is not None for r in results)

    result = await db_session.execute(
        select(ShoppingList).where(ShoppingList.meal_plan_id == plan_id)
    )
    assert len(result.scalars().all()) == 1, "exactly one list survives concurrent generation"


async def test_toggle_shopping_item(auth_client, db_session):
    product = await _create_product(db_session, "toggle")

    create_resp = await auth_client.post(
        "/api/v1/meal-plans",
        json={"name": "Toggle Plan", "week_start_date": "2026-06-01"},
    )
    plan_id = create_resp.json()["id"]

    await auth_client.post(
        f"/api/v1/meal-plans/{plan_id}/items",
        json={
            "product_id": str(product.id),
            "day_of_week": 0,
            "meal_type": "dinner",
            "quantity_servings": 1.0,
        },
    )

    # Generate shopping list
    list_resp = await auth_client.get(
        f"/api/v1/meal-plans/{plan_id}/shopping-list"
    )
    list_data = list_resp.json()
    list_id = list_data["id"]
    item_id = list_data["items"][0]["id"]

    # Toggle item checked
    response = await auth_client.patch(
        f"/api/v1/meal-plans/shopping-lists/{list_id}/items/{item_id}/check",
        json={"is_checked": True},
    )
    assert response.status_code == 200
    assert response.json()["is_checked"] is True

    # Toggle back
    response2 = await auth_client.patch(
        f"/api/v1/meal-plans/shopping-lists/{list_id}/items/{item_id}/check",
        json={"is_checked": False},
    )
    assert response2.status_code == 200
    assert response2.json()["is_checked"] is False


async def test_unauthorized_401(client):
    response = await client.post(
        "/api/v1/meal-plans",
        json={"name": "Unauthorized Plan", "week_start_date": "2026-04-06"},
    )
    assert response.status_code == 401
