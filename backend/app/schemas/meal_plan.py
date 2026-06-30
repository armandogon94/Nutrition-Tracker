import uuid
from datetime import date

from pydantic import BaseModel, Field

from app.core.datetime_utils import UTCDateTime
from app.schemas.product import ProductResponse


class MealPlanItemCreate(BaseModel):
    product_id: uuid.UUID
    day_of_week: int = Field(ge=0, le=6)
    meal_type: str = Field(pattern="^(breakfast|lunch|dinner|snack)$")
    quantity_servings: float = Field(default=1.0, gt=0, le=10000)
    quantity_grams: float | None = Field(default=None, gt=0, le=100000)


class MealPlanItemResponse(BaseModel):
    id: uuid.UUID
    product_id: uuid.UUID
    day_of_week: int
    meal_type: str
    quantity_servings: float
    quantity_grams: float | None
    product: ProductResponse
    created_at: UTCDateTime

    model_config = {"from_attributes": True}


class MealPlanCreate(BaseModel):
    # str_strip_whitespace turns a whitespace-only name ("   ") into "" so that
    # min_length=1 rejects it; without stripping, min_length counts the spaces.
    model_config = {"str_strip_whitespace": True}

    name: str = Field(min_length=1, max_length=255)
    week_start_date: date
    notes: str | None = None
    is_template: bool = False


class MealPlanResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    week_start_date: date
    notes: str | None
    is_template: bool
    items: list[MealPlanItemResponse] = []
    created_at: UTCDateTime

    model_config = {"from_attributes": True}


class MealPlanListResponse(BaseModel):
    id: uuid.UUID
    name: str
    week_start_date: date
    is_template: bool
    items_count: int
    created_at: UTCDateTime
