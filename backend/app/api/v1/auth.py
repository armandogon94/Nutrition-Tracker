from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.rate_limit import limiter
from app.core.security import (
    create_access_token,
    create_refresh_token,
    hash_password,
    rotate_refresh_token,
    verify_password,
    verify_refresh_token,
)
from app.models.user import User
from app.schemas.auth import (
    AppleSigninRequest,
    LogoutRequest,
    RefreshRequest,
    RefreshResponse,
    TokenResponse,
    UserLogin,
    UserRegister,
    UserResponse,
)
from app.services.apple_verifier import verify_identity_token

router = APIRouter()


def _access_token_for(user: User) -> tuple[str, int]:
    """Issue an access token + return its lifetime in seconds."""
    expires_in = int(timedelta(hours=settings.jwt_expire_hours).total_seconds())
    token = create_access_token(str(user.id), user.email)
    return token, expires_in


@router.post("/register", response_model=TokenResponse, status_code=201)
@limiter.limit("3/minute")
async def register(
    request: Request, data: UserRegister, db: AsyncSession = Depends(get_db)
) -> TokenResponse:
    """Register a new user account and return an access + refresh pair."""
    result = await db.execute(select(User).where(User.email == data.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=409, detail="Email already registered")

    user = User(
        email=data.email,
        password_hash=hash_password(data.password),
        display_name=data.display_name,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    access_token, expires_in = _access_token_for(user)
    refresh_plain, _ = await create_refresh_token(db, user.id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_plain,
        expires_in=expires_in,
        user=UserResponse.model_validate(user),
    )


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login(
    request: Request, data: UserLogin, db: AsyncSession = Depends(get_db)
) -> TokenResponse:
    """Login with email + password, returning an access + refresh pair."""
    result = await db.execute(select(User).where(User.email == data.email))
    user = result.scalar_one_or_none()
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    access_token, expires_in = _access_token_for(user)
    refresh_plain, _ = await create_refresh_token(db, user.id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_plain,
        expires_in=expires_in,
        user=UserResponse.model_validate(user),
    )


def _synthesize_apple_email(apple_user_id: str) -> str:
    """Fallback when Apple withholds the email on follow-up sign-ins."""
    return f"apple_{apple_user_id}@fittracker.local"


def _display_name_from(req: AppleSigninRequest, fallback: str) -> str:
    if req.full_name and (req.full_name.firstName or req.full_name.lastName):
        first = (req.full_name.firstName or "").strip()
        last = (req.full_name.lastName or "").strip()
        joined = f"{first} {last}".strip()
        if joined:
            return joined
    return fallback


async def _email_owner(db: AsyncSession, email: str) -> User | None:
    result = await db.execute(select(User).where(User.email == email))
    return result.scalar_one_or_none()


async def _provision_apple_email(
    db: AsyncSession,
    *,
    verified_email: str | None,
    client_email: str | None,
    apple_user_id: str,
) -> str:
    """Pick a NON-colliding email for a brand-new Apple account.

    Preference order: verified JWT email -> client-supplied email -> synthesized
    ``apple_<sub>@fittracker.local``. A candidate that already belongs to another
    account is skipped: an unverified or client-supplied email must never seed an
    address that silently attaches this Apple identity to someone else's row. The
    synthesized address is keyed on the unique Apple ``sub``, so it is the
    guaranteed-distinct fallback. If even that collides (only possible if someone
    pre-registered the synthesized address) we refuse rather than hijack a row.
    """
    candidates = (
        verified_email,
        client_email,
        _synthesize_apple_email(apple_user_id),
    )
    for candidate in candidates:
        if candidate and await _email_owner(db, candidate) is None:
            return candidate
    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=(
            "Unable to provision Apple account; "
            "sign in with your existing credentials."
        ),
    )


@router.post("/apple", response_model=TokenResponse)
@limiter.limit("5/minute")
async def sign_in_with_apple(
    request: Request,
    data: AppleSigninRequest,
    db: AsyncSession = Depends(get_db),
) -> TokenResponse:
    """Verify an Apple identity token and upsert a user keyed by Apple user id.

    The verified `sub` is the canonical key. On first sign-in we create a new
    user, preferring the email Apple signed into the JWT, then the request body,
    then a synthesized `apple_<id>@fittracker.local` so the unique-email
    constraint is always satisfied. Subsequent sign-ins look the user up by
    `apple_user_id` and reuse the row.

    Account-takeover guard (Slice 9.6 security fix): a *pre-existing* account is
    only ever auto-linked to this Apple identity when the email came from the
    signed JWT AND Apple flagged it `email_verified == "true"`. An unverified
    JWT email, or the fully client-controlled `data.email`, can seed a brand-new
    account's address but must NEVER attach this `sub` to someone else's row —
    otherwise an attacker could bind their Apple id to a victim's password
    account and sign in as them thereafter.
    """
    claims = await verify_identity_token(data.identity_token)

    # Apple's verified `sub` is the canonical user id. The request body field
    # is duplicated to make iOS error-handling easier; we trust the JWT.
    apple_user_id = str(claims.get("sub") or data.user_identifier)

    result = await db.execute(
        select(User).where(User.apple_user_id == apple_user_id)
    )
    user = result.scalar_one_or_none()

    if user is None:
        verified_email = claims.get("email")
        # Apple ships `email_verified` as the string "true"/"false" (older
        # tokens may use a bool). Only a JWT-sourced, Apple-verified email may
        # resolve to a pre-existing account — never `data.email`, never an
        # unverified address. This single check closes the pre-auth takeover.
        email_is_apple_verified = claims.get("email_verified") in (True, "true")

        existing_user: User | None = None
        if verified_email and email_is_apple_verified:
            existing_user = await _email_owner(db, verified_email)

        if existing_user is not None:
            # Safe link: Apple vouches for this address and signed it into the
            # JWT, so attaching the Apple id to the matching account is correct.
            existing_user.apple_user_id = apple_user_id
            user = existing_user
        else:
            # Brand-new account. The chosen email must not collide with any
            # existing row, so an unverified/client email can't hijack one.
            email = await _provision_apple_email(
                db,
                verified_email=verified_email,
                client_email=data.email,
                apple_user_id=apple_user_id,
            )
            user = User(
                email=email,
                password_hash="!apple-no-password",  # never matches verify_password
                display_name=_display_name_from(data, fallback=email.split("@")[0]),
                apple_user_id=apple_user_id,
            )
            db.add(user)

        await db.flush()
        await db.refresh(user)

    access_token, expires_in = _access_token_for(user)
    refresh_plain, _ = await create_refresh_token(db, user.id)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_plain,
        expires_in=expires_in,
        user=UserResponse.model_validate(user),
    )


