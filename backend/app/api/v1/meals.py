from datetime import date
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
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
    """Create a meal, or return the existing one for the same natural key.

    ``meals`` has a UNIQUE (user_id, meal_type, meal_date) constraint
    (``uq_meals_user_type_date``), so a raw insert of a duplicate natural key
    raised an unhandled ``IntegrityError`` (surfacing as a 500). We route through
    the same conflict-safe find-or-create used by ``POST /meals/log``: a
    duplicate request idempotently converges on the single existing meal rather
    than erroring, and concurrent first-creates never duplicate.
    """
    return await _find_or_create_meal(
        db, user_id=user_id, meal_type=data.meal_type, meal_date=data.meal_date
    )


async def _select_meal(
    db: AsyncSession, *, user_id: UUID, meal_type: str, meal_date: date
) -> Meal | None:
    result = await db.execute(
        select(Meal).where(
            Meal.user_id == user_id,
            Meal.meal_type == meal_type,
            Meal.meal_date == meal_date,
        )
    )
    return result.scalars().first()


async def _find_or_create_meal(
    db: AsyncSession, *, user_id: UUID, meal_type: str, meal_date: date
) -> Meal:
    """Return the user's meal for (meal_type, meal_date), creating it if absent.

    Mirrors the iOS client's "one meal per type per day" rule so logging a
    second item into today's lunch attaches to the same parent meal.

    Atomic under concurrency: ``INSERT ... ON CONFLICT DO NOTHING`` against the
    ``uq_meals_user_type_date`` constraint never raises, so two simultaneous
    first logs cannot create duplicate parent meals — whoever loses the race is a
    no-op insert. We then re-select by the natural key to return the single
    canonical ORM row (whether we created it or the concurrent request did).
    """
    await db.execute(
        pg_insert(Meal)
        .values(user_id=user_id, meal_type=meal_type, meal_date=meal_date)
        .on_conflict_do_nothing(
            index_elements=["user_id", "meal_type", "meal_date"]
        )
    )
    meal = await _select_meal(
        db, user_id=user_id, meal_type=meal_type, meal_date=meal_date
    )
    if meal is None:  # pragma: no cover - row must exist after insert-or-conflict
        raise HTTPException(status_code=500, detail="Failed to resolve meal")
    return meal


def _parse_product_id(raw: str | None) -> UUID | None:
    """Best-effort parse of a client-supplied product id into a UUID."""
    if not raw:
        return None
    try:
        return UUID(raw)
    except ValueError:
        return None


