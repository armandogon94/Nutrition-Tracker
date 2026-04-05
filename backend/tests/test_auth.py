import pytest


async def test_register_success(client):
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": "newuser@example.com",
            "password": "securepass123",
            "display_name": "New User",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "newuser@example.com"
    assert data["user"]["display_name"] == "New User"
    assert "id" in data["user"]


async def test_register_duplicate_email(client):
    payload = {
        "email": "duplicate@example.com",
        "password": "securepass123",
        "display_name": "First User",
    }
    resp1 = await client.post("/api/v1/auth/register", json=payload)
    assert resp1.status_code == 201

    payload["display_name"] = "Second User"
    resp2 = await client.post("/api/v1/auth/register", json=payload)
    assert resp2.status_code == 409
    assert "already registered" in resp2.json()["detail"].lower()


async def test_register_short_password(client):
    response = await client.post(
        "/api/v1/auth/register",
        json={
            "email": "shortpw@example.com",
            "password": "short",
            "display_name": "Short PW",
        },
    )
    assert response.status_code == 422


async def test_login_success(client):
    # Register first
    await client.post(
        "/api/v1/auth/register",
        json={
            "email": "logintest@example.com",
            "password": "loginpass123",
            "display_name": "Login Tester",
        },
    )

    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": "logintest@example.com",
            "password": "loginpass123",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["user"]["email"] == "logintest@example.com"


async def test_login_wrong_password(client):
    # Register first
    await client.post(
        "/api/v1/auth/register",
        json={
            "email": "wrongpw@example.com",
            "password": "correctpass123",
            "display_name": "Wrong PW",
        },
    )

    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": "wrongpw@example.com",
            "password": "wrongpassword",
        },
    )
    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


async def test_login_nonexistent_email(client):
    response = await client.post(
        "/api/v1/auth/login",
        json={
            "email": "nobody@nowhere.com",
            "password": "somepassword",
        },
    )
    assert response.status_code == 401


async def test_get_me_authenticated(auth_client):
    response = await auth_client.get("/api/v1/auth/me")
    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "testuser@test.dev"
    assert data["display_name"] == "Test User"


async def test_get_me_no_token(client):
    response = await client.get("/api/v1/auth/me")
    assert response.status_code == 401
