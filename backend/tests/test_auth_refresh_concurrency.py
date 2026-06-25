"""Atomic refresh-token rotation + theft-detection tests (backend hardening).

The plain rotation flow is covered in ``test_auth_refresh.py``. This module
locks down the *concurrency* and *reuse-detection* guarantees of the atomic
rotation introduced in the backend-hardening slice:

- Two concurrent ``/refresh`` calls presenting the SAME token cannot both
  succeed (exactly one 200, one 401). Without the atomic conditional UPDATE
  both could verify the active row and mint divergent token chains.
- A detected reuse (the losing concurrent request, or an explicit replay of an
  already-rotated token) revokes the WHOLE token family, so even the winner's
  freshly-minted token is invalidated and the user must re-authenticate.
"""

import asyncio

from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.main import app
from app.models.refresh_token import RefreshToken


async def _register_and_login(client) -> dict:
    email = "rotate-race@test.dev"
    password = "supersecret123"
    await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "display_name": "Race User"},
    )
    resp = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )
    assert resp.status_code == 200, resp.text
    return resp.json()


def _new_client() -> AsyncClient:
    """A fresh client/connection so concurrent calls don't share a session."""
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def test_concurrent_refresh_only_one_succeeds(client):
    """Two simultaneous refreshes of the same token: exactly one wins."""
    initial = await _register_and_login(client)
    token = initial["refresh_token"]

    async def _refresh() -> int:
        async with _new_client() as ac:
            resp = await ac.post(
                "/api/v1/auth/refresh", json={"refresh_token": token}
            )
            return resp.status_code

    # Fire both at once. The atomic UPDATE...WHERE revoked_at IS NULL must let
    # exactly one claim the row; the other gets 401.
    results = await asyncio.gather(_refresh(), _refresh())

    assert sorted(results) == [200, 401], (
        f"expected exactly one success and one rejection, got {results}"
    )


async def test_concurrent_refresh_burns_token_family(client, db_session):
    """The losing concurrent refresh flags reuse and revokes every token."""
    initial = await _register_and_login(client)
    token = initial["refresh_token"]

    winners: list[str] = []

    async def _refresh() -> int:
        async with _new_client() as ac:
            resp = await ac.post(
                "/api/v1/auth/refresh", json={"refresh_token": token}
            )
            if resp.status_code == 200:
                winners.append(resp.json()["refresh_token"])
            return resp.status_code

    results = await asyncio.gather(_refresh(), _refresh())
    assert sorted(results) == [200, 401]
    assert len(winners) == 1

    # Reuse was detected, so the family is burned: NO active refresh rows remain
    # and even the winner's brand-new token is rejected.
    active = await db_session.scalar(
        select(func.count())
        .select_from(RefreshToken)
        .where(RefreshToken.revoked_at.is_(None))
    )
    assert active == 0, "all refresh tokens in the family must be revoked"

    replay_winner = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": winners[0]}
    )
    assert replay_winner.status_code == 401


async def test_replayed_revoked_token_revokes_family(client, db_session):
    """Replaying an already-rotated token revokes the whole family (theft)."""
    initial = await _register_and_login(client)

    # Legitimate rotation: token1 -> token2 (token1 now revoked).
    first = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": initial["refresh_token"]}
    )
    assert first.status_code == 200
    token2 = first.json()["refresh_token"]

    # Attacker replays the stolen, already-revoked token1.
    replay = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": initial["refresh_token"]}
    )
    assert replay.status_code == 401

    # Reuse detection burned the family, so the legitimate token2 is now dead.
    active = await db_session.scalar(
        select(func.count())
        .select_from(RefreshToken)
        .where(RefreshToken.revoked_at.is_(None))
    )
    assert active == 0

    after = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": token2}
    )
    assert after.status_code == 401


async def test_unknown_token_does_not_touch_family(client, db_session):
    """A never-issued token returns 401 but leaves existing tokens active."""
    initial = await _register_and_login(client)

    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": "f00dface" * 8},  # 64 hex chars, never minted
    )
    assert resp.status_code == 401

    # The legitimate tokens must still be usable — unknown tokens are not reuse.
    # (register + login each mint one active refresh row, so the family is 2.)
    active = await db_session.scalar(
        select(func.count())
        .select_from(RefreshToken)
        .where(RefreshToken.revoked_at.is_(None))
    )
    assert active == 2

    ok = await client.post(
        "/api/v1/auth/refresh", json={"refresh_token": initial["refresh_token"]}
    )
    assert ok.status_code == 200
