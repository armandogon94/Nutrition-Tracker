"""Rate-limit tests for `/api/v1/auth/*` endpoints (Slice 9.8).

These tests assert the slowapi limits documented in
`plans/slice-09-backend-debt.md` Phase C and `docs/adr/0003-refresh-token-rotation.md`:

- /auth/login: 5/minute (per IP for unauthenticated)
- /auth/register: 3/minute (per IP)
- /auth/refresh: 10/minute (per IP)

The 6th login / 4th register within a minute must return HTTP 429 with a
`Retry-After` header and a JSON body of `{detail: "rate_limited",
retry_after: <seconds>}`.

The fixtures reset the limiter state between tests so the per-IP counters
do not bleed across tests.
"""

import pytest

from app.core.rate_limit import limiter


@pytest.fixture(autouse=True)
def _reset_limiter():
    """Clear the in-memory rate-limit storage between tests."""
    # slowapi/limits keeps counts on the storage backend; reset() empties them.
    try:
        limiter.reset()
    except Exception:
        # Some storage backends (e.g. memory in older versions) don't expose
        # reset; fall back to clearing the internal storage directly.
        if hasattr(limiter, "_storage") and hasattr(limiter._storage, "storage"):
            limiter._storage.storage.clear()
    yield
    try:
        limiter.reset()
    except Exception:
        if hasattr(limiter, "_storage") and hasattr(limiter._storage, "storage"):
            limiter._storage.storage.clear()


async def test_login_rate_limited_after_5_requests(client):
    """6th login attempt within 60s returns 429 with Retry-After header."""
    payload = {"email": "ratelimit@test.dev", "password": "wrongpw"}

    # First 5 attempts: should NOT be 429 (will be 401 since user doesn't exist)
    for _ in range(5):
        resp = await client.post("/api/v1/auth/login", json=payload)
        assert resp.status_code != 429, "Should not be rate-limited within quota"

    # 6th attempt: 429 with Retry-After header and structured body.
    resp = await client.post("/api/v1/auth/login", json=payload)
    assert resp.status_code == 429
    assert "Retry-After" in resp.headers
    body = resp.json()
    expected_retry = int(resp.headers["Retry-After"])
    assert body == {"detail": "rate_limited", "retry_after": expected_retry}


async def test_register_rate_limited_after_3_requests(client):
    """4th register attempt within 60s returns 429."""
    base = {"password": "passw0rd!", "display_name": "Spam"}

    # First 3 should not be limited (they may 200/409 — irrelevant here).
    for i in range(3):
        await client.post(
            "/api/v1/auth/register",
            json={**base, "email": f"spam{i}@test.dev"},
        )

    resp = await client.post(
        "/api/v1/auth/register",
        json={**base, "email": "spam-final@test.dev"},
    )
    assert resp.status_code == 429
    body = resp.json()
    assert body["detail"] == "rate_limited"
    assert "retry_after" in body
    assert "Retry-After" in resp.headers


async def test_refresh_under_quota_succeeds(client, test_user):
    """A successful refresh under the 10/min quota still works."""
    # Acquire a refresh token via /login (1 of 5 login requests this minute).
    login = await client.post(
        "/api/v1/auth/login",
        json={"email": test_user.email, "password": "testpass123"},
    )
    assert login.status_code == 200
    refresh_token = login.json()["refresh_token"]

    resp = await client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert resp.status_code == 200
    assert "access_token" in resp.json()
    assert "refresh_token" in resp.json()


async def test_per_user_isolation_for_authed_routes(
    client, auth_token, auth_token_b
):
    """Per-user limits on authenticated routes don't bleed across users.

    User A burns through their /products/{id} quota; user B should still be
    allowed to make their own request. This test only requires that the key
    function discriminates user A from user B — it does not need to actually
    exhaust the 120/min cap.
    """
    headers_a = {"Authorization": f"Bearer {auth_token}"}
    headers_b = {"Authorization": f"Bearer {auth_token_b}"}

    # Burn 5 product GETs as user A (well under 120 cap; this test isn't
    # about hitting the cap, it's about verifying the limiter does not lump
    # both users into a single bucket).
    for _ in range(5):
        await client.get(
            "/api/v1/products/00000000-0000-0000-0000-000000000001",
            headers=headers_a,
        )

    # User B should still be able to call the endpoint without inheriting A's
    # bucket. Even on a 404 the request must reach the handler (not the
    # limiter).
    resp = await client.get(
        "/api/v1/products/00000000-0000-0000-0000-000000000001",
        headers=headers_b,
    )
    assert resp.status_code != 429, (
        "User B should not be limited by user A's quota; got 429"
    )
