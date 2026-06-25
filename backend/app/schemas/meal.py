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


# ---- POST /meals/log (iOS MealService contract) --------------------------
#
# iOS sends a combined "create the meal + add one item" payload with a full
# nutrition snapshot (calories/macros already multiplied by `servings`). The
# response mirrors the iOS `MealDTO` / `MealItemDTO` (snapshot fields on each
# item, NOT the nested `product` of `MealItemResponse`). `client_item_id`
# makes the write idempotent across offline-queue retries.


class MealLogRequest(BaseModel):
    """Mirrors iOS ``LogMealItemRequest``. ``calories``/macros are the totals
    for ``servings`` (iOS multiplies per-serving values before sending)."""

    meal_type: str = Field(pattern="^(breakfast|lunch|dinner|snack)$")
    meal_date: date
    product_id: str | None = None
    product_name: str = Field(min_length=1, max_length=255)
    brand: str | None = Field(default=None, max_length=255)
    servings: float = Field(gt=0, le=10000)
    calories: float = Field(ge=0, le=10_000_000)
    protein_g: float = Field(ge=0, le=1_000_000)
    carbs_g: float = Field(ge=0, le=1_000_000)
    fat_g: float = Field(ge=0, le=1_000_000)
    client_item_id: str | None = Field(default=None, max_length=64)


class MealItemLogResponse(BaseModel):
    """Mirrors iOS ``MealItemDTO``: snapshot fields, ids as strings."""

    id: str
    product_id: str | None
    product_name: str
    brand: str | None
    servings: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float


class MealLogResponse(BaseModel):
    """Mirrors iOS ``MealDTO``: the parent meal with its snapshot items."""

    id: str
    user_id: str
    meal_type: str
    meal_date: date
    items: list[MealItemLogResponse] = []
