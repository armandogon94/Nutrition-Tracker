from datetime import date, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.meal import Meal, MealItem
from app.models.product import Product
from app.schemas.nutrition import DailyNutritionResponse


def _serving_factor():
    """Per-item scaling factor for macro aggregation.

    When an item is logged by grams, scale macros by quantity_grams /
    serving_size_g; otherwise fall back to quantity_servings.

    B5 / Flash A7: the divisor is floored to 0.01 (``greatest(serving_size_g,
    0.01)``) so a zero-or-tiny serving size can't blow the division up into
    inf/overflow. This mirrors the ``max(servings, 0.01)`` clamp on the write
    path in ``meals._resolve_product_for_log``.
    """
    return func.coalesce(
        MealItem.quantity_grams / func.greatest(Product.serving_size_g, 0.01),
        MealItem.quantity_servings,
    )


def _macro_aggregates(serving_factor):
    """The (calories, protein, carbs, fat, fiber, distinct-meal-count) selects
    shared by the daily and weekly aggregation queries."""
    return (
        func.coalesce(func.sum(Product.calories * serving_factor), 0),
        func.coalesce(func.sum(Product.protein_g * serving_factor), 0),
        func.coalesce(func.sum(Product.carbs_g * serving_factor), 0),
        func.coalesce(func.sum(Product.fat_g * serving_factor), 0),
        func.coalesce(func.sum(Product.fiber_g * serving_factor), 0),
        func.count(func.distinct(Meal.id)),
    )


async def calculate_daily_nutrition(
    session: AsyncSession, user_id: UUID, nutrition_date: date
) -> DailyNutritionResponse:
    """Calculate daily macro totals from all meals."""
    serving_factor = _serving_factor()
    query = (
        select(*_macro_aggregates(serving_factor))
        .select_from(Meal)
        .join(MealItem, Meal.id == MealItem.meal_id)
        .join(Product, MealItem.product_id == Product.id)
        .where(Meal.user_id == user_id, Meal.meal_date == nutrition_date)
    )

    result = await session.execute(query)
    row = result.one()

    return DailyNutritionResponse(
        nutrition_date=nutrition_date,
        total_calories=float(row[0]),
        total_protein_g=float(row[1]),
        total_carbs_g=float(row[2]),
        total_fat_g=float(row[3]),
        total_fiber_g=float(row[4]),
        meals_count=int(row[5]),
    )


async def calculate_weekly_nutrition(
    session: AsyncSession, user_id: UUID, start_date: date, end_date: date
) -> list[DailyNutritionResponse]:
    """Calculate daily macro totals for an inclusive date range in ONE query.

    B12: the previous implementation looped day-by-day, issuing up to ~91
    aggregate queries. This runs a single grouped aggregate over the whole range
    (GROUP BY meal_date) and zero-fills missing days in memory, preserving the
    per-day response shape and ordering (start_date .. end_date inclusive).
    """
    serving_factor = _serving_factor()
    query = (
        select(Meal.meal_date, *_macro_aggregates(serving_factor))
        .select_from(Meal)
        .join(MealItem, Meal.id == MealItem.meal_id)
        .join(Product, MealItem.product_id == Product.id)
        .where(
            Meal.user_id == user_id,
            Meal.meal_date >= start_date,
            Meal.meal_date <= end_date,
        )
        .group_by(Meal.meal_date)
    )

    result = await session.execute(query)
    by_date: dict[date, DailyNutritionResponse] = {
        row[0]: DailyNutritionResponse(
            nutrition_date=row[0],
            total_calories=float(row[1]),
            total_protein_g=float(row[2]),
            total_carbs_g=float(row[3]),
            total_fat_g=float(row[4]),
            total_fiber_g=float(row[5]),
            meals_count=int(row[6]),
        )
        for row in result.all()
    }

    days: list[DailyNutritionResponse] = []
    current = start_date
    while current <= end_date:
        days.append(
            by_date.get(
                current,
                DailyNutritionResponse(
                    nutrition_date=current,
                    total_calories=0.0,
                    total_protein_g=0.0,
                    total_carbs_g=0.0,
                    total_fat_g=0.0,
                    total_fiber_g=0.0,
                    meals_count=0,
                ),
            )
        )
        current += timedelta(days=1)
    return days
