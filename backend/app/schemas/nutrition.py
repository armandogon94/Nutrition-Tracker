from datetime import date

from pydantic import BaseModel


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
    daily_calories: int = 2000
    daily_protein_g: int = 150
    daily_carbs_g: int = 250
    daily_fat_g: int = 65


class NutritionGoalResponse(BaseModel):
    daily_calories: int
    daily_protein_g: int
    daily_carbs_g: int
    daily_fat_g: int

    model_config = {"from_attributes": True}
