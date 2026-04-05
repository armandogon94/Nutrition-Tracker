import pytest


async def test_get_goals_default(auth_client):
    response = await auth_client.get("/api/v1/nutrition/goals")
    assert response.status_code == 200
    data = response.json()
    # Default goals from the endpoint
    assert data["daily_calories"] == 2000
    assert data["daily_protein_g"] == 150
    assert data["daily_carbs_g"] == 250
    assert data["daily_fat_g"] == 65


async def test_update_goals(auth_client):
    response = await auth_client.put(
        "/api/v1/nutrition/goals",
        json={
            "daily_calories": 2500,
            "daily_protein_g": 180,
            "daily_carbs_g": 300,
            "daily_fat_g": 70,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["daily_calories"] == 2500
    assert data["daily_protein_g"] == 180
    assert data["daily_carbs_g"] == 300
    assert data["daily_fat_g"] == 70


async def test_get_goals_after_update(auth_client):
    # Update goals first
    await auth_client.put(
        "/api/v1/nutrition/goals",
        json={
            "daily_calories": 1800,
            "daily_protein_g": 140,
            "daily_carbs_g": 200,
            "daily_fat_g": 55,
        },
    )

    # Now get them back
    response = await auth_client.get("/api/v1/nutrition/goals")
    assert response.status_code == 200
    data = response.json()
    assert data["daily_calories"] == 1800
    assert data["daily_protein_g"] == 140


async def test_update_goals_partial(auth_client):
    """Updating goals replaces all fields (PUT semantics)."""
    response = await auth_client.put(
        "/api/v1/nutrition/goals",
        json={
            "daily_calories": 3000,
            "daily_protein_g": 200,
            "daily_carbs_g": 350,
            "daily_fat_g": 80,
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["daily_calories"] == 3000
    assert data["daily_protein_g"] == 200
    assert data["daily_carbs_g"] == 350
    assert data["daily_fat_g"] == 80


async def test_unauthorized_401(client):
    response = await client.get("/api/v1/nutrition/goals")
    assert response.status_code == 401
