import uuid
from datetime import date

import pytest

from app.models.meal import Meal, MealItem
from app.models.product import Product


async def _seed_meal_with_product(db_session, user_id, meal_date_str="2026-04-10"):
    """Create a product, a meal, and a meal item for nutrition calculation tests."""
    meal_date = date.fromisoformat(meal_date_str)

    product = Product(
        barcode=f"NUT-{uuid.uuid4().hex[:8]}",
        name="Chicken Breast",
        brand="Generic",
        serving_size_g=100.0,
        calories=165.0,
        protein_g=31.0,
        carbs_g=0.0,
        fat_g=3.6,
        fiber_g=0.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()

    meal = Meal(
        user_id=user_id,
        meal_type="lunch",
        meal_date=meal_date,
    )
    db_session.add(meal)
    await db_session.commit()

    item = MealItem(
        meal_id=meal.id,
        product_id=product.id,
        quantity_servings=2.0,
    )
    db_session.add(item)
    await db_session.commit()

    return product, meal, item


async def test_daily_nutrition_with_meals(auth_client, db_session, test_user):
    await _seed_meal_with_product(db_session, test_user.id, "2026-04-10")

    response = await auth_client.get("/api/v1/nutrition/daily/2026-04-10")
    assert response.status_code == 200
    data = response.json()
    assert data["nutrition_date"] == "2026-04-10"
    # 165 cal * 2 servings = 330
    assert data["total_calories"] == pytest.approx(330.0, rel=0.01)
    # 31g protein * 2 servings = 62
    assert data["total_protein_g"] == pytest.approx(62.0, rel=0.01)
    assert data["meals_count"] == 1


async def test_daily_nutrition_empty(auth_client):
    response = await auth_client.get("/api/v1/nutrition/daily/2020-01-01")
    assert response.status_code == 200
    data = response.json()
    assert data["total_calories"] == 0.0
    assert data["total_protein_g"] == 0.0
    assert data["meals_count"] == 0


async def test_weekly_nutrition(auth_client, db_session, test_user):
    await _seed_meal_with_product(db_session, test_user.id, "2026-04-11")

    response = await auth_client.get(
        "/api/v1/nutrition/weekly",
        params={"start_date": "2026-04-11", "end_date": "2026-04-13"},
    )
    assert response.status_code == 200
    data = response.json()
    # Should have 3 days (11, 12, 13)
    assert len(data) == 3
    # First day has data
    assert data[0]["total_calories"] > 0
    # Other days are empty
    assert data[1]["total_calories"] == 0.0
    assert data[2]["total_calories"] == 0.0


async def test_daily_nutrition_scales_by_grams(auth_client, db_session, test_user):
    """Items logged by grams scale macros by quantity_grams / serving_size_g
    (regression test for the Codex cycle-2 gram-scaling fix)."""
    meal_date = date.fromisoformat("2026-04-14")
    product = Product(
        barcode=f"NUT-{uuid.uuid4().hex[:8]}",
        name="Oats",
        brand="Generic",
        serving_size_g=100.0,
        calories=200.0,
        protein_g=10.0,
        carbs_g=40.0,
        fat_g=4.0,
        fiber_g=8.0,
        source="manual",
    )
    db_session.add(product)
    await db_session.commit()

    meal = Meal(user_id=test_user.id, meal_type="breakfast", meal_date=meal_date)
    db_session.add(meal)
    await db_session.commit()

    # Logged by grams (250g of a 100g serving = 2.5x); servings=1.0 must be ignored.
    item = MealItem(
        meal_id=meal.id,
        product_id=product.id,
        quantity_grams=250.0,
        quantity_servings=1.0,
    )
    db_session.add(item)
    await db_session.commit()

    response = await auth_client.get("/api/v1/nutrition/daily/2026-04-14")
    assert response.status_code == 200
    data = response.json()
    # 250g / 100g = 2.5x → 200*2.5 = 500 cal (NOT 200*1 serving).
    assert data["total_calories"] == pytest.approx(500.0, rel=0.01)
    assert data["total_protein_g"] == pytest.approx(25.0, rel=0.01)


async def test_unauthorized_401(client):
    response = await client.get("/api/v1/nutrition/daily/2026-04-01")
    assert response.status_code == 401
