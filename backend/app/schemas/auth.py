import uuid
from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=255)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserResponse(BaseModel):
    id: uuid.UUID
    email: str
    display_name: str
    created_at: datetime

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    """Login/register response — includes the refresh pair (Slice 9.5)."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds until access_token exp
    user: UserResponse


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=16, max_length=128)


class RefreshResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


# ---- Sign in with Apple (Slice 9.6) --------------------------------------


class AppleFullName(BaseModel):
    firstName: str | None = None
    lastName: str | None = None


class AppleSigninRequest(BaseModel):
    identity_token: str = Field(min_length=1)
    user_identifier: str = Field(min_length=1, max_length=255)
    email: EmailStr | None = None
    full_name: AppleFullName | None = None


# ---- Logout (Slice 9.7) --------------------------------------------------


class LogoutRequest(BaseModel):
    refresh_token: str | None = None
