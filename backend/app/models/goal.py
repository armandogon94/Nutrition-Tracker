import uuid
from datetime import datetime

from sqlalchemy import UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class NutritionGoal(Base):
    __tablename__ = "nutrition_goals"
    __table_args__ = (UniqueConstraint("user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    daily_calories: Mapped[int] = mapped_column(default=2000)
    daily_protein_g: Mapped[int] = mapped_column(default=150)
    daily_carbs_g: Mapped[int] = mapped_column(default=250)
    daily_fat_g: Mapped[int] = mapped_column(default=65)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, onupdate=datetime.utcnow)
