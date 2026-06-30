import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.models.exercise import Exercise
from app.models.workout import WorkoutProgram
from tests.conftest import TEST_USER_B_ID, TEST_USER_ID


async def _create_exercise(db_session, name_suffix=""):
    """Helper to create a test exercise."""
    exercise = Exercise(
        name=f"Workout Test Exercise {uuid.uuid4().hex[:4]} {name_suffix}".strip(),
        primary_muscle="chest",
        secondary_muscles="triceps",
        equipment="barbell",
        difficulty="intermediate",
        instructions="Push the weight.",
        category="compound",
    )
    db_session.add(exercise)
    await db_session.commit()
    return exercise


async def _create_preset_program(db_session):
    """Helper to create a preset workout program."""
    program = WorkoutProgram(
        user_id=None,
        name=f"Preset Program {uuid.uuid4().hex[:4]}",
        description="A preset program for testing",
        program_type="push_pull_legs",
        days_per_week=3,
        difficulty="intermediate",
        is_preset=True,
    )
    db_session.add(program)
    await db_session.commit()
    return program


async def test_list_programs(auth_client, db_session):
    await _create_preset_program(db_session)

    response = await auth_client.get("/api/v1/workouts/programs")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1


async def test_get_program(auth_client, db_session):
    program = await _create_preset_program(db_session)

    response = await auth_client.get(f"/api/v1/workouts/programs/{program.id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == str(program.id)
    assert data["name"] == program.name
    assert data["is_preset"] is True


async def test_get_program_not_found(auth_client):
    fake_id = str(uuid.uuid4())
    response = await auth_client.get(f"/api/v1/workouts/programs/{fake_id}")
    assert response.status_code == 404


async def test_create_program(auth_client):
    response = await auth_client.post(
        "/api/v1/workouts/programs",
        json={
            "name": "My Custom Program",
            "description": "A custom push/pull split",
            "program_type": "push_pull",
            "days_per_week": 4,
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "My Custom Program"
    assert data["days_per_week"] == 4
    assert data["is_preset"] is False


@pytest.mark.parametrize("bad_name", ["", "   ", "\t"])
async def test_create_program_rejects_blank_name(auth_client, bad_name):
    """WorkoutProgramCreate.name must reject blank / whitespace-only names."""
    response = await auth_client.post(
        "/api/v1/workouts/programs",
        json={"name": bad_name, "days_per_week": 3},
    )
    assert response.status_code == 422


async def test_start_session(auth_client):
    now = datetime.now(timezone.utc).isoformat()
    response = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    assert response.status_code == 201
    data = response.json()
    assert "id" in data
    assert data["completed_at"] is None
    assert data["sets"] == []


async def test_start_session_with_client_supplied_id(auth_client):
    """Client-supplied id (Codex finding #1): when iOS sends its local UUID as
    `id`, the backend must persist the session under THAT id so subsequent
    set-logging / completion calls to /sessions/{id}/... resolve."""
    client_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()
    response = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["id"] == client_id

    # The session must be addressable by the client id end-to-end.
    follow = await auth_client.get(f"/api/v1/workouts/sessions/{client_id}")
    assert follow.status_code == 200
    assert follow.json()["id"] == client_id


async def test_start_session_idempotent_returns_existing(auth_client, db_session):
    """Posting the SAME client id twice must be idempotent: return the existing
    session (200/201) rather than erroring on a PK conflict or duplicating it.
    This is what makes the offline-retry sweep safe to replay a start."""
    exercise = await _create_exercise(db_session, "idempotent")
    client_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    first = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert first.status_code == 201
    assert first.json()["id"] == client_id

    # A logged set against the (only) session.
    await auth_client.post(
        f"/api/v1/workouts/sessions/{client_id}/sets",
        json={"exercise_id": str(exercise.id), "set_number": 1, "reps": 5, "weight_kg": 60.0},
    )

    # Replaying the start must NOT raise and must NOT create a second session.
    second = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert second.status_code in (200, 201)
    assert second.json()["id"] == client_id

    # Exactly one session exists for the user, and the previously logged set
    # is still attached (no clobber/duplicate).
    history = await auth_client.get("/api/v1/workouts/history")
    matches = [e for e in history.json() if e["id"] == client_id]
    assert len(matches) == 1
    assert matches[0]["total_sets"] == 1


async def test_start_session_client_id_collision_across_users_returns_409(
    auth_client, auth_client_b, db_session
):
    """Flash G3: when user B posts an id already owned by user A, the server must
    return 409 (forcing B to regenerate) — never silently mint a new id (which
    would 404 B's later set-logs) and never leak/hijack A's row."""
    client_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    # User A starts a session with this id.
    a_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert a_resp.status_code == 201
    assert a_resp.json()["user_id"] == str(TEST_USER_ID)

    # User B posts the SAME id -> 409, regenerate and retry. A's data untouched.
    b_resp = await auth_client_b.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert b_resp.status_code == 409

    # And B cannot read A's session by that id (A's row is still A's).
    a_read = await auth_client.get(f"/api/v1/workouts/sessions/{client_id}")
    assert a_read.status_code == 200
    assert a_read.json()["user_id"] == str(TEST_USER_ID)

    # B reading that id gets 404 (not A's session).
    b_read = await auth_client_b.get(f"/api/v1/workouts/sessions/{client_id}")
    assert b_read.status_code == 404


async def test_get_session(auth_client):
    now = datetime.now(timezone.utc).isoformat()
    create_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = create_resp.json()["id"]

    response = await auth_client.get(f"/api/v1/workouts/sessions/{session_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == session_id


async def test_log_set(auth_client, db_session):
    exercise = await _create_exercise(db_session, "log-set")

    # Start session
    now = datetime.now(timezone.utc).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = session_resp.json()["id"]

    # Log a set
    response = await auth_client.post(
        f"/api/v1/workouts/sessions/{session_id}/sets",
        json={
            "exercise_id": str(exercise.id),
            "set_number": 1,
            "reps": 10,
            "weight_kg": 80.0,
            "rpe": 7.0,
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["exercise_id"] == str(exercise.id)
    assert data["set_number"] == 1
    assert data["reps"] == 10
    assert data["weight_kg"] == 80.0
    assert data["rpe"] == 7.0
    # First set for this exercise should be a PR
    assert data["is_pr"] is True


async def test_log_set_idempotent_with_client_set_id(auth_client, db_session):
    """B6: replaying the same client_set_id (timeout retry / offline sweep) must
    NOT duplicate the set — it returns the original row and leaves exactly one
    set on the session."""
    exercise = await _create_exercise(db_session, "idem-set")
    now = datetime.now(timezone.utc).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = session_resp.json()["id"]

    client_set_id = str(uuid.uuid4())
    payload = {
        "client_set_id": client_set_id,
        "exercise_id": str(exercise.id),
        "set_number": 1,
        "reps": 8,
        "weight_kg": 90.0,
    }

    first = await auth_client.post(
        f"/api/v1/workouts/sessions/{session_id}/sets", json=payload
    )
    assert first.status_code == 201
    first_id = first.json()["id"]
    assert first.json()["is_pr"] is True

    # Replay the exact same set: same row back, not a duplicate.
    second = await auth_client.post(
        f"/api/v1/workouts/sessions/{session_id}/sets", json=payload
    )
    assert second.status_code in (200, 201)
    assert second.json()["id"] == first_id

    # Exactly one set is attached to the session.
    session = await auth_client.get(f"/api/v1/workouts/sessions/{session_id}")
    assert len(session.json()["sets"]) == 1

    # And the PR was not double-counted: one PR row for this exercise.
    prs = await auth_client.get("/api/v1/workouts/prs")
    pr_rows = [r for r in prs.json() if r["exercise"]["id"] == str(exercise.id)]
    assert len(pr_rows) == 1


async def test_log_set_session_not_found(auth_client, db_session):
    exercise = await _create_exercise(db_session, "set-no-session")
    fake_session_id = str(uuid.uuid4())

    response = await auth_client.post(
        f"/api/v1/workouts/sessions/{fake_session_id}/sets",
        json={
            "exercise_id": str(exercise.id),
            "set_number": 1,
            "reps": 5,
            "weight_kg": 60.0,
        },
    )
    assert response.status_code == 404
    assert "session not found" in response.json()["detail"].lower()


async def test_complete_session(auth_client):
    now = datetime.now(timezone.utc).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = session_resp.json()["id"]

    response = await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete",
        json={"notes": "Great workout!"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["completed_at"] is not None
    assert data["notes"] == "Great workout!"
    assert data["duration_minutes"] is not None


async def test_complete_session_rejects_oversized_notes(auth_client):
    """SessionComplete.notes is capped (max_length=5000) so a client cannot
    flood the DB / logs with megabytes of text."""
    now = datetime.now(timezone.utc).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = session_resp.json()["id"]

    response = await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete",
        json={"notes": "x" * 5001},
    )
    assert response.status_code == 422


async def test_start_session_converts_offset_to_utc(auth_client):
    """B9: a tz-aware started_at must be converted to UTC before storage, not
    have its tzinfo stripped in place. 2026-06-26T23:30:00-05:00 is the SAME
    instant as 2026-06-27T04:30:00Z, so the serialized response must come back
    as 04:30 UTC (the wall clock 23:30 stored as-is would be a 5h error)."""
    response = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": "2026-06-26T23:30:00-05:00"},
    )
    assert response.status_code == 201
    started_at = response.json()["started_at"]
    # UTCDateTime serializes with an explicit offset; the instant must be 04:30Z.
    parsed = datetime.fromisoformat(started_at)
    assert parsed == datetime(2026, 6, 27, 4, 30, tzinfo=timezone.utc)


async def test_complete_session_is_idempotent(auth_client):
    """B6: re-completing an already-completed session returns the session (200),
    not 409, so a replayed PATCH (app killed before local cleanup) converges."""
    now = datetime.now(timezone.utc).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = session_resp.json()["id"]

    first = await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete",
        json={"notes": "done"},
    )
    assert first.status_code == 200
    first_completed_at = first.json()["completed_at"]

    # Replay the completion: must return the same completed session, not 409.
    second = await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete",
        json={"notes": "done again"},
    )
    assert second.status_code == 200
    assert second.json()["completed_at"] == first_completed_at
    # Original notes are preserved (the replay does not overwrite).
    assert second.json()["notes"] == "done"


async def test_complete_session_clamps_negative_duration(auth_client):
    """Flash G1: a future started_at (client clock manipulation) must not yield a
    negative duration; it is clamped to >= 0."""
    # started_at one hour in the future relative to the server's completion time.
    future = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": future},
    )
    session_id = session_resp.json()["id"]

    response = await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete",
        json={},
    )
    assert response.status_code == 200
    assert response.json()["duration_minutes"] == 0


async def test_get_workout_history(auth_client, db_session):
    exercise = await _create_exercise(db_session, "history")

    # Create and complete a session
    now = datetime.now(timezone.utc)
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now.isoformat()},
    )
    session_id = session_resp.json()["id"]

    # Log a set
    await auth_client.post(
        f"/api/v1/workouts/sessions/{session_id}/sets",
        json={
            "exercise_id": str(exercise.id),
            "set_number": 1,
            "reps": 8,
            "weight_kg": 100.0,
        },
    )

    # Complete session
    await auth_client.patch(
        f"/api/v1/workouts/sessions/{session_id}/complete",
        json={"notes": "History test"},
    )

    response = await auth_client.get("/api/v1/workouts/history")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1

    # Find our session in the history
    found = [entry for entry in data if entry["id"] == session_id]
    assert len(found) == 1
    assert found[0]["total_sets"] >= 1
    assert found[0]["total_volume"] >= 800.0  # 8 reps * 100kg


