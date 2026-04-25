import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Date, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class DailyNutrition(Base):
    __tablename__ = "daily_nutrition"
    __table_args__ = (UniqueConstraint("user_id", "nutrition_date"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    nutrition_date: Mapped[date] = mapped_column(Date)
    total_calories: Mapped[float] = mapped_column(default=0.0)
    total_protein_g: Mapped[float] = mapped_column(default=0.0)
    total_carbs_g: Mapped[float] = mapped_column(default=0.0)
    total_fat_g: Mapped[float] = mapped_column(default=0.0)
    total_fiber_g: Mapped[float] = mapped_column(default=0.0)
    meals_count: Mapped[int] = mapped_column(default=0)
    updated_at: Mapped[datetime] = mapped_column(default=_utcnow, onupdate=_utcnow)
