from datetime import date
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.models.meal import Meal, MealItem
from app.models.product import Product
from app.schemas.meal import (
    MealCreate,
    MealItemCreate,
    MealItemLogResponse,
    MealItemResponse,
    MealLogRequest,
    MealLogResponse,
    MealResponse,
)

router = APIRouter()


@router.post("", response_model=MealResponse, status_code=201)
async def create_meal(
    data: MealCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> Meal:
    """Create a new meal."""
    meal = Meal(user_id=user_id, **data.model_dump())
    db.add(meal)
    await db.flush()
    await db.refresh(meal)
    return meal


async def _find_or_create_meal(
    db: AsyncSession, *, user_id: UUID, meal_type: str, meal_date: date
) -> Meal:
    """Return the user's meal for (meal_type, meal_date), creating it if absent.

    Mirrors the iOS client's "one meal per type per day" rule so logging a
    second item into today's lunch attaches to the same parent meal.
    """
    result = await db.execute(
        select(Meal).where(
            Meal.user_id == user_id,
            Meal.meal_type == meal_type,
            Meal.meal_date == meal_date,
        )
    )
    meal = result.scalars().first()
    if meal is None:
        meal = Meal(user_id=user_id, meal_type=meal_type, meal_date=meal_date)
        db.add(meal)
        await db.flush()
    return meal


async def _resolve_product_for_log(db: AsyncSession, data: MealLogRequest) -> Product:
    """Resolve (or create) the Product backing a logged item.

    iOS sends TOTAL macros for ``servings`` plus a client-side product id that
    may not exist in our catalog (vision/manual items). We store *per-serving*
    macros so the existing nutrition aggregation (``Product.<macro> *
    quantity_servings``) reproduces the totals iOS sent, and so the response can
    echo them back. If the id already maps to a product we reuse it (keeping
    barcode-sourced catalog rows authoritative).
    """
    servings = data.servings if data.servings > 0 else 1.0

    product: Product | None = None
    if data.product_id:
        try:
            pid = UUID(data.product_id)
        except ValueError:
            pid = None
        if pid is not None:
            product = await db.get(Product, pid)
            if product is not None:
                return product

    # Create a snapshot product carrying per-serving nutrition.
    new_id = uuid4()
    if data.product_id:
        try:
            new_id = UUID(data.product_id)
        except ValueError:
            new_id = uuid4()
    product = Product(
        id=new_id,
        # Barcode is unique + required; synthesize a stable, non-colliding one
        # for client-logged items that have no real barcode.
        barcode=f"log:{new_id}",
        name=data.product_name,
        brand=data.brand,
        serving_size_g=100.0,
        calories=data.calories / servings,
        protein_g=data.protein_g / servings,
        carbs_g=data.carbs_g / servings,
        fat_g=data.fat_g / servings,
        fiber_g=0.0,
        source="manual",
    )
    db.add(product)
    await db.flush()
    return product


def _item_to_log_response(item: MealItem, product: Product) -> MealItemLogResponse:
    """Build the iOS ``MealItemDTO`` snapshot from the stored item + product."""
    servings = item.quantity_servings
    return MealItemLogResponse(
        id=str(item.id),
        product_id=str(item.product_id),
        product_name=product.name,
        brand=product.brand,
        servings=servings,
        calories=product.calories * servings,
        protein_g=product.protein_g * servings,
        carbs_g=product.carbs_g * servings,
        fat_g=product.fat_g * servings,
    )


@router.post("/log", response_model=MealLogResponse, status_code=201)
async def log_meal_item(
    data: MealLogRequest,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> MealLogResponse:
    """Log a single food item, creating today's meal if needed (iOS contract).

    Combined "create meal + add item" matching iOS ``MealService.logItem``.
    Idempotent on ``(meal, client_item_id)``: replaying a queued offline write
    with the same ``client_item_id`` returns the existing item instead of
    inserting a duplicate. Returns the parent meal in the iOS ``MealDTO`` shape
    with snapshot items.
    """
    meal = await _find_or_create_meal(
        db, user_id=user_id, meal_type=data.meal_type, meal_date=data.meal_date
    )

    # Idempotency: if this client_item_id already exists on this meal, return it.
    existing: MealItem | None = None
    if data.client_item_id:
        result = await db.execute(
            select(MealItem).where(
                MealItem.meal_id == meal.id,
                MealItem.client_item_id == data.client_item_id,
            )
        )
        existing = result.scalars().first()

    if existing is not None:
        product = await db.get(Product, existing.product_id)
        item = existing
    else:
        product = await _resolve_product_for_log(db, data)
        item = MealItem(
            meal_id=meal.id,
            product_id=product.id,
            quantity_servings=data.servings,
            client_item_id=data.client_item_id,
        )
        db.add(item)
        await db.flush()

    # Reload the meal's items so the response reflects everything logged so far.
    await db.refresh(meal, attribute_names=["items"])
    items_with_products: list[MealItemLogResponse] = []
    for it in sorted(meal.items, key=lambda x: x.created_at):
        prod = product if it.id == item.id else await db.get(Product, it.product_id)
        items_with_products.append(_item_to_log_response(it, prod))

    return MealLogResponse(
        id=str(meal.id),
        user_id=str(meal.user_id),
        meal_type=meal.meal_type,
        meal_date=meal.meal_date,
        items=items_with_products,
    )


@router.delete("/items/{item_id}", status_code=204)
async def remove_meal_item_by_id(
    item_id: UUID,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Delete a meal item by id alone (iOS ``MealService.deleteItem`` contract).

    Ownership is enforced by joining through the item's parent meal. Idempotent:
    deleting an unknown/already-deleted item returns 204 so the offline-retry
    queue can replay a delete without erroring.
    """
    result = await db.execute(
        select(MealItem, Meal)
        .join(Meal, MealItem.meal_id == Meal.id)
        .where(MealItem.id == item_id)
    )
    row = result.first()
    if row is None:
        return None  # already gone — idempotent success
    item, meal = row
    if meal.user_id != user_id:
        # Don't reveal another user's item; treat as not-found.
        raise HTTPException(status_code=404, detail="Meal item not found")
    await db.delete(item)
    return None


@router.get("/{meal_date}", response_model=list[MealResponse])
async def get_meals_by_date(
    meal_date: date, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
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
    meal_id: UUID, data: MealItemCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> MealItem:
    """Add a food item to a meal."""
    # Verify meal exists and belongs to user
    result = await db.execute(select(Meal).where(Meal.id == meal_id))
    meal = result.scalar_one_or_none()
    if not meal or meal.user_id != user_id:
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
    meal_id: UUID, item_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> None:
    """Remove a food item from a meal."""
    # Verify meal belongs to user
    result = await db.execute(select(Meal).where(Meal.id == meal_id))
    meal = result.scalar_one_or_none()
    if not meal or meal.user_id != user_id:
        raise HTTPException(status_code=404, detail="Meal not found")

    result = await db.execute(
        select(MealItem).where(MealItem.id == item_id, MealItem.meal_id == meal_id)
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Meal item not found")
    await db.delete(item)


@router.delete("/{meal_id}", status_code=204)
async def delete_meal(meal_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)) -> None:
    """Delete an entire meal and its items."""
    result = await db.execute(select(Meal).where(Meal.id == meal_id))
    meal = result.scalar_one_or_none()
    if not meal or meal.user_id != user_id:
        raise HTTPException(status_code=404, detail="Meal not found")
    await db.delete(meal)
