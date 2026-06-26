import uuid
from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.core.datetime_utils import UTCDateTime, to_naive_utc
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
    # str_strip_whitespace turns a whitespace-only name ("   ") into "" so that
    # min_length=1 rejects it; without stripping, min_length counts the spaces.
    model_config = {"str_strip_whitespace": True}

    name: str = Field(min_length=1, max_length=255)
    description: str | None = None
    program_type: str | None = None
    days_per_week: int = Field(ge=1, le=7)


class SessionCreate(BaseModel):
    # Optional client-supplied primary key. The iOS client mints a local UUID
    # the instant a workout starts (its on-device + HealthKit idempotency key)
    # and sends it here so set-logging / completion to /sessions/{id}/... resolve
    # to the SAME row server-side. When omitted, the server mints the id.
    # See Codex review finding #1 (workout local-vs-server UUID mismatch).
    id: uuid.UUID | None = None
    program_id: uuid.UUID | None = None
    program_day_id: uuid.UUID | None = None
    started_at: datetime

    @field_validator("started_at", mode="after")
    @classmethod
    def strip_tz(cls, v: datetime) -> datetime:
        # B9: a tz-aware instant must be converted to UTC BEFORE dropping tzinfo,
        # otherwise e.g. 23:30-05:00 would be stored as 23:30Z instead of 04:30Z.
        return to_naive_utc(v)


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
    completed_at: UTCDateTime

    model_config = {"from_attributes": True}


class SessionResponse(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    program_id: uuid.UUID | None
    program_day_id: uuid.UUID | None
    started_at: UTCDateTime
    completed_at: UTCDateTime | None
    duration_minutes: int | None
    notes: str | None
    sets: list[SetResponse] = []

    model_config = {"from_attributes": True}


class SessionComplete(BaseModel):
    notes: str | None = Field(default=None, max_length=5000)


class PersonalRecordResponse(BaseModel):
    id: uuid.UUID
    exercise: ExerciseResponse
    max_weight_kg: float | None
    max_reps_at_weight: int | None
    estimated_1rm: float | None
    achieved_at: UTCDateTime

    model_config = {"from_attributes": True}


class VolumeByMuscle(BaseModel):
    muscle_group: str
    total_volume: float
    total_sets: int


class WorkoutHistoryEntry(BaseModel):
    id: uuid.UUID
    started_at: UTCDateTime
    completed_at: UTCDateTime | None
    duration_minutes: int | None
    program_name: str | None = None
    day_name: str | None = None
    total_sets: int
    total_volume: float
