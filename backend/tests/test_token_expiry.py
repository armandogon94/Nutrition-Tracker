"""Token-expiration backend tests (Slice 9.3).

Confirms that protected endpoints reject access tokens whose `exp` claim is in
the past, ensuring the `jwt.ExpiredSignatureError` branch in `get_current_user`
fires and returns 401 with the documented WWW-Authenticate header.
"""

from datetime import timedelta

import pytest

from app.core.security import create_access_token


@pytest.fixture
def expired_token(test_user):
    """Mint an access token whose `exp` claim is one hour in the past."""
    return create_access_token(
        str(test_user.id),
        test_user.email,
        expires_delta=timedelta(hours=-1),
    )


async def test_expired_token_returns_401_on_protected_endpoint(client, expired_token):
    """A protected endpoint must reject an expired token with 401."""
    response = await client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert response.status_code == 401
    assert response.headers.get("WWW-Authenticate") == "Bearer"
    detail = response.json().get("detail", "").lower()
    assert "expired" in detail


async def test_expired_token_blocks_workouts_endpoint(client, expired_token):
    """Cross-check: another protected route also rejects an expired token."""
    response = await client.get(
        "/api/v1/workouts/programs",
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert response.status_code == 401
