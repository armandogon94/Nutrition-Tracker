from collections import defaultdict
from uuid import UUID

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.meal_plan import MealPlan, MealPlanItem
from app.models.product import Product
from app.models.shopping_list import ShoppingList, ShoppingListItem

# Map product categories to grocery sections
CATEGORY_MAP = {
    "produce": "Frutas y Verduras",
    "meat": "Carnes y Aves",
    "seafood": "Pescados y Mariscos",
    "dairy": "Lácteos y Huevos",
    "bakery": "Panadería",
    "grains": "Granos y Cereales",
    "canned": "Enlatados y Conservas",
    "condiments": "Condimentos y Especias",
    "oils": "Aceites y Vinagres",
    "beverages": "Bebidas",
    "frozen": "Congelados",
    "snacks": "Botanas y Snacks",
}


async def generate_shopping_list(
    session: AsyncSession, meal_plan_id: UUID, user_id: UUID
) -> ShoppingList:
    """Generate shopping list from meal plan by aggregating ingredients."""
    # Verify the meal plan exists AND belongs to the requesting user (no IDOR):
    # never aggregate or generate a list from another user's plan.
    result = await session.execute(
        select(MealPlan).where(
            MealPlan.id == meal_plan_id,
            MealPlan.user_id == user_id,
        )
    )
    meal_plan = result.scalar_one_or_none()
    if not meal_plan:
        raise ValueError("Meal plan not found")

    # Get all items with products
    result = await session.execute(
        select(MealPlanItem)
        .where(MealPlanItem.meal_plan_id == meal_plan_id)
    )
    items = list(result.scalars().all())

    # Aggregate by product
    aggregated: dict[str, dict] = defaultdict(lambda: {"quantity": 0.0, "unit": "g", "category": "Otros"})
    for item in items:
        product = item.product
        key = product.name.lower().strip()
        grams = (item.quantity_grams or product.serving_size_g * item.quantity_servings)
        aggregated[key]["quantity"] += grams
        aggregated[key]["unit"] = "g"
        aggregated[key]["name"] = product.name
        aggregated[key]["category"] = _categorize_product(product)

    # Idempotent regeneration: drop any prior list(s) for this (user, plan)
    # so repeated generation replaces rather than accumulating duplicate rows.
    existing = await session.execute(
        select(ShoppingList.id).where(
            ShoppingList.user_id == user_id,
            ShoppingList.meal_plan_id == meal_plan_id,
        )
    )
    existing_ids = [row[0] for row in existing.all()]
    if existing_ids:
        await session.execute(
            delete(ShoppingListItem).where(ShoppingListItem.shopping_list_id.in_(existing_ids))
        )
        await session.execute(
            delete(ShoppingList).where(ShoppingList.id.in_(existing_ids))
        )
        await session.flush()

    # Create shopping list
    shopping_list = ShoppingList(
        user_id=user_id,
        meal_plan_id=meal_plan_id,
        name=f"Lista - {meal_plan.name}",
    )
    session.add(shopping_list)
    await session.flush()

    for _key, data in sorted(aggregated.items()):
        item = ShoppingListItem(
            shopping_list_id=shopping_list.id,
            ingredient_name=data["name"],
            quantity=round(data["quantity"], 1),
            unit=data["unit"],
            category=data["category"],
        )
        session.add(item)

    await session.flush()
    await session.refresh(shopping_list)
    return shopping_list


def _categorize_product(product: Product) -> str:
    """Simple keyword-based categorization."""
    name = (product.name or "").lower()
    brand = (product.brand or "").lower()
    combined = f"{name} {brand}"

    if any(w in combined for w in ["chicken", "pollo", "beef", "res", "pork", "cerdo", "meat", "carne"]):
        return "Carnes y Aves"
    if any(w in combined for w in ["milk", "leche", "cheese", "queso", "yogurt", "egg", "huevo"]):
        return "Lácteos y Huevos"
    if any(w in combined for w in ["bread", "pan", "tortilla"]):
        return "Panadería"
    if any(w in combined for w in ["rice", "arroz", "pasta", "bean", "frijol", "lentil", "oat", "avena"]):
        return "Granos y Cereales"
    if any(w in combined for w in ["juice", "jugo", "water", "agua", "soda", "refresco"]):
        return "Bebidas"
    if any(w in combined for w in ["oil", "aceite", "vinegar", "vinagre"]):
        return "Aceites y Vinagres"
    if any(w in combined for w in ["chip", "nut", "nuez", "snack"]):
        return "Botanas y Snacks"
    return "Otros"
