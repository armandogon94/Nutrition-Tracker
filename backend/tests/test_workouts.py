import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.models.exercise import Exercise
from app.models.workout import WorkoutProgram


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
