import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

import bcrypt
import jwt
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.refresh_token import RefreshToken


class RefreshTokenReuseError(Exception):
    """Raised when a refresh row could not be atomically claimed for rotation.

    This happens when the row's ``revoked_at`` was already set by the time the
    conditional UPDATE ran — i.e. a concurrent ``/refresh`` won the race, the
    user logged out, or the same plaintext is being replayed after a prior
    rotation. Per the refresh-token-theft-detection pattern the caller MUST
    treat this as a potential compromise of the token *family* and revoke every
    active refresh token belonging to ``user_id``.
    """

    def __init__(self, user_id: UUID) -> None:
        self.user_id = user_id
        super().__init__("refresh token reuse / concurrent rotation detected")


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
# Rotation: on /refresh we ATOMICALLY claim the presented row
# (`UPDATE ... SET revoked_at=now() WHERE id=:id AND revoked_at IS NULL
# RETURNING id`) and only then insert a fresh one. The conditional update is
# the concurrency guard: if two requests present the same plaintext at once,
# exactly one update matches a still-active row; the loser sees zero rows and
# raises `RefreshTokenReuseError`, which the route turns into a family-wide
# revocation. Replaying an already-rotated plaintext hits the same zero-row
# path, so token theft is detected rather than silently honored.


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


async def find_refresh_token_any_state(
    db: AsyncSession, plaintext: str
) -> RefreshToken | None:
    """Look up a refresh row by plaintext *regardless* of revoked/expired state.

    Returns the row if the hash resolves to one, even when it is revoked or
    expired. ``None`` only when the token was never issued. The /refresh route
    uses this to tell an *unknown* token (plain 401) apart from a *known but
    already-revoked* token (reuse → revoke the whole family).
    """
    return await db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == _hash_refresh_token(plaintext)
        )
    )


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
    """Atomically revoke ``current`` and issue a new refresh token.

    The revocation is a single conditional statement::

        UPDATE refresh_tokens
           SET revoked_at = now()
         WHERE id = :id AND revoked_at IS NULL
        RETURNING id

    Only one concurrent caller can match the ``revoked_at IS NULL`` predicate,
    so only one caller proceeds to mint a replacement. If no row was updated the
    token was already revoked (lost the rotation race, replayed after a prior
    rotation, or revoked by logout); we raise :class:`RefreshTokenReuseError`
    so the caller can revoke the whole token family.

    Raises:
        RefreshTokenReuseError: if the row could not be claimed for rotation.
    """
    result = await db.execute(
        update(RefreshToken)
        .where(
            RefreshToken.id == current.id,
            RefreshToken.revoked_at.is_(None),
        )
        .values(revoked_at=datetime.now(timezone.utc))
        .returning(RefreshToken.id)
    )
    claimed = result.scalar_one_or_none()
    if claimed is None:
        # The row was not active when we tried to claim it: concurrent rotation,
        # replay of an already-rotated token, or a logout in between.
        raise RefreshTokenReuseError(current.user_id)
    # Keep the in-session ORM object consistent with the row we just updated.
    await db.refresh(current)
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
