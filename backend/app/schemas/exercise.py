import uuid
from datetime import datetime

from pydantic import BaseModel


class ExerciseResponse(BaseModel):
    id: uuid.UUID
    name: str
    primary_muscle: str
    secondary_muscles: str | None
    equipment: str | None
    difficulty: str | None
    instructions: str | None
    video_url: str | None
    category: str | None

    model_config = {"from_attributes": True}


class ExerciseListResponse(BaseModel):
    exercises: list[ExerciseResponse]
    total: int
