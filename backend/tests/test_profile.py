import pytest


async def test_create_profile(auth_client):
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
    assert response.status_code == 200
    data = response.json()
    assert data["weight_kg"] == 80
    assert data["height_cm"] == 180
    assert data["age"] == 30
    assert data["sex"] == "male"
    assert data["activity_level"] == "moderate"


async def test_update_profile(auth_client):
    # Create profile first
    await auth_client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 80,
            "height_cm": 180,
            "age": 30,
            "sex": "male",
            "activity_level": "moderate",
        },
    )

    # Update it (same endpoint, upsert behavior)
    response = await auth_client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 78,
            "height_cm": 180,
            "age": 31,
            "sex": "male",
            "activity_level": "active",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["weight_kg"] == 78
    assert data["age"] == 31
    assert data["activity_level"] == "active"


async def test_get_tdee(auth_client):
    # Create profile first
    await auth_client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 80,
            "height_cm": 180,
            "age": 30,
            "sex": "male",
            "activity_level": "moderate",
        },
    )

    response = await auth_client.get("/api/v1/profile/tdee")
    assert response.status_code == 200
    data = response.json()
    assert "bmr" in data
    assert "tdee" in data
    assert "daily_calories" in data
    assert "daily_protein_g" in data
    assert "daily_carbs_g" in data
    assert "daily_fat_g" in data
    # BMR for 80kg, 180cm, 30yo male = 1780
    assert data["bmr"] == pytest.approx(1780.0, rel=0.01)
    # TDEE for moderate = 1780 * 1.55
    assert data["tdee"] == pytest.approx(1780 * 1.55, rel=0.01)


async def test_get_tdee_no_profile(auth_client, db_session):
    """TDEE endpoint returns 404 when no profile exists.

    We use a fresh user that has never created a profile to avoid
    interference from other tests that may have created one.
    """
    import uuid

    from app.core.security import create_access_token, hash_password
    from app.models.user import User

    new_user = User(
        id=uuid.uuid4(),
        email=f"noprofile-{uuid.uuid4().hex[:6]}@test.dev",
        password_hash=hash_password("testpass123"),
        display_name="No Profile User",
    )
    db_session.add(new_user)
    await db_session.commit()

    token = create_access_token(str(new_user.id), new_user.email)
    auth_client.headers["Authorization"] = f"Bearer {token}"

    response = await auth_client.get("/api/v1/profile/tdee")
    assert response.status_code == 404
    assert "profile not found" in response.json()["detail"].lower()


async def test_set_goal_preset(auth_client):
    # Create profile first
    await auth_client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 80,
            "height_cm": 180,
            "age": 30,
            "sex": "male",
            "activity_level": "moderate",
        },
    )

    response = await auth_client.post(
        "/api/v1/profile/goals",
        json={"goal_preset": "fat_loss"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["goal_preset"] == "fat_loss"
    assert "daily_calories" in data
    # Fat loss = TDEE - 500
    expected_tdee = 1780 * 1.55
    expected_calories = int(expected_tdee - 500)
    assert data["daily_calories"] == pytest.approx(expected_calories, abs=5)


async def test_set_goal_preset_no_profile(auth_client, db_session):
    """Setting goal preset returns 404 when no profile exists."""
    import uuid

    from app.core.security import create_access_token, hash_password
    from app.models.user import User

    new_user = User(
        id=uuid.uuid4(),
        email=f"nogoals-{uuid.uuid4().hex[:6]}@test.dev",
        password_hash=hash_password("testpass123"),
        display_name="No Goals User",
    )
    db_session.add(new_user)
    await db_session.commit()

    token = create_access_token(str(new_user.id), new_user.email)
    auth_client.headers["Authorization"] = f"Bearer {token}"

    response = await auth_client.post(
        "/api/v1/profile/goals",
        json={"goal_preset": "maintenance"},
    )
    assert response.status_code == 404


async def test_profile_calculates_bmr(auth_client):
    response = await auth_client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 60,
            "height_cm": 165,
            "age": 25,
            "sex": "female",
            "activity_level": "sedentary",
        },
    )
    assert response.status_code == 200
    data = response.json()
    # BMR for 60kg, 165cm, 25yo female = 10*60 + 6.25*165 - 5*25 - 161 = 1345.25
    assert data["bmr"] == pytest.approx(1345.25, rel=0.01)
    # TDEE for sedentary = 1345.25 * 1.2
    assert data["tdee"] == pytest.approx(1345.25 * 1.2, rel=0.01)


async def test_unauthorized_401(client):
    response = await client.post(
        "/api/v1/profile",
        json={
            "weight_kg": 80,
            "height_cm": 180,
            "age": 30,
            "sex": "male",
            "activity_level": "moderate",
        },
    )
    assert response.status_code == 401