async def test_get_volume(auth_client, db_session):
    exercise = await _create_exercise(db_session, "volume")

    now = datetime.now(timezone.utc)
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now.isoformat()},
    )
    session_id = session_resp.json()["id"]

    await auth_client.post(
        f"/api/v1/workouts/sessions/{session_id}/sets",
        json={
            "exercise_id": str(exercise.id),
            "set_number": 1,
            "reps": 10,
            "weight_kg": 50.0,
        },
    )

    response = await auth_client.get(
        "/api/v1/workouts/volume", params={"period": "week"}
    )
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    # Should include our chest exercise
    if data:
        assert "muscle_group" in data[0]
        assert "total_volume" in data[0]
        assert "total_sets" in data[0]


async def test_history_uses_single_query(auth_client, db_session, setup_db):
    """N+1 guard: GET /workouts/history must NOT fire one query per session.

    Seeds 5 completed sessions × 3 sets each (each with a distinct exercise),
    each session linked to a workout program + day, and asserts the entire
    endpoint executes in a small, bounded number of SELECTs rather than scaling
    with session count.
    """
    from sqlalchemy import event

    from app.models.workout import WorkoutProgramDay

    _engine, session_factory = setup_db

    # Seed exercises
    exercises = []
    for i in range(3):
        ex = await _create_exercise(db_session, name_suffix=f"n1-{i}")
        exercises.append(ex)

    # Seed a program + day so the history endpoint must look them up per session
    program = await _create_preset_program(db_session)
    program_day = WorkoutProgramDay(
        program_id=program.id,
        day_number=1,
        day_name="Push Day",
    )
    db_session.add(program_day)
    await db_session.commit()

    # Seed 5 sessions × 3 sets via the API to exercise the same code paths
    now = datetime.now(timezone.utc)
    session_ids: list[str] = []
    for s_idx in range(5):
        resp = await auth_client.post(
            "/api/v1/workouts/sessions",
            json={
                "started_at": (now - timedelta(hours=s_idx)).isoformat(),
                "program_id": str(program.id),
                "program_day_id": str(program_day.id),
            },
        )
        sid = resp.json()["id"]
        session_ids.append(sid)
        for set_idx, ex in enumerate(exercises, start=1):
            await auth_client.post(
                f"/api/v1/workouts/sessions/{sid}/sets",
                json={
                    "exercise_id": str(ex.id),
                    "set_number": set_idx,
                    "reps": 5,
                    "weight_kg": 50.0 + set_idx,
                },
            )
        await auth_client.patch(
            f"/api/v1/workouts/sessions/{sid}/complete",
            json={"notes": "n1 test"},
        )

    # Count SELECT queries during the history call
    sync_engine = _engine.sync_engine
    select_count = {"n": 0}
    captured: list[str] = []

    def _on_execute(conn, cursor, statement, parameters, context, executemany):
        if statement.lstrip().upper().startswith("SELECT"):
            select_count["n"] += 1
            captured.append(statement.split("\n")[0][:140])

    event.listen(sync_engine, "before_cursor_execute", _on_execute)
    try:
        response = await auth_client.get("/api/v1/workouts/history")
    finally:
        event.remove(sync_engine, "before_cursor_execute", _on_execute)

    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 5

    # With selectinload + batched program/day name lookups: 1 auth user +
    # 1 sessions + 1 sets-batch + 1 exercises-batch + 1 programs-batch +
    # 1 program_days-batch = 6 SELECTs total, bounded regardless of session
    # count. Without the fix, the loop over sessions adds a per-session
    # program SELECT and program_day SELECT, scaling 1 + 2N + … (29 for N=5).
    assert select_count["n"] <= 6, (
        f"history endpoint executed {select_count['n']} SELECTs — N+1 not fixed.\n"
        + "\n".join(f"  {i + 1}. {q}" for i, q in enumerate(captured))
    )


