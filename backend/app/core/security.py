import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

import bcrypt
import jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.refresh_token import RefreshToken


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))


def create_access_token(
    user_id: str,
    email: str,
    expires_delta: timedelta | None = None,
) -> str:
    """Mint a signed JWT access token.

    `expires_delta` overrides the default lifetime (`settings.jwt_expire_hours`).
    Pass a negative `timedelta` to mint an already-expired token for testing.

    A random `jti` (JWT ID) is included so two tokens minted in the same second
    are byte-distinct (matters for the rotation flow where /login + /refresh
    can happen in the same instant in tests).
    """
    if expires_delta is None:
        expires_delta = timedelta(hours=settings.jwt_expire_hours)
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "email": email,
        "iat": now,
        "exp": now + expires_delta,
        "jti": secrets.token_hex(8),
    }
    return jwt.encode(payload, settings.secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.secret_key, algorithms=[settings.jwt_algorithm])


# ---- Refresh-token helpers (Slice 9.5) -----------------------------------
#
# Plaintext refresh tokens are random 256-bit hex strings (64 chars). We never
# store the plaintext — only an HMAC-SHA256 hash keyed with `settings.secret_key`.
# bcrypt is too slow for the per-request DB lookup; a deterministic keyed hash
# lets us index `token_hash` and find the matching row in O(1).
#
# Rotation: on /refresh we revoke the presented row (set `revoked_at`) and
# insert a fresh one. Replaying the old plaintext fails because its row is
# revoked even though its hash still resolves.


def _hash_refresh_token(plaintext: str) -> str:
    """Return a deterministic, keyed SHA-256 hex digest of the refresh token."""
    mac = hashlib.sha256()
    mac.update(settings.secret_key.encode("utf-8"))
    mac.update(b"|")
    mac.update(plaintext.encode("utf-8"))
    return mac.hexdigest()


async def create_refresh_token(
    db: AsyncSession,
    user_id: UUID,
    *,
    expires_delta: timedelta | None = None,
) -> tuple[str, RefreshToken]:
    """Mint and persist a refresh token. Returns (plaintext, db row).

    The plaintext is shown to the client exactly once; only the hash is stored.
    """
    if expires_delta is None:
        expires_delta = timedelta(days=settings.refresh_token_expire_days)
    plaintext = secrets.token_hex(32)  # 256 bits of entropy
    row = RefreshToken(
        user_id=user_id,
        token_hash=_hash_refresh_token(plaintext),
        expires_at=datetime.now(timezone.utc) + expires_delta,
    )
    db.add(row)
    await db.flush()
    return plaintext, row


async def verify_refresh_token(db: AsyncSession, plaintext: str) -> RefreshToken | None:
    """Look up an active (non-revoked, non-expired) refresh row by plaintext.

    Returns None if the token is unknown, revoked, or expired.
    """
    row = await db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == _hash_refresh_token(plaintext)
        )
    )
    if row is None:
        return None
    if row.revoked_at is not None:
        return None
    # Compare in UTC; if the column came back tz-naive (legacy rows) coerce it.
    expires_at = row.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at < datetime.now(timezone.utc):
        return None
    return row


async def rotate_refresh_token(
    db: AsyncSession, current: RefreshToken
) -> tuple[str, RefreshToken]:
    """Revoke `current` and issue a new refresh token for the same user."""
    current.revoked_at = datetime.now(timezone.utc)
    await db.flush()
    return await create_refresh_token(db, current.user_id)


async def revoke_user_refresh_tokens(db: AsyncSession, user_id: UUID) -> int:
    """Revoke every active refresh token belonging to `user_id`.

    Returns the count of newly-revoked rows. Already-revoked rows are left
    untouched so we don't reset their revocation timestamp.
    """
    rows = await db.scalars(
        select(RefreshToken).where(
            RefreshToken.user_id == user_id,
            RefreshToken.revoked_at.is_(None),
        )
    )
    revoked = 0
    now = datetime.now(timezone.utc)
    for row in rows.all():
        row.revoked_at = now
        revoked += 1
    if revoked:
        await db.flush()
    return revoked
