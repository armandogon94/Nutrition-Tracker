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


async def test_weekly_nutrition_multiple_days_aggregate(
    auth_client, db_session, test_user
):
    """B12: data on several days in the range is aggregated per-day correctly
    by the single grouped query (not collapsed or misattributed)."""
    await _seed_meal_with_product(db_session, test_user.id, "2026-07-01")
    await _seed_meal_with_product(db_session, test_user.id, "2026-07-03")

    response = await auth_client.get(
        "/api/v1/nutrition/weekly",
        params={"start_date": "2026-07-01", "end_date": "2026-07-03"},
    )
    assert response.status_code == 200
    data = response.json()
    assert [d["nutrition_date"] for d in data] == [
        "2026-07-01",
        "2026-07-02",
        "2026-07-03",
    ]
    # Day 1 and day 3 have the seeded meal; day 2 is zero-filled.
    assert data[0]["total_calories"] == pytest.approx(330.0, rel=0.01)
    assert data[1]["total_calories"] == 0.0
    assert data[2]["total_calories"] == pytest.approx(330.0, rel=0.01)
    assert data[0]["meals_count"] == 1
    assert data[1]["meals_count"] == 0
    assert data[2]["meals_count"] == 1


async def test_weekly_nutrition_uses_single_grouped_query(
    auth_client, db_session, test_user
):
    """B12 regression: the weekly endpoint must NOT loop one query per day.

    Count the GROUP BY meal_date aggregate statements emitted while serving the
    weekly endpoint. The old day-by-day loop issued one per day (e.g. 7); the
    grouped implementation issues exactly one.
    """
    from sqlalchemy import event

    import app.core.database as db_mod

    await _seed_meal_with_product(db_session, test_user.id, "2026-08-01")

    engine = db_mod.engine.sync_engine
    grouped_selects: list[str] = []

    def _before_cursor_execute(conn, cursor, statement, params, context, executemany):
        normalized = " ".join(statement.lower().split())
        if "from meals" in normalized and "group by" in normalized:
            grouped_selects.append(normalized)

    event.listen(engine, "before_cursor_execute", _before_cursor_execute)
    try:
        response = await auth_client.get(
            "/api/v1/nutrition/weekly",
            params={"start_date": "2026-08-01", "end_date": "2026-08-07"},
        )
    finally:
        event.remove(engine, "before_cursor_execute", _before_cursor_execute)

    assert response.status_code == 200
    assert len(response.json()) == 7
    # Exactly one grouped aggregate over the whole range — not one per day.
    assert len(grouped_selects) == 1, grouped_selects


async def test_unauthorized_401(client):
    response = await client.get("/api/v1/nutrition/daily/2026-04-01")
    assert response.status_code == 401
