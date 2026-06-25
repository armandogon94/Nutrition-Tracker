from datetime import date

from pydantic import BaseModel, Field


class DailyNutritionResponse(BaseModel):
    nutrition_date: date
    total_calories: float
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    total_fiber_g: float
    meals_count: int

    model_config = {"from_attributes": True}


class NutritionGoalUpdate(BaseModel):
    daily_calories: int = Field(default=2000, ge=800, le=10000)
    daily_protein_g: int = Field(default=150, ge=0, le=500)
    daily_carbs_g: int = Field(default=250, ge=0, le=1000)
    daily_fat_g: int = Field(default=65, ge=0, le=500)


class NutritionGoalResponse(BaseModel):
    daily_calories: int
    daily_protein_g: int
    daily_carbs_g: int
    daily_fat_g: int

    model_config = {"from_attributes": True}


class FoodRecognitionResponse(BaseModel):
    """Response for ``POST /api/v1/nutrition/recognize``.

    Mirrors the iOS ``VisionRecognitionResponse`` DTO exactly (same field
    names / optionality) so ``VisionService.recognize`` decodes it directly:
    ``{food, grams, confidence, calories?, protein_g?, carbs_g?, fat_g?}``.
    ``confidence`` is a free-form string ("high"/"medium"/"low") to stay loose
    with model output. Macros are per the estimated ``grams`` portion and may be
    null when the model declines to estimate them.
    """

    food: str
    grams: float
    confidence: str
    calories: float | None = None
    protein_g: float | None = None
    carbs_g: float | None = None
    fat_g: float | None = None
