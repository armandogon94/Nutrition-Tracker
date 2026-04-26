import uuid
from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("role IN ('user', 'admin')", name="users_role_check"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str] = mapped_column(String(255))
    # NOTE: column is TIMESTAMP WITHOUT TIME ZONE (existing schema). The
    # _utcnow helper (defined above) returns a naive UTC datetime to keep
    # DB inserts compatible with the un-tzaware column.
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)
    # Slice 9.4 — gates `/api/v1/admin/*` via require_admin (Slice 10).
    role: Mapped[str] = mapped_column(String(20), nullable=False, default="user")
    # Slice 9.4 — populated by `/api/v1/auth/apple` upsert flow (Slice 9.6).
    apple_user_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True, default=None
    )
