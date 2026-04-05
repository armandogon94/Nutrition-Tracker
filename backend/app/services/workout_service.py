from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.exercise import Exercise
from app.models.workout import (
    PersonalRecord,
    WorkoutSession,
    WorkoutSet,
)


def estimate_1rm(weight_kg: float, reps: int) -> float:
    """Average of Brzycki and Epley formulas."""
    if reps <= 0 or weight_kg <= 0:
        return 0.0
    if reps == 1:
        return weight_kg
    if reps >= 37:
        reps = 36  # Cap to prevent division by zero in Brzycki formula
    brzycki = weight_kg * (36.0 / (37.0 - reps))
    epley = weight_kg * (1.0 + reps / 30.0)
    return round((brzycki + epley) / 2, 1)


async def check_and_update_pr(
    session: AsyncSession,
    user_id: UUID,
    exercise_id: UUID,
    weight_kg: float | None,
    reps: int,
) -> bool:
    """Check if this set is a new PR. Returns True if it's a PR."""
    if not weight_kg or weight_kg <= 0:
        return False

    e1rm = estimate_1rm(weight_kg, reps)

    result = await session.execute(
        select(PersonalRecord).where(
            PersonalRecord.user_id == user_id,
            PersonalRecord.exercise_id == exercise_id,
        )
    )
    existing_pr = result.scalar_one_or_none()

    if not existing_pr:
        pr = PersonalRecord(
            user_id=user_id,
            exercise_id=exercise_id,
            max_weight_kg=weight_kg,
            max_reps_at_weight=reps,
            estimated_1rm=e1rm,
            achieved_at=datetime.utcnow(),
        )
        session.add(pr)
        return True

    if e1rm > (existing_pr.estimated_1rm or 0):
        existing_pr.max_weight_kg = weight_kg
        existing_pr.max_reps_at_weight = reps
        existing_pr.estimated_1rm = e1rm
        existing_pr.achieved_at = datetime.utcnow()
        return True

    return False


async def get_volume_by_muscle(
    session: AsyncSession, user_id: UUID, start_date: datetime, end_date: datetime
) -> list[dict]:
    """Calculate total volume per muscle group for a date range."""
    query = (
        select(
            Exercise.primary_muscle,
            func.sum(WorkoutSet.reps * func.coalesce(WorkoutSet.weight_kg, 0)).label("total_volume"),
            func.count(WorkoutSet.id).label("total_sets"),
        )
        .select_from(WorkoutSet)
        .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
        .join(Exercise, WorkoutSet.exercise_id == Exercise.id)
        .where(
            WorkoutSession.user_id == user_id,
            WorkoutSession.started_at >= start_date,
            WorkoutSession.started_at <= end_date,
        )
        .group_by(Exercise.primary_muscle)
        .order_by(func.sum(WorkoutSet.reps * func.coalesce(WorkoutSet.weight_kg, 0)).desc())
    )

    result = await session.execute(query)
    return [
        {"muscle_group": row[0], "total_volume": float(row[1]), "total_sets": int(row[2])}
        for row in result.all()
    ]


async def get_exercise_history(
    session: AsyncSession, user_id: UUID, exercise_id: UUID, limit: int = 20
) -> list[dict]:
    """Get recent sets for an exercise, for pre-filling and chart data."""
    query = (
        select(WorkoutSet, WorkoutSession.started_at)
        .join(WorkoutSession, WorkoutSet.session_id == WorkoutSession.id)
        .where(
            WorkoutSession.user_id == user_id,
            WorkoutSet.exercise_id == exercise_id,
        )
        .order_by(WorkoutSession.started_at.desc(), WorkoutSet.set_number)
        .limit(limit)
    )

    result = await session.execute(query)
    return [
        {
            "set_number": row[0].set_number,
            "reps": row[0].reps,
            "weight_kg": row[0].weight_kg,
            "rpe": row[0].rpe,
            "date": row[1].isoformat(),
        }
        for row in result.all()
    ]
