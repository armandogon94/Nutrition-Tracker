"""Refresh-token rotation tests (Slice 9.5).

Covers /api/v1/auth/refresh:

- happy path: register -> login returns access + refresh, /refresh issues a new
  pair; the old refresh is revoked and unusable
- expired refresh -> 401
- already-revoked refresh -> 401
- rotation: after a successful refresh, the previous refresh token cannot be
  reused (token-theft detection)
"""

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select


async def _register_and_login(client) -> dict:
    email = "refresh-user@test.dev"
    password = "supersecret"
    await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "display_name": "Refresh User"},
    )
    resp = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "access_token" in body
    assert "refresh_token" in body, "login must return a refresh token"
    return body


async def test_refresh_happy_path(client):
    """Login -> refresh returns a fresh pair, old refresh is revoked."""
    initial = await _register_and_login(client)

    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": initial["refresh_token"]},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"] and body["access_token"] != initial["access_token"]
    assert body["refresh_token"] and body["refresh_token"] != initial["refresh_token"]
    assert body["expires_in"] > 0


async def test_refresh_rotation_old_invalid_after_new_issued(client):
    """After /refresh, presenting the old refresh token must fail."""
    initial = await _register_and_login(client)

    first = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": initial["refresh_token"]},
    )
    assert first.status_code == 200

    # Replay the original refresh token — must be rejected.
    replay = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": initial["refresh_token"]},
    )
    assert replay.status_code == 401


async def test_refresh_revoked_returns_401(client, db_session):
    """A refresh row whose `revoked_at` is set must be rejected."""
    from app.models.refresh_token import RefreshToken

    initial = await _register_and_login(client)

    # Manually mark the issued refresh as revoked.
    rows = await db_session.execute(select(RefreshToken))
    tokens = list(rows.scalars().all())
    assert tokens, "login must persist a refresh token row"
    for t in tokens:
        t.revoked_at = datetime.now(timezone.utc)
    await db_session.commit()

    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": initial["refresh_token"]},
    )
    assert resp.status_code == 401


async def test_refresh_expired_returns_401(client, db_session):
    """A refresh row whose `expires_at` is in the past must be rejected."""
    from app.models.refresh_token import RefreshToken

    initial = await _register_and_login(client)

    rows = await db_session.execute(select(RefreshToken))
    for t in rows.scalars().all():
        t.expires_at = datetime.now(timezone.utc) - timedelta(days=1)
    await db_session.commit()

    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": initial["refresh_token"]},
    )
    assert resp.status_code == 401


async def test_refresh_unknown_token_returns_401(client, test_user):
    """A syntactically-valid but never-issued token must be rejected."""
    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": "deadbeef" * 8},  # 64 hex chars, never minted
    )
    assert resp.status_code == 401
