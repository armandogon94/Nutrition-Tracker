"""Apple identity-token verifier (Slice 9.6).

Sign in with Apple delivers a JWT signed by Apple's private key. We verify it
locally before trusting it:

1. Fetch the public JWKs from `https://appleid.apple.com/auth/keys` (cached
   in-process for 1 hour — Apple rotates these slowly).
2. Pick the JWK whose `kid` matches the token header's `kid`.
3. Verify signature, `exp`, `iss`, and `aud` using PyJWT.

The endpoint never trusts the `email` or `user_identifier` strings the iOS
client sends — we read both from the verified JWT body when available, and
fall back to the request body only for the optional `full_name` (which Apple
delivers out-of-band on the very first sign-in).

Tests inject a fake `_fetch_jwks` to avoid real network. Production reaches
Apple via a fresh httpx client; once Slice 9.9 lands the shared client will
replace this.
"""

from __future__ import annotations

import time
from typing import Any

import httpx
import jwt
from fastapi import HTTPException, status
from jwt.algorithms import RSAAlgorithm

from app.core.config import settings

# Module-level cache: { "value": <jwks dict>, "expires_at": <epoch seconds> }.
# The cache lives for the process lifetime; a per-request lock isn't needed
# because the worst case is a thundering herd of 2-3 fetches at expiry.
_CACHE_TTL_SECONDS = 60 * 60  # 1 hour
_cache: dict[str, Any] = {}


async def _fetch_jwks() -> dict:
    """HTTP GET Apple's JWK set. Tests monkeypatch this to skip the network."""
    async with httpx.AsyncClient(timeout=5.0) as http:
        resp = await http.get(settings.apple_jwk_url)
        resp.raise_for_status()
        return resp.json()


async def _get_jwks() -> dict:
    """Return the JWK set, refreshing the in-process cache if it expired."""
    now = time.time()
    cached = _cache.get("value")
    expires_at = _cache.get("expires_at", 0)
    if cached is not None and expires_at > now:
        return cached

    try:
        jwks = await _fetch_jwks()
    except Exception as exc:  # network down / Apple 5xx — fall back to stale
        if cached is not None:
            return cached
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Apple identity provider unreachable",
        ) from exc

    _cache["value"] = jwks
    _cache["expires_at"] = now + _CACHE_TTL_SECONDS
    return jwks


def _jwk_for_kid(jwks: dict, kid: str) -> dict | None:
    for key in jwks.get("keys", []):
        if key.get("kid") == kid:
            return key
    return None


async def verify_identity_token(identity_token: str) -> dict:
    """Verify an Apple identity JWT and return the decoded claims.

    Raises ``HTTPException(401)`` for any signature/audience/issuer/expiry
    failure. Callers should treat the returned `sub` claim as the durable
    Apple user identifier.

    The returned dict carries Apple's `email` and `email_verified` claims when
    present. `email_verified` arrives as the string "true"/"false" (older
    tokens may use a bool). Callers MUST NOT trust `email` for linking to an
    existing account unless `email_verified` is truthy — Apple will sign tokens
    whose email it has not verified, so an unconditional email link is an
    account-takeover vector. See `sign_in_with_apple`.
    """
    try:
        unverified_header = jwt.get_unverified_header(identity_token)
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Malformed Apple identity token",
        ) from exc

    kid = unverified_header.get("kid")
    if not kid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple identity token missing kid",
        )

    jwks = await _get_jwks()
    jwk = _jwk_for_kid(jwks, kid)
    if jwk is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unknown Apple signing key",
        )

    try:
        public_key = RSAAlgorithm.from_jwk(jwk)
        claims = jwt.decode(
            identity_token,
            public_key,
            algorithms=[jwk.get("alg", "RS256")],
            audience=settings.apple_bundle_id,
            issuer=settings.apple_issuer,
            options={"require": ["exp", "iss", "aud", "sub"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple identity token expired",
        ) from exc
    except jwt.InvalidAudienceError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple identity token audience mismatch",
        ) from exc
    except jwt.InvalidIssuerError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Apple identity token issuer mismatch",
        ) from exc
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Apple identity token",
        ) from exc

    return claims
