from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.deps import get_current_user
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
async def register(data: UserRegister, db: AsyncSession = Depends(get_db)) -> TokenResponse:
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
async def login(data: UserLogin, db: AsyncSession = Depends(get_db)) -> TokenResponse:
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


@router.post("/apple", response_model=TokenResponse)
async def sign_in_with_apple(
    data: AppleSigninRequest, db: AsyncSession = Depends(get_db)
) -> TokenResponse:
    """Verify an Apple identity token and upsert a user keyed by Apple user id.

    On first sign-in we create a new user — preferring the email Apple put in
    the JWT (or the request body if Apple omitted it), falling back to a
    synthesized `apple_<id>@fittracker.local` so the unique-email constraint
    is always satisfied. Subsequent sign-ins look the user up by
    `apple_user_id` and reuse the row.
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
        email = (
            verified_email
            or (data.email if data.email else None)
            or _synthesize_apple_email(apple_user_id)
        )

        # Email collision guard: if a password user already owns this email,
        # link the Apple id to that account rather than 409-ing the user out
        # of their own login.
        existing = await db.execute(select(User).where(User.email == email))
        existing_user = existing.scalar_one_or_none()
        if existing_user is not None:
            existing_user.apple_user_id = apple_user_id
            user = existing_user
        else:
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
async def refresh(
    data: RefreshRequest, db: AsyncSession = Depends(get_db)
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
