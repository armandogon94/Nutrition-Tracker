"""Logout / refresh-token revocation tests (Slice 9.7).

POST /api/v1/auth/logout requires a valid access token and revokes refresh
tokens for the caller. With a body it revokes only that specific refresh
token; without a body it revokes every active refresh row owned by the user
(sign-out from all devices).
"""


async def _login(client) -> dict:
    email = "logout-user@test.dev"
    password = "supersecret"
    await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "display_name": "Logout User"},
    )
    resp = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )
    return resp.json()


async def test_logout_then_refresh_returns_401(client):
    """Login -> logout (with refresh body) -> /refresh with that token = 401."""
    tokens = await _login(client)

    resp = await client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert resp.status_code == 204

    refresh = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refresh.status_code == 401


async def test_logout_without_body_revokes_all_user_refresh_tokens(client):
    """Logout without a body revokes every active refresh row for that user."""
    tokens_a = await _login(client)
    # Same user, second device — log in again to mint a second refresh row.
    second = await client.post(
        "/api/v1/auth/login",
        json={"email": "logout-user@test.dev", "password": "supersecret"},
    )
    tokens_b = second.json()
    assert tokens_a["refresh_token"] != tokens_b["refresh_token"]

    resp = await client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {tokens_b['access_token']}"},
    )
    assert resp.status_code == 204

    # Both refresh tokens are now unusable.
    for rt in (tokens_a["refresh_token"], tokens_b["refresh_token"]):
        replay = await client.post(
            "/api/v1/auth/refresh", json={"refresh_token": rt}
        )
        assert replay.status_code == 401, rt


async def test_logout_requires_authentication(client):
    """No bearer header -> 401, no DB mutation."""
    resp = await client.post("/api/v1/auth/logout", json={})
    assert resp.status_code == 401