async def test_get_personal_records(auth_client, db_session):
    exercise = await _create_exercise(db_session, "pr-test")

    now = datetime.now(timezone.utc)
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now.isoformat()},
    )
    session_id = session_resp.json()["id"]

    # Log a set that should be a PR
    await auth_client.post(
        f"/api/v1/workouts/sessions/{session_id}/sets",
        json={
            "exercise_id": str(exercise.id),
            "set_number": 1,
            "reps": 5,
            "weight_kg": 120.0,
        },
    )

    response = await auth_client.get("/api/v1/workouts/prs")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) >= 1

    # Find the PR for our exercise
    pr = [r for r in data if r["exercise"]["id"] == str(exercise.id)]
    assert len(pr) == 1
    assert pr[0]["max_weight_kg"] == 120.0
    assert pr[0]["max_reps_at_weight"] == 5
    assert pr[0]["estimated_1rm"] is not None
    assert pr[0]["estimated_1rm"] > 120.0  # 1RM should be higher than 5RM


async def test_pr_repeated_sets_converge_to_single_row_with_max(
    auth_client, db_session
):
    """B7: repeatedly logging sets for the same exercise must converge to exactly
    ONE personal_records row holding the highest estimated 1RM. A weaker later
    set must not clobber a stronger PR (no lost update), and no duplicate rows."""
    exercise = await _create_exercise(db_session, "pr-converge")
    now = datetime.now(timezone.utc).isoformat()
    session_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"started_at": now},
    )
    session_id = session_resp.json()["id"]

    async def log(weight, reps):
        return await auth_client.post(
            f"/api/v1/workouts/sessions/{session_id}/sets",
            json={
                "exercise_id": str(exercise.id),
                "set_number": 1,
                "reps": reps,
                "weight_kg": weight,
            },
        )

    # First set: PR. Heavier set: new PR. Lighter set: NOT a PR.
    r1 = await log(100.0, 5)
    assert r1.json()["is_pr"] is True
    r2 = await log(140.0, 5)
    assert r2.json()["is_pr"] is True
    r3 = await log(80.0, 5)
    assert r3.json()["is_pr"] is False

    prs = await auth_client.get("/api/v1/workouts/prs")
    pr_rows = [r for r in prs.json() if r["exercise"]["id"] == str(exercise.id)]
    # Exactly one row, holding the max (140kg), never clobbered by the 80kg set.
    assert len(pr_rows) == 1
    assert pr_rows[0]["max_weight_kg"] == 140.0


