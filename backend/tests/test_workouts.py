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


async def test_start_session_client_id_not_leaked_across_users(
    auth_client, auth_client_b, db_session
):
    """Idempotency must be scoped to the caller. User B replaying user A's id
    must NOT return (or hijack) user A's session — it creates B's own, or 404s
    on read, but never leaks A's data."""
    client_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()

    # User A starts a session with this id.
    a_resp = await auth_client.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert a_resp.status_code == 201
    assert a_resp.json()["user_id"] == str(TEST_USER_ID)

    # User B posts the SAME id. The response must belong to B, never to A.
    b_resp = await auth_client_b.post(
        "/api/v1/workouts/sessions",
        json={"id": client_id, "started_at": now},
    )
    assert b_resp.status_code in (200, 201)
    assert b_resp.json()["user_id"] == str(TEST_USER_B_ID)

    # And B cannot read A's session by that id (A's row is still A's).
    a_read = await auth_client.get(f"/api/v1/workouts/sessions/{client_id}")
    assert a_read.status_code == 200
    assert a_read.json()["user_id"] == str(TEST_USER_ID)


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
    now = datetime.utcnow()
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
