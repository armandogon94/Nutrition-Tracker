from datetime import datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.models.workout import (
    PersonalRecord,
    WorkoutProgram,
    WorkoutProgramDay,
    WorkoutSession,
    WorkoutSet,
)
from app.schemas.workout import (
    PersonalRecordResponse,
    SessionComplete,
    SessionCreate,
    SessionResponse,
    SetCreate,
    SetResponse,
    VolumeByMuscle,
    WorkoutHistoryEntry,
    WorkoutProgramCreate,
    WorkoutProgramListResponse,
    WorkoutProgramResponse,
)
from app.services.workout_service import check_and_update_pr, get_volume_by_muscle

router = APIRouter()


# --- Programs ---

@router.get("/programs", response_model=list[WorkoutProgramListResponse])
async def list_programs(
    user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> list[WorkoutProgram]:
    query = select(WorkoutProgram).where(
        (WorkoutProgram.is_preset == True) | (WorkoutProgram.user_id == user_id)  # noqa: E712
    )
    result = await db.execute(query.order_by(WorkoutProgram.name))
    return list(result.scalars().all())


@router.get("/programs/{program_id}", response_model=WorkoutProgramResponse)
async def get_program(program_id: UUID, db: AsyncSession = Depends(get_db)) -> WorkoutProgram:
    result = await db.execute(select(WorkoutProgram).where(WorkoutProgram.id == program_id))
    program = result.scalar_one_or_none()
    if not program:
        raise HTTPException(status_code=404, detail="Program not found")
    return program


@router.post("/programs", response_model=WorkoutProgramListResponse, status_code=201)
async def create_program(
    data: WorkoutProgramCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> WorkoutProgram:
    program = WorkoutProgram(user_id=user_id, **data.model_dump())
    db.add(program)
    await db.flush()
    await db.refresh(program)
    return program


# --- Sessions ---

@router.post("/sessions", response_model=SessionResponse, status_code=201)
async def start_session(
    data: SessionCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> WorkoutSession:
    session_obj = WorkoutSession(user_id=user_id, **data.model_dump())
    db.add(session_obj)
    await db.flush()
    await db.refresh(session_obj)
    return session_obj


@router.get("/sessions/{session_id}", response_model=SessionResponse)
async def get_session(session_id: UUID, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)) -> WorkoutSession:
    result = await db.execute(select(WorkoutSession).where(WorkoutSession.id == session_id))
    ws = result.scalar_one_or_none()
    if not ws or ws.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found")
    return ws


@router.post("/sessions/{session_id}/sets", response_model=SetResponse, status_code=201)
async def log_set(
    session_id: UUID, data: SetCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> WorkoutSet:
    # Verify session exists and belongs to user
    result = await db.execute(select(WorkoutSession).where(WorkoutSession.id == session_id))
    ws = result.scalar_one_or_none()
    if not ws or ws.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found")
    if ws.completed_at is not None:
        raise HTTPException(status_code=409, detail="Cannot add sets to a completed session")

    # Check for PR
    is_pr = await check_and_update_pr(db, user_id, data.exercise_id, data.weight_kg, data.reps)

    workout_set = WorkoutSet(
        session_id=session_id,
        is_pr=is_pr,
        **data.model_dump(),
    )
    db.add(workout_set)
    await db.flush()
    await db.refresh(workout_set)
    return workout_set


@router.patch("/sessions/{session_id}/complete", response_model=SessionResponse)
async def complete_session(
    session_id: UUID, data: SessionComplete, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> WorkoutSession:
    result = await db.execute(select(WorkoutSession).where(WorkoutSession.id == session_id))
    ws = result.scalar_one_or_none()
    if not ws or ws.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found")

    if ws.completed_at is not None:
        raise HTTPException(status_code=409, detail="Session already completed")

    ws.completed_at = datetime.utcnow()
    ws.duration_minutes = int((ws.completed_at - ws.started_at).total_seconds() / 60)
    if data.notes:
        ws.notes = data.notes

    await db.flush()
    await db.refresh(ws)
    return ws


# --- History & Analytics ---

@router.get("/history", response_model=list[WorkoutHistoryEntry])
async def get_workout_history(
    user_id: UUID = Depends(get_current_user_id),
    start_date: datetime | None = None,
    end_date: datetime | None = None,
    db: AsyncSession = Depends(get_db),
) -> list[WorkoutHistoryEntry]:
    if not end_date:
        end_date = datetime.utcnow()
    if not start_date:
        start_date = end_date - timedelta(days=30)

    # Avoid N+1: eagerly load sets (and their exercise) plus the program day in
    # a single round-trip via selectinload. Program names need a separate batch
    # SELECT WHERE id IN (...) below — we cannot eager-load them through the
    # session relationship because WorkoutSession does not declare one.
    result = await db.execute(
        select(WorkoutSession)
        .where(
            WorkoutSession.user_id == user_id,
            WorkoutSession.started_at >= start_date,
            WorkoutSession.started_at <= end_date,
        )
        .options(
            selectinload(WorkoutSession.sets).selectinload(WorkoutSet.exercise),
        )
        .order_by(WorkoutSession.started_at.desc())
    )
    sessions = list(result.scalars().all())

    # Batch-load only the columns we need. Selecting whole ORM objects would
    # cascade-fire the `lazy="selectin"` relationships on WorkoutProgram.days
    # and WorkoutProgramDay.exercises, adding queries we don't use.
    program_ids = {s.program_id for s in sessions if s.program_id is not None}
    program_day_ids = {s.program_day_id for s in sessions if s.program_day_id is not None}

    program_names: dict = {}
    if program_ids:
        prog_result = await db.execute(
            select(WorkoutProgram.id, WorkoutProgram.name).where(
                WorkoutProgram.id.in_(program_ids)
            )
        )
        program_names = {row[0]: row[1] for row in prog_result.all()}

    day_names: dict = {}
    if program_day_ids:
        day_result = await db.execute(
            select(WorkoutProgramDay.id, WorkoutProgramDay.day_name).where(
                WorkoutProgramDay.id.in_(program_day_ids)
            )
        )
        day_names = {row[0]: row[1] for row in day_result.all()}

    entries = []
    for s in sessions:
        total_sets = len(s.sets)
        total_volume = sum((ws.reps * (ws.weight_kg or 0)) for ws in s.sets)

        program_name = program_names.get(s.program_id)
        day_name = day_names.get(s.program_day_id)

        entries.append(WorkoutHistoryEntry(
            id=s.id,
            started_at=s.started_at,
            completed_at=s.completed_at,
            duration_minutes=s.duration_minutes,
            program_name=program_name,
            day_name=day_name,
            total_sets=total_sets,
            total_volume=total_volume,
        ))

    return entries


@router.get("/volume", response_model=list[VolumeByMuscle])
async def get_volume(
    user_id: UUID = Depends(get_current_user_id),
    period: str = Query(default="week", pattern="^(week|month)$"),
    db: AsyncSession = Depends(get_db),
) -> list[VolumeByMuscle]:
    now = datetime.utcnow()
    if period == "week":
        start = now - timedelta(days=7)
    else:
        start = now - timedelta(days=30)

    data = await get_volume_by_muscle(db, user_id, start, now)
    return [VolumeByMuscle(**d) for d in data]


@router.get("/prs", response_model=list[PersonalRecordResponse])
async def get_personal_records(
    user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> list[PersonalRecord]:
    result = await db.execute(
        select(PersonalRecord)
        .where(PersonalRecord.user_id == user_id)
        .order_by(PersonalRecord.achieved_at.desc())
    )
    return list(result.scalars().all())
