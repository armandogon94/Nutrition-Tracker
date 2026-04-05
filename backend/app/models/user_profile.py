import uuid
from datetime import datetime

from sqlalchemy import String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class UserProfile(Base):
    __tablename__ = "user_profiles"
    __table_args__ = (UniqueConstraint("user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    weight_kg: Mapped[float]
    height_cm: Mapped[float]
    age: Mapped[int]
    sex: Mapped[str] = mapped_column(String(20))
    activity_level: Mapped[str] = mapped_column(String(50), default="moderate")
    goal_preset: Mapped[str | None] = mapped_column(String(50))
    custom_daily_calories: Mapped[int | None] = mapped_column()
    custom_protein_g: Mapped[int | None] = mapped_column()
    custom_carbs_g: Mapped[int | None] = mapped_column()
    custom_fat_g: Mapped[int | None] = mapped_column()
    bmr: Mapped[float | None] = mapped_column()
    tdee: Mapped[float | None] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow)
