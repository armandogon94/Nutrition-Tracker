from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.exercise import Exercise
from app.schemas.exercise import ExerciseListResponse, ExerciseResponse

router = APIRouter()


def escape_like(s: str) -> str:
    """Escape SQL LIKE wildcard characters."""
    return s.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_")


@router.get("", response_model=ExerciseListResponse)
async def list_exercises(
    muscle: str | None = None,
    equipment: str | None = None,
    difficulty: str | None = None,
    q: str | None = None,
    limit: int = Query(default=50, le=200),
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
) -> ExerciseListResponse:
    query = select(Exercise)
    count_query = select(func.count(Exercise.id))

    if muscle:
        query = query.where(Exercise.primary_muscle == muscle)
        count_query = count_query.where(Exercise.primary_muscle == muscle)
    if equipment:
        query = query.where(Exercise.equipment.ilike(f"%{escape_like(equipment)}%"))
        count_query = count_query.where(Exercise.equipment.ilike(f"%{escape_like(equipment)}%"))
    if difficulty:
        query = query.where(Exercise.difficulty == difficulty)
        count_query = count_query.where(Exercise.difficulty == difficulty)
    if q:
        escaped_q = escape_like(q)
        query = query.where(
            or_(Exercise.name.ilike(f"%{escaped_q}%"), Exercise.primary_muscle.ilike(f"%{escaped_q}%"))
        )
        count_query = count_query.where(
            or_(Exercise.name.ilike(f"%{escaped_q}%"), Exercise.primary_muscle.ilike(f"%{escaped_q}%"))
        )

    total_result = await db.execute(count_query)
    total = total_result.scalar() or 0

    result = await db.execute(
        query.order_by(Exercise.name).offset(offset).limit(limit)
    )
    exercises = list(result.scalars().all())

    return ExerciseListResponse(
        exercises=[ExerciseResponse.model_validate(e) for e in exercises],
        total=total,
    )


@router.get("/{exercise_id}", response_model=ExerciseResponse)
async def get_exercise(exercise_id: UUID, db: AsyncSession = Depends(get_db)) -> Exercise:
    result = await db.execute(select(Exercise).where(Exercise.id == exercise_id))
    exercise = result.scalar_one_or_none()
    if not exercise:
        raise HTTPException(status_code=404, detail="Exercise not found")
    return exercise
