import uuid
from datetime import date

from pydantic import BaseModel, Field

from app.core.datetime_utils import UTCDateTime
from app.schemas.product import ProductResponse


class MealItemCreate(BaseModel):
    product_id: uuid.UUID
    quantity_servings: float = 1.0
    quantity_grams: float | None = None


class MealItemResponse(BaseModel):
    id: uuid.UUID
    product_id: uuid.UUID
    quantity_servings: float
    quantity_grams: float | None
    product: ProductResponse
    created_at: UTCDateTime

    model_config = {"from_attributes": True}


class MealCreate(BaseModel):
    meal_type: str = Field(default="breakfast", pattern="^(breakfast|lunch|dinner|snack)$")
    meal_date: date


class MealResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    meal_type: str
    meal_date: date
    items: list[MealItemResponse] = []
    created_at: UTCDateTime

    model_config = {"from_attributes": True}
