async def test_health_check_v2(client):
    response = await client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["version"] == "2.0.0"


async def test_create_profile(auth_client, test_user):
    response = await auth_client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 80,
            "height_cm": 180,
            "age": 30,
            "sex": "male",
            "activity_level": "moderate",
        },
    )
    # Authenticated create/upsert returns 200 with the computed profile.
    assert response.status_code == 200
    data = response.json()
    assert data["weight_kg"] == 80
    assert data["height_cm"] == 180
    assert data["age"] == 30
    assert data["sex"] == "male"
    assert data["activity_level"] == "moderate"
    # BMR/TDEE are derived server-side from the submitted metrics.
    assert data["bmr"] is not None
    assert data["tdee"] is not None


async def test_get_tdee_no_profile(auth_client):
    # Authenticated user that has not created a profile yet.
    response = await auth_client.get("/api/v1/profile/tdee")
    assert response.status_code == 404
    assert response.json()["detail"] == "Profile not found. Create a profile first."


async def test_list_exercises(client):
    response = await client.get("/api/v1/exercises")
    assert response.status_code in (200, 500)


async def test_list_programs(auth_client):
    response = await auth_client.get("/api/v1/workouts/programs")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


async def test_workout_session_not_found(auth_client):
    # Authenticated request for a session id that does not exist -> 404.
    response = await auth_client.get(
        "/api/v1/workouts/sessions/00000000-0000-0000-0000-000000000099"
    )
    assert response.status_code == 404
    assert response.json()["detail"] == "Session not found"


async def test_meal_plan_create(auth_client, test_user):
    response = await auth_client.post(
        "/api/v1/meal-plans",
        json={
            "name": "Test Plan",
            "week_start_date": "2026-03-30",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Test Plan"
    assert data["week_start_date"] == "2026-03-30"
    assert "id" in data
