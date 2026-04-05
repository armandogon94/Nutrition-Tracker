from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.models.meal_plan import MealPlan, MealPlanItem
from app.models.product import Product
from app.models.shopping_list import ShoppingList, ShoppingListItem
from app.schemas.meal_plan import (
    MealPlanCreate,
    MealPlanItemCreate,
    MealPlanItemResponse,
    MealPlanResponse,
)
from app.schemas.shopping import ShoppingItemCheck, ShoppingListResponse
from app.services.shopping_list import generate_shopping_list

router = APIRouter()


@router.post("", response_model=MealPlanResponse, status_code=201)
async def create_meal_plan(
    data: MealPlanCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> MealPlan:
    plan = MealPlan(user_id=user_id, **data.model_dump())
    db.add(plan)
    await db.flush()
    await db.refresh(plan)
    return plan


@router.get("", response_model=list[MealPlanResponse])
async def list_meal_plans(
    user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> list[MealPlan]:
    result = await db.execute(
        select(MealPlan).where(MealPlan.user_id == user_id).order_by(MealPlan.week_start_date.desc())
    )
    return list(result.scalars().all())


@router.get("/{plan_id}", response_model=MealPlanResponse)
async def get_meal_plan(plan_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)) -> MealPlan:
    result = await db.execute(select(MealPlan).where(MealPlan.id == plan_id))
    plan = result.scalar_one_or_none()
    if not plan or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Meal plan not found")
    return plan


@router.delete("/{plan_id}", status_code=204)
async def delete_meal_plan(plan_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)) -> None:
    result = await db.execute(select(MealPlan).where(MealPlan.id == plan_id))
    plan = result.scalar_one_or_none()
    if not plan or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Meal plan not found")
    await db.delete(plan)


@router.post("/{plan_id}/items", response_model=MealPlanItemResponse, status_code=201)
async def add_meal_plan_item(
    plan_id: UUID, data: MealPlanItemCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> MealPlanItem:
    # Verify plan exists and belongs to user
    result = await db.execute(select(MealPlan).where(MealPlan.id == plan_id))
    plan = result.scalar_one_or_none()
    if not plan or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Meal plan not found")

    # Verify product exists
    result = await db.execute(select(Product).where(Product.id == data.product_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Product not found")

    item = MealPlanItem(meal_plan_id=plan_id, **data.model_dump())
    db.add(item)
    await db.flush()
    await db.refresh(item)
    return item


@router.delete("/{plan_id}/items/{item_id}", status_code=204)
async def remove_meal_plan_item(
    plan_id: UUID, item_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> None:
    # Verify plan belongs to user
    result = await db.execute(select(MealPlan).where(MealPlan.id == plan_id))
    plan = result.scalar_one_or_none()
    if not plan or plan.user_id != user_id:
        raise HTTPException(status_code=404, detail="Meal plan not found")

    result = await db.execute(
        select(MealPlanItem).where(MealPlanItem.id == item_id, MealPlanItem.meal_plan_id == plan_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Meal plan item not found")
    await db.delete(item)


@router.get("/{plan_id}/shopping-list", response_model=ShoppingListResponse)
async def generate_plan_shopping_list(
    plan_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> ShoppingListResponse:
    try:
        shopping_list = await generate_shopping_list(db, plan_id, user_id)
        return shopping_list
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.patch("/shopping-lists/{list_id}/items/{item_id}/check")
async def toggle_shopping_item(
    list_id: UUID, item_id: UUID, data: ShoppingItemCheck, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> dict:
    # Verify shopping list belongs to user
    list_result = await db.execute(select(ShoppingList).where(ShoppingList.id == list_id))
    shopping_list = list_result.scalar_one_or_none()
    if not shopping_list or shopping_list.user_id != user_id:
        raise HTTPException(status_code=404, detail="Shopping list not found")

    result = await db.execute(
        select(ShoppingListItem).where(
            ShoppingListItem.id == item_id,
            ShoppingListItem.shopping_list_id == list_id,
        )
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Shopping list item not found")
    item.is_checked = data.is_checked
    return {"id": str(item.id), "is_checked": item.is_checked}
