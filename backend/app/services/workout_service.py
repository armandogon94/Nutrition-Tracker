from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.datetime_utils import utcnow_naive
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
    """Check if this set is a new PR. Returns True if it's a PR.

    B7: this is a PostgreSQL upsert rather than select-then-insert so two
    concurrent first-PR sets for the same ``(user_id, exercise_id)`` converge
    to a single row (enforced by ``uq_personal_records_user_exercise``) instead
    of racing into duplicates that later crash ``scalar_one_or_none()``. The PR
    row is only overwritten when the new estimated 1RM is strictly higher
    (``WHERE excluded.estimated_1rm > personal_records.estimated_1rm``), so a
    weaker concurrent set never clobbers a stronger one (no lost update).
    """
    if not weight_kg or weight_kg <= 0:
        return False

    e1rm = estimate_1rm(weight_kg, reps)
    now = utcnow_naive()

    stmt = pg_insert(PersonalRecord).values(
        user_id=user_id,
        exercise_id=exercise_id,
        max_weight_kg=weight_kg,
        max_reps_at_weight=reps,
        estimated_1rm=e1rm,
        achieved_at=now,
    )
    stmt = stmt.on_conflict_do_update(
        constraint="uq_personal_records_user_exercise",
        set_={
            "max_weight_kg": stmt.excluded.max_weight_kg,
            "max_reps_at_weight": stmt.excluded.max_reps_at_weight,
            "estimated_1rm": stmt.excluded.estimated_1rm,
            "achieved_at": stmt.excluded.achieved_at,
        },
        where=stmt.excluded.estimated_1rm > PersonalRecord.estimated_1rm,
    ).returning(PersonalRecord.id, func.coalesce(PersonalRecord.estimated_1rm, 0.0))

    result = await session.execute(stmt)
    row = result.first()

    # Three outcomes:
    #   - row is None  -> conflict, but WHERE failed (not a higher 1RM): not a PR.
    #   - row returned -> either an INSERT (brand-new PR) or an UPDATE that fired
    #     because the new 1RM was strictly higher; both mean "this set is a PR".
    return row is not None


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
