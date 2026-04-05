import uuid

import pytest

from app.models.exercise import Exercise


async def _seed_exercises(db_session):
    """Seed a few exercises into the test database."""
    exercises = [
        Exercise(
            name=f"Test Bench Press {uuid.uuid4().hex[:4]}",
            primary_muscle="chest",
            secondary_muscles="triceps,front_delts",
            equipment="barbell",
            difficulty="intermediate",
            instructions="Lie on bench and press the bar up.",
            category="compound",
        ),
        Exercise(
            name=f"Test Squat {uuid.uuid4().hex[:4]}",
            primary_muscle="quadriceps",
            secondary_muscles="glutes,hamstrings",
            equipment="barbell",
            difficulty="intermediate",
            instructions="Place bar on upper back and squat down.",
            category="compound",
        ),
        Exercise(
            name=f"Test Bicep Curl {uuid.uuid4().hex[:4]}",
            primary_muscle="biceps",
            secondary_muscles=None,
            equipment="dumbbell",
            difficulty="beginner",
            instructions="Curl the weight up.",
            category="isolation",
        ),
    ]
    for ex in exercises:
        db_session.add(ex)
    await db_session.commit()
    return exercises


async def test_list_exercises(client, db_session):
    """Exercises endpoint is public -- no auth needed."""
    await _seed_exercises(db_session)

    response = await client.get("/api/v1/exercises")
    assert response.status_code == 200
    data = response.json()
    assert "exercises" in data
    assert "total" in data
    assert data["total"] >= 3
    assert len(data["exercises"]) >= 3


async def test_list_exercises_filter_muscle(client, db_session):
    exercises = await _seed_exercises(db_session)
    chest_name = exercises[0].name  # The bench press

    response = await client.get("/api/v1/exercises", params={"muscle": "chest"})
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1
    names = [e["name"] for e in data["exercises"]]
    assert chest_name in names
    # All returned exercises should be chest exercises
    for ex in data["exercises"]:
        assert ex["primary_muscle"] == "chest"


async def test_list_exercises_search(client, db_session):
    exercises = await _seed_exercises(db_session)
    squat_name = exercises[1].name

    # Search by partial name
    response = await client.get("/api/v1/exercises", params={"q": "Squat"})
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1
    names = [e["name"] for e in data["exercises"]]
    assert squat_name in names


async def test_list_exercises_pagination(client, db_session):
    await _seed_exercises(db_session)

    response = await client.get(
        "/api/v1/exercises", params={"limit": 2, "offset": 0}
    )
    assert response.status_code == 200
    data = response.json()
    assert len(data["exercises"]) <= 2

    # Second page
    response2 = await client.get(
        "/api/v1/exercises", params={"limit": 2, "offset": 2}
    )
    assert response2.status_code == 200
    data2 = response2.json()
    # Should be different exercises (or empty if only 3 exist)
    if data2["exercises"]:
        first_page_ids = {e["id"] for e in data["exercises"]}
        second_page_ids = {e["id"] for e in data2["exercises"]}
        assert first_page_ids.isdisjoint(second_page_ids)


async def test_get_exercise(client, db_session):
    exercises = await _seed_exercises(db_session)
    ex = exercises[0]

    response = await client.get(f"/api/v1/exercises/{ex.id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == str(ex.id)
    assert data["name"] == ex.name
    assert data["primary_muscle"] == "chest"


async def test_get_exercise_not_found(client):
    fake_id = str(uuid.uuid4())
    response = await client.get(f"/api/v1/exercises/{fake_id}")
    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


async def test_search_escapes_sql_wildcards(client, db_session):
    """Verify that % and _ in search queries are treated as literal characters."""
    # Seed exercises with normal names (no wildcards)
    exercises = await _seed_exercises(db_session)

    # Search with SQL wildcard "%" -- should NOT match everything
    response = await client.get("/api/v1/exercises", params={"q": "bench%"})
    assert response.status_code == 200
    data = response.json()
    # "bench%" as a literal should not match any of our seeded exercises
    # (their names start with "Test Bench Press", "Test Squat", "Test Bicep Curl")
    assert data["total"] == 0

    # Search with SQL wildcard "_" -- should NOT act as single-char wildcard
    response2 = await client.get("/api/v1/exercises", params={"q": "leg_"})
    assert response2.status_code == 200
    data2 = response2.json()
    assert data2["total"] == 0


async def test_escape_like_function():
    """Unit test the escape_like helper directly."""
    from app.api.v1.exercises import escape_like

    assert escape_like("bench%press") == r"bench\%press"
    assert escape_like("leg_extension") == r"leg\_extension"
    assert escape_like("normal") == "normal"
    assert escape_like("100%_done") == r"100\%\_done"
    assert escape_like(r"back\slash") == r"back\\slash"