async def test_pr_concurrent_first_sets_converge(test_user, db_session, setup_db):
    """B7: two concurrent first-PR upserts for the same (user, exercise) — each in
    its own DB session — must converge to ONE row (enforced by the unique
    constraint) instead of duplicating and later raising MultipleResultsFound."""
    from sqlalchemy import select

    from app.models.workout import PersonalRecord
    from app.services.workout_service import check_and_update_pr
    from tests.conftest import TEST_USER_ID

    exercise = await _create_exercise(db_session, "pr-concurrent")

    _engine, session_factory = setup_db

    # Two independent sessions race the first PR for the same key. Each runs as
    # its own task and commits its own transaction, so PostgreSQL serializes the
    # conflicting INSERT ... ON CONFLICT on uq_personal_records_user_exercise:
    # one inserts, the other resolves to an UPDATE — never a duplicate row.
    # (Awaiting them sequentially in a single coroutine would DEADLOCK: the 2nd
    # INSERT blocks on the 1st uncommitted txn, whose commit only comes later in
    # the same code path. Real requests don't — they commit independently.)
    import asyncio

    async def _race(weight: float) -> bool:
        async with session_factory() as s:
            is_pr = await check_and_update_pr(s, TEST_USER_ID, exercise.id, weight, 5)
            await s.commit()
            return is_pr

    results = await asyncio.gather(_race(100.0), _race(120.0))
    assert any(results)

    # Exactly one PR row survives, and a later read does NOT raise.
    result = await db_session.execute(
        select(PersonalRecord).where(
            PersonalRecord.user_id == TEST_USER_ID,
            PersonalRecord.exercise_id == exercise.id,
        )
    )
    rows = result.scalars().all()
    assert len(rows) == 1
    assert rows[0].max_weight_kg == 120.0
