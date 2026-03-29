from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.meal import Meal, MealItem
from app.models.product import Product
from app.schemas.meal import MealCreate, MealItemCreate, MealItemResponse, MealResponse

router = APIRouter()


@router.post("", response_model=MealResponse, status_code=201)
async def create_meal(data: MealCreate, db: AsyncSession = Depends(get_db)) -> Meal:
    """Create a new meal."""
    meal = Meal(**data.model_dump())
    db.add(meal)
    await db.flush()
    await db.refresh(meal)
    return meal


@router.get("/{meal_date}", response_model=list[MealResponse])
async def get_meals_by_date(
    meal_date: date, user_id: UUID, db: AsyncSession = Depends(get_db)
) -> list[Meal]:
    """Get all meals for a specific date."""
    result = await db.execute(
        select(Meal)
        .where(Meal.user_id == user_id, Meal.meal_date == meal_date)
        .order_by(Meal.created_at)
    )
    return list(result.scalars().all())


@router.post("/{meal_id}/items", response_model=MealItemResponse, status_code=201)
async def add_meal_item(
    meal_id: UUID, data: MealItemCreate, db: AsyncSession = Depends(get_db)
) -> MealItem:
    """Add a food item to a meal."""
    # Verify meal exists
    result = await db.execute(select(Meal).where(Meal.id == meal_id))
    meal = result.scalar_one_or_none()
    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")

    # Verify product exists
    result = await db.execute(select(Product).where(Product.id == data.product_id))
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    item = MealItem(meal_id=meal_id, **data.model_dump())
    db.add(item)
    await db.flush()
    await db.refresh(item)
    return item


@router.delete("/{meal_id}/items/{item_id}", status_code=204)
async def remove_meal_item(
    meal_id: UUID, item_id: UUID, db: AsyncSession = Depends(get_db)
) -> None:
    """Remove a food item from a meal."""
    result = await db.execute(
        select(MealItem).where(MealItem.id == item_id, MealItem.meal_id == meal_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Meal item not found")
    await db.delete(item)


@router.delete("/{meal_id}", status_code=204)
async def delete_meal(meal_id: UUID, db: AsyncSession = Depends(get_db)) -> None:
    """Delete an entire meal and its items."""
    result = await db.execute(select(Meal).where(Meal.id == meal_id))
    meal = result.scalar_one_or_none()
    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")
    await db.delete(meal)
