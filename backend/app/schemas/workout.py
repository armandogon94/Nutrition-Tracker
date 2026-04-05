import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.exercise import ExerciseResponse


class WorkoutProgramExerciseResponse(BaseModel):
    id: uuid.UUID
    exercise: ExerciseResponse
    set_count: int
    rep_min: int | None
    rep_max: int | None
    rest_seconds: int | None
    exercise_order: int
    notes: str | None

    model_config = {"from_attributes": True}


class WorkoutProgramDayResponse(BaseModel):
    id: uuid.UUID
    day_number: int
    day_name: str | None
    focus: str | None
    description: str | None
    exercises: list[WorkoutProgramExerciseResponse] = []

    model_config = {"from_attributes": True}


class WorkoutProgramResponse(BaseModel):
    id: uuid.UUID
    name: str
    description: str | None
    program_type: str | None
    days_per_week: int
    difficulty: str | None
    is_preset: bool
    days: list[WorkoutProgramDayResponse] = []

    model_config = {"from_attributes": True}


class WorkoutProgramListResponse(BaseModel):
    id: uuid.UUID
    name: str
    description: str | None
    program_type: str | None
    days_per_week: int
    difficulty: str | None
    is_preset: bool

    model_config = {"from_attributes": True}


class WorkoutProgramCreate(BaseModel):
    name: str = Field(max_length=255)
    description: str | None = None
    program_type: str | None = None
    days_per_week: int = Field(ge=1, le=7)


class SessionCreate(BaseModel):
    program_id: uuid.UUID | None = None
    program_day_id: uuid.UUID | None = None
    started_at: datetime


class SetCreate(BaseModel):
    exercise_id: uuid.UUID
    set_number: int = Field(ge=1, le=100)
    reps: int = Field(ge=0, le=1000)
    weight_kg: float | None = Field(default=None, ge=0, le=1000)
    rpe: float | None = Field(default=None, ge=1, le=10)


class SetResponse(BaseModel):
    id: uuid.UUID
    exercise_id: uuid.UUID
    exercise: ExerciseResponse
    set_number: int
    reps: int
    weight_kg: float | None
    rpe: float | None
    is_pr: bool
    completed_at: datetime

    model_config = {"from_attributes": True}


class SessionResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    program_id: uuid.UUID | None
    program_day_id: uuid.UUID | None
    started_at: datetime
    completed_at: datetime | None
    duration_minutes: int | None
    notes: str | None
    sets: list[SetResponse] = []

    model_config = {"from_attributes": True}


class SessionComplete(BaseModel):
    notes: str | None = None


class PersonalRecordResponse(BaseModel):
    id: uuid.UUID
    exercise: ExerciseResponse
    max_weight_kg: float | None
    max_reps_at_weight: int | None
    estimated_1rm: float | None
    achieved_at: datetime

    model_config = {"from_attributes": True}


class VolumeByMuscle(BaseModel):
    muscle_group: str
    total_volume: float
    total_sets: int


class WorkoutHistoryEntry(BaseModel):
    id: uuid.UUID
    started_at: datetime
    completed_at: datetime | None
    duration_minutes: int | None
    program_name: str | None = None
    day_name: str | None = None
    total_sets: int
    total_volume: float
