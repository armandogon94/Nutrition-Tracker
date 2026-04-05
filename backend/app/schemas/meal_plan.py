import uuid
from datetime import date, datetime

from pydantic import BaseModel, Field

from app.schemas.product import ProductResponse


class MealPlanItemCreate(BaseModel):
    product_id: uuid.UUID
    day_of_week: int = Field(ge=0, le=6)
    meal_type: str = Field(pattern="^(breakfast|lunch|dinner|snack)$")
    quantity_servings: float = 1.0
    quantity_grams: float | None = None


class MealPlanItemResponse(BaseModel):
    id: uuid.UUID
    product_id: uuid.UUID
    day_of_week: int
    meal_type: str
    quantity_servings: float
    quantity_grams: float | None
    product: ProductResponse
    created_at: datetime

    model_config = {"from_attributes": True}


class MealPlanCreate(BaseModel):
    name: str = Field(max_length=255)
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
    created_at: datetime

    model_config = {"from_attributes": True}


class MealPlanListResponse(BaseModel):
    id: uuid.UUID
    name: str
    week_start_date: date
    is_template: bool
    items_count: int
    created_at: datetime