@router.post("/refresh", response_model=RefreshResponse)
@limiter.limit("10/minute")
async def refresh(
    request: Request,
    data: RefreshRequest,
    db: AsyncSession = Depends(get_db),
) -> RefreshResponse:
    """Exchange a valid refresh token for a fresh access + refresh pair.

    Rotation: the presented refresh row is revoked and a new one is issued.
    Replaying the original refresh token after this call returns 401.
    """
    row = await verify_refresh_token(db, data.refresh_token)
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    user = await db.get(User, row.user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    new_plain, _ = await rotate_refresh_token(db, row)
    access_token, expires_in = _access_token_for(user)
    return RefreshResponse(
        access_token=access_token,
        refresh_token=new_plain,
        expires_in=expires_in,
    )


@router.post("/logout", status_code=204)
async def logout(
    data: LogoutRequest | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Revoke refresh tokens for the requesting user.

    If `refresh_token` is provided, only that specific token is revoked. Otherwise
    every active refresh token belonging to the caller is revoked (sign-out
    from all devices).
    """
    body = data or LogoutRequest()
    if body.refresh_token:
        row = await verify_refresh_token(db, body.refresh_token)
        # Tolerate already-invalid tokens — logout is idempotent. We still
        # require auth so an attacker cannot probe the table anonymously.
        if row is not None and row.user_id == user.id:
            from datetime import datetime, timezone

            row.revoked_at = datetime.now(timezone.utc)
            await db.flush()
    else:
        from app.core.security import revoke_user_refresh_tokens

        await revoke_user_refresh_tokens(db, user.id)
    return None


@router.get("/me", response_model=UserResponse)
async def get_me(user: User = Depends(get_current_user)) -> UserResponse:
    """Get current authenticated user."""
    return UserResponse.model_validate(user)
