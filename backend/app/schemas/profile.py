from enum import Enum

from pydantic import BaseModel, Field


class ActivityLevel(str, Enum):
    SEDENTARY = "sedentary"
    LIGHT = "light"
    MODERATE = "moderate"
    ACTIVE = "active"
    VERY_ACTIVE = "very_active"


class GoalPreset(str, Enum):
    FAT_LOSS = "fat_loss"
    MAINTENANCE = "maintenance"
    LEAN_BULK = "lean_bulk"
    MUSCLE_GAIN = "muscle_gain"


class ProfileCreate(BaseModel):
    weight_kg: float = Field(ge=20, le=300, description="Body weight in kg")
    height_cm: float = Field(ge=100, le=250, description="Height in cm")
    age: int = Field(ge=13, le=120, description="Age in years")
    sex: str = Field(pattern="^(male|female)$")
    activity_level: ActivityLevel = ActivityLevel.MODERATE


class ProfileResponse(BaseModel):
    weight_kg: float
    height_cm: float
    age: int
    sex: str
    activity_level: str
    bmr: float | None
    tdee: float | None
    goal_preset: str | None
    daily_calories: int | None
    daily_protein_g: int | None
    daily_carbs_g: int | None
    daily_fat_g: int | None

    model_config = {"from_attributes": True}


class GoalPresetUpdate(BaseModel):
    goal_preset: GoalPreset


class CustomGoalUpdate(BaseModel):
    custom_daily_calories: int = Field(gt=0)
    custom_protein_g: int = Field(ge=0)
    custom_carbs_g: int = Field(ge=0)
    custom_fat_g: int = Field(ge=0)


class TDEEResponse(BaseModel):
    bmr: float
    tdee: float
    activity_level: str
    goal_preset: str | None
    daily_calories: int
    daily_protein_g: int
    daily_carbs_g: int
    daily_fat_g: int
