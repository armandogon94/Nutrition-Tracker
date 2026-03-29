from datetime import date
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.meal import Meal, MealItem
from app.models.product import Product
from app.schemas.nutrition import DailyNutritionResponse


async def calculate_daily_nutrition(
    session: AsyncSession, user_id: UUID, nutrition_date: date
) -> DailyNutritionResponse:
    """Calculate daily macro totals from all meals."""
    query = (
        select(
            func.coalesce(func.sum(Product.calories * MealItem.quantity_servings), 0),
            func.coalesce(func.sum(Product.protein_g * MealItem.quantity_servings), 0),
            func.coalesce(func.sum(Product.carbs_g * MealItem.quantity_servings), 0),
            func.coalesce(func.sum(Product.fat_g * MealItem.quantity_servings), 0),
            func.coalesce(func.sum(Product.fiber_g * MealItem.quantity_servings), 0),
            func.count(func.distinct(Meal.id)),
        )
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
