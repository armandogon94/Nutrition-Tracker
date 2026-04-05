import uuid
from datetime import datetime

from pydantic import BaseModel


class ShoppingListItemResponse(BaseModel):
    id: uuid.UUID
    ingredient_name: str
    quantity: float
    unit: str | None
    category: str | None
    is_checked: bool

    model_config = {"from_attributes": True}


class ShoppingListResponse(BaseModel):
    id: uuid.UUID
    name: str | None
    meal_plan_id: uuid.UUID | None
    items: list[ShoppingListItemResponse] = []
    generated_at: datetime

    model_config = {"from_attributes": True}


class ShoppingItemCheck(BaseModel):
    is_checked: bool
