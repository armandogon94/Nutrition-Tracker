from datetime import datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.datetime_utils import utcnow_naive
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
async def get_program(
    program_id: UUID,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> WorkoutProgram:
    # Scope detail reads to presets or the caller's own programs (no IDOR):
    # a private program owned by another user must 404, not leak.
    result = await db.execute(
        select(WorkoutProgram).where(
            WorkoutProgram.id == program_id,
            (WorkoutProgram.is_preset == True) | (WorkoutProgram.user_id == user_id),  # noqa: E712
        )
    )
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
    # Client-supplied id path (Codex finding #1): the iOS client sends its local
    # session UUID as `id` so later set-logging / completion calls to
    # /sessions/{id}/... address the SAME row. This must be idempotent so the
    # offline-retry sweep can safely replay a "start".
    payload = data.model_dump()
    client_id = payload.pop("id", None)

    if client_id is not None:
        # Idempotency is scoped to the caller. If THIS user already started a
        # session with this id, return it unchanged — never duplicate, never
        # clobber its sets (this is what makes the offline-retry sweep safe to
        # replay a "start").
        #
        # Flash G3 / Gemini-Pro: if the id is already taken by a DIFFERENT user
        # (a UUID collision; astronomically unlikely in practice) we must NOT
        # silently mint a new id. The client would keep using its original id
        # for later /sessions/{id}/sets calls and 404. Instead return 409 so the
        # client regenerates a fresh id and retries the whole start. We also do
        # not leak or hijack the other user's row.
        existing = await db.execute(
            select(WorkoutSession).where(WorkoutSession.id == client_id)
        )
        existing_session = existing.scalar_one_or_none()
        if existing_session is not None:
            if existing_session.user_id == user_id:
                return existing_session
            raise HTTPException(
                status_code=409,
                detail="Session id already in use; regenerate and retry",
            )

    # IDOR guard (Codex finding #5): a caller may only attach a program / day
    # they can actually see. Without this, an authenticated user could store
    # another user's PRIVATE program_id / program_day_id on their own session and
    # later read its name back through GET /history (program_name / day_name).
    #
    #   - program_id      must be a preset (global) OR owned by the caller.
    #   - program_day_id  must belong to that accessible program; supplying a day
    #                     without a program (nothing to anchor ownership to) is
    #                     rejected, as is a day from a different/unowned program.
    program_id = payload.get("program_id")
    program_day_id = payload.get("program_day_id")

    if program_id is not None:
        prog_result = await db.execute(
            select(WorkoutProgram.id).where(
                WorkoutProgram.id == program_id,
                (WorkoutProgram.is_preset == True)  # noqa: E712
                | (WorkoutProgram.user_id == user_id),
            )
        )
        if prog_result.scalar_one_or_none() is None:
            # Don't reveal whether the program exists for someone else: 404.
            raise HTTPException(status_code=404, detail="Program not found")

    if program_day_id is not None:
        if program_id is None:
            # A day with no program gives us nothing to scope ownership against.
            raise HTTPException(
                status_code=422,
                detail="program_day_id requires a matching program_id",
            )
        day_result = await db.execute(
            select(WorkoutProgramDay.id).where(
                WorkoutProgramDay.id == program_day_id,
                WorkoutProgramDay.program_id == program_id,
            )
        )
        if day_result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=404, detail="Program day not found for this program"
            )

    session_obj = WorkoutSession(user_id=user_id, **payload)
    if client_id is not None:
        session_obj.id = client_id
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

    # B6 idempotent path: when the client supplies a client_set_id, a network
    # timeout + retry (or the offline sweep) can replay the same set. Insert with
    # ON CONFLICT (session_id, client_set_id) DO NOTHING, then re-select: a replay
    # returns the original row instead of duplicating the set or re-firing the PR.
    if data.client_set_id is not None:
        existing = await db.execute(
            select(WorkoutSet).where(
                WorkoutSet.session_id == session_id,
                WorkoutSet.client_set_id == data.client_set_id,
            )
        )
        existing_set = existing.scalar_one_or_none()
        if existing_set is not None:
            return existing_set

        # Not seen yet: race-insert. If a concurrent request wins the partial
        # unique index, DO NOTHING returns no id and we re-select the winner —
        # without running the PR upsert for this losing duplicate.
        insert_stmt = (
            pg_insert(WorkoutSet)
            .values(session_id=session_id, is_pr=False, **data.model_dump())
            .on_conflict_do_nothing(index_elements=["session_id", "client_set_id"])
            .returning(WorkoutSet.id)
        )
        inserted = (await db.execute(insert_stmt)).scalar_one_or_none()
        if inserted is None:
            await db.flush()
            winner = await db.execute(
                select(WorkoutSet).where(
                    WorkoutSet.session_id == session_id,
                    WorkoutSet.client_set_id == data.client_set_id,
                )
            )
            return winner.scalar_one()

        # We inserted the row: now it's safe to evaluate the PR exactly once.
        is_pr = await check_and_update_pr(
            db, user_id, data.exercise_id, data.weight_kg, data.reps
        )
        if is_pr:
            await db.execute(
                update(WorkoutSet).where(WorkoutSet.id == inserted).values(is_pr=True)
            )
        await db.flush()
        row = await db.execute(select(WorkoutSet).where(WorkoutSet.id == inserted))
        return row.scalar_one()

    # Legacy path (no idempotency key): preserve prior behaviour.
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

    # B6: make completion idempotent. A successful PATCH whose response is lost
    # (app killed before local cleanup) gets replayed; returning the already
    # completed session (200) lets the client converge instead of getting stuck
    # on a 409 forever.
    if ws.completed_at is not None:
        return ws

    ws.completed_at = utcnow_naive()
    # Flash G1: clamp to >= 0. A client with a manipulated/forward clock can set
    # started_at after completed_at, which would otherwise store a negative
    # duration and corrupt analytics.
    ws.duration_minutes = max(
        0, int((ws.completed_at - ws.started_at).total_seconds() / 60)
    )
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
        end_date = utcnow_naive()
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
    now = utcnow_naive()
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