async def _resolve_product_for_log(
    db: AsyncSession, data: MealLogRequest
) -> tuple[Product, bool]:
    """Resolve (or create) the Product backing a logged item.

    Returns ``(product, created_new)`` where ``created_new`` is True only when
    THIS request's INSERT actually landed the snapshot row. B4: the caller uses
    this flag to decide whether a losing-race orphan cleanup is safe — a
    pre-existing catalog row (reused via the early ``db.get``) or a snapshot a
    concurrent request created must NEVER be deleted by this request.

    iOS sends TOTAL macros for ``servings`` plus a client-side product id that
    may not exist in our catalog (vision/manual items). We store *per-serving*
    macros so the existing nutrition aggregation (``Product.<macro> *
    quantity_servings``) reproduces the totals iOS sent, and so the response can
    echo them back. If the id already maps to a product we reuse it (keeping
    barcode-sourced catalog rows authoritative).

    Atomic under concurrency: ``Product.id`` (PK) and ``Product.barcode`` are
    both unique, and the synthesized barcode (``log:{id}``) is derived from the
    id, so two concurrent replays carrying the SAME new ``product_id`` would
    otherwise both miss the read and both try to INSERT the same row — the loser
    hits a unique violation that poisons the session and 500s. We instead insert
    via ``INSERT ... ON CONFLICT DO NOTHING RETURNING id`` (which never raises,
    covering both the id and barcode constraints): a non-empty RETURNING means we
    created it; an empty one means a concurrent request did, so we re-select by
    id and report ``created_new=False``.
    """
    # B5/Flash A7: clamp the divisor so a tiny-but-positive servings value can't
    # blow up the per-serving macro math (overflow / inf). Pydantic already
    # rejects <= 0; this is defense in depth for direct/internal callers.
    servings = max(data.servings, 0.01)

    pid = _parse_product_id(data.product_id)
    if pid is not None:
        # Reuse an existing catalog/snapshot row if the id already maps to one.
        product = await db.get(Product, pid)
        if product is not None:
            return product, False

    # Snapshot id: honor the client's id when valid, else mint a fresh one.
    new_id = pid if pid is not None else uuid4()
    inserted_id = (
        await db.execute(
            pg_insert(Product)
            .values(
                id=new_id,
                # Barcode is unique + required; synthesize a stable, non-colliding
                # one for client-logged items that have no real barcode. Derived
                # from the id so an id-conflict and a barcode-conflict are the same
                # row (re-selecting by id always finds the winner).
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
            .on_conflict_do_nothing()
            .returning(Product.id)
        )
    ).scalar_one_or_none()

    created_new = inserted_id is not None
    product = await db.get(Product, new_id)
    if product is None:  # pragma: no cover - row must exist after insert-or-conflict
        raise HTTPException(status_code=500, detail="Failed to resolve product")
    return product, created_new


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


async def _select_item_by_client_id(
    db: AsyncSession, *, meal_id: UUID, client_item_id: str
) -> MealItem | None:
    result = await db.execute(
        select(MealItem).where(
            MealItem.meal_id == meal_id,
            MealItem.client_item_id == client_item_id,
        )
    )
    return result.scalars().first()


async def _get_or_create_item(
    db: AsyncSession, *, meal_id: UUID, data: MealLogRequest
) -> tuple[MealItem, Product]:
    """Return the (item, product) for this log, idempotent on client_item_id.

    Atomic under concurrent offline-retry traffic via ``INSERT ... ON CONFLICT
    DO NOTHING`` against the ``uq_meal_items_meal_client_item`` partial unique
    index — the insert never raises, so the session is never poisoned. If we lose
    the race (RETURNING is empty), we return the item the winner committed
    instead, discarding our own snapshot product only when THIS request newly
    created it as an orphan ``log:`` snapshot (B4).

    With no client_item_id there is no idempotency key (the partial index
    excludes NULLs), so the insert always lands as a fresh row.
    """
    # Fast path: an exact replay (same client_item_id already stored).
    if data.client_item_id:
        existing = await _select_item_by_client_id(
            db, meal_id=meal_id, client_item_id=data.client_item_id
        )
        if existing is not None:
            product = await db.get(Product, existing.product_id)
            return existing, product

    product, created_new = await _resolve_product_for_log(db, data)

    stmt = (
        pg_insert(MealItem)
        .values(
            meal_id=meal_id,
            product_id=product.id,
            quantity_servings=data.servings,
            client_item_id=data.client_item_id,
        )
        .returning(MealItem.id)
    )
    if data.client_item_id:
        stmt = stmt.on_conflict_do_nothing(
            index_elements=["meal_id", "client_item_id"],
            index_where=MealItem.client_item_id.isnot(None),
        )

    inserted_id = (await db.execute(stmt)).scalar_one_or_none()

    if inserted_id is not None:
        item = await db.get(MealItem, inserted_id)
        return item, product

    # Lost the concurrent race on this client_item_id. Return the winner's row.
    existing = await _select_item_by_client_id(
        db, meal_id=meal_id, client_item_id=data.client_item_id
    )
    if existing is None:  # pragma: no cover - conflict implies a row exists
        raise HTTPException(status_code=500, detail="Failed to resolve meal item")
    # B4: only clean up a snapshot THIS request newly created and that is a
    # genuinely-orphaned log snapshot — never a pre-existing shared catalog row
    # (which `created_new=False` covers) and never a real-barcode product. This
    # prevents a losing race from deleting another user's catalog product.
    if (
        existing.product_id != product.id
        and created_new
        and product.source == "manual"
        and product.barcode.startswith("log:")
    ):
        await db.delete(product)
    winner_product = await db.get(Product, existing.product_id)
    return existing, winner_product


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

    item, product = await _get_or_create_item(db, meal_id=meal.id, data=data)

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
