import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Boolean, Date, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class MealPlan(Base):
    __tablename__ = "meal_plans"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    name: Mapped[str] = mapped_column(String(255))
    week_start_date: Mapped[date] = mapped_column(Date)
    notes: Mapped[str | None] = mapped_column(Text)
    is_template: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=_utcnow, onupdate=_utcnow)

    items: Mapped[list["MealPlanItem"]] = relationship(
        back_populates="meal_plan", cascade="all, delete-orphan", lazy="selectin"
    )


class MealPlanItem(Base):
    __tablename__ = "meal_plan_items"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    meal_plan_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("meal_plans.id", ondelete="CASCADE"))
    product_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("products.id"))
    day_of_week: Mapped[int]  # 0-6 (Monday-Sunday)
    meal_type: Mapped[str] = mapped_column(String(50))
    quantity_servings: Mapped[float] = mapped_column(default=1.0)
    quantity_grams: Mapped[float | None] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    meal_plan: Mapped["MealPlan"] = relationship(back_populates="items")
    product: Mapped["Product"] = relationship(lazy="selectin")


from app.models.product import Product  # noqa: E402
