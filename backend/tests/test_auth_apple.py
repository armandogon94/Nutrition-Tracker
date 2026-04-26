"""Sign in with Apple verification tests (Slice 9.6).

The /api/v1/auth/apple endpoint accepts an Apple-issued identity token, verifies
its signature against Apple's published JWKs, and upserts a user by
`apple_user_id`. We never hit Apple's network in tests — the JWK lookup is
monkeypatched to return a deterministic local key, and identity tokens are
freshly minted with the matching private key for each scenario.
"""

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from sqlalchemy import select

from app.core.config import settings
from app.models.user import User
from app.services import apple_verifier as apple_mod


# ---- Test fixtures: deterministic RSA keypair + JWK installer ------------


def _new_rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _public_key_to_jwk(pub_key, kid: str) -> dict:
    """Build the JWK dict shape Apple publishes."""
    numbers = pub_key.public_numbers()
    import base64

    def _b64(n: int) -> str:
        b = n.to_bytes((n.bit_length() + 7) // 8, "big")
        return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")

    return {
        "kty": "RSA",
        "kid": kid,
        "use": "sig",
        "alg": "RS256",
        "n": _b64(numbers.n),
        "e": _b64(numbers.e),
    }


@pytest.fixture
def apple_keypair():
    """Generate one RSA key + return (private_pem, kid, jwk dict)."""
    priv = _new_rsa_key()
    kid = "test-key-id"
    jwk = _public_key_to_jwk(priv.public_key(), kid)
    pem = priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    return pem, kid, jwk


@pytest.fixture(autouse=True)
def patch_apple_jwks(monkeypatch, apple_keypair):
    """Force apple_verifier to use our local JWK rather than fetching Apple."""
    _, kid, jwk = apple_keypair

    async def fake_fetch():
        return {"keys": [jwk]}

    # Bypass the in-memory cache so each test sees a fresh fetch result.
    apple_mod._cache.clear()
    monkeypatch.setattr(apple_mod, "_fetch_jwks", fake_fetch)
    yield
    apple_mod._cache.clear()


def _mint_identity_token(
    private_pem: bytes,
    kid: str,
    *,
    sub: str = "001234.deadbeefcafe.5678",
    aud: str | None = None,
    iss: str | None = None,
    exp_offset: timedelta = timedelta(minutes=10),
    email: str | None = "apple-user@privaterelay.appleid.com",
) -> str:
    payload = {
        "sub": sub,
        "iss": iss if iss is not None else settings.apple_issuer,
        "aud": aud if aud is not None else settings.apple_bundle_id,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + exp_offset,
    }
    if email is not None:
        payload["email"] = email
    return jwt.encode(payload, private_pem, algorithm="RS256", headers={"kid": kid})


# ---- Tests ---------------------------------------------------------------


async def test_apple_first_time_creates_user(client, db_session, apple_keypair):
    pem, kid, _ = apple_keypair
    # Mint with the email Apple would put in the JWT — that's what we trust.
    token = _mint_identity_token(
        pem, kid, sub="apple-uid-aaaa", email="newuser@example.com"
    )

    resp = await client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": token,
            "user_identifier": "apple-uid-aaaa",
            "email": "newuser@example.com",
            "full_name": {"firstName": "Ada", "lastName": "Lovelace"},
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["user"]["email"] == "newuser@example.com"

    rows = await db_session.execute(
        select(User).where(User.apple_user_id == "apple-uid-aaaa")
    )
    user = rows.scalar_one()
    assert user.display_name == "Ada Lovelace"


async def test_apple_first_time_no_email_in_jwt_synthesizes_email(
    client, db_session, apple_keypair
):
    """Apple sometimes withholds email; we synthesize a stable local address."""
    pem, kid, _ = apple_keypair
    token = _mint_identity_token(pem, kid, sub="apple-uid-no-email", email=None)

    resp = await client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": token,
            "user_identifier": "apple-uid-no-email",
        },
    )
    assert resp.status_code == 200
    assert resp.json()["user"]["email"] == "apple_apple-uid-no-email@fittracker.local"


async def test_apple_second_time_reuses_user_by_apple_user_id(
    client, db_session, apple_keypair
):
    pem, kid, _ = apple_keypair
    token1 = _mint_identity_token(pem, kid, sub="apple-uid-bbbb")

    r1 = await client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": token1,
            "user_identifier": "apple-uid-bbbb",
            "email": "first@example.com",
        },
    )
    assert r1.status_code == 200
    user_id_1 = r1.json()["user"]["id"]

    # Second sign-in: Apple omits email after first issuance — confirm the
    # endpoint matches by apple_user_id and reuses the same user row.
    token2 = _mint_identity_token(pem, kid, sub="apple-uid-bbbb", email=None)
    r2 = await client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": token2,
            "user_identifier": "apple-uid-bbbb",
        },
    )
    assert r2.status_code == 200
    assert r2.json()["user"]["id"] == user_id_1

    rows = await db_session.execute(
        select(User).where(User.apple_user_id == "apple-uid-bbbb")
    )
    assert len(list(rows.scalars().all())) == 1


async def test_apple_bad_signature_returns_401(client, apple_keypair):
    """A token signed by an unrelated key must fail verification."""
    other_priv = _new_rsa_key().private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    _, kid, _ = apple_keypair  # advertise the legitimate kid in the header
    token = _mint_identity_token(other_priv, kid, sub="apple-uid-bad")

    resp = await client.post(
        "/api/v1/auth/apple",
        json={"identity_token": token, "user_identifier": "apple-uid-bad"},
    )
    assert resp.status_code == 401


async def test_apple_expired_token_returns_401(client, apple_keypair):
    pem, kid, _ = apple_keypair
    token = _mint_identity_token(
        pem, kid, sub="apple-uid-expired", exp_offset=timedelta(minutes=-10)
    )
    resp = await client.post(
        "/api/v1/auth/apple",
        json={"identity_token": token, "user_identifier": "apple-uid-expired"},
    )
    assert resp.status_code == 401


async def test_apple_wrong_audience_returns_401(client, apple_keypair):
    pem, kid, _ = apple_keypair
    token = _mint_identity_token(
        pem, kid, sub="apple-uid-wrong-aud", aud="com.someone.else"
    )
    resp = await client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": token,
            "user_identifier": "apple-uid-wrong-aud",
        },
    )
    assert resp.status_code == 401


async def test_apple_wrong_issuer_returns_401(client, apple_keypair):
    pem, kid, _ = apple_keypair
    token = _mint_identity_token(
        pem, kid, sub="apple-uid-wrong-iss", iss="https://evil.example.com"
    )
    resp = await client.post(
        "/api/v1/auth/apple",
        json={
            "identity_token": token,
            "user_identifier": "apple-uid-wrong-iss",
        },
    )
    assert resp.status_code == 401
