import uuid
from datetime import date, datetime, timezone

from sqlalchemy import Date, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Meal(Base):
    __tablename__ = "meals"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    meal_type: Mapped[str] = mapped_column(String(50), default="breakfast")
    meal_date: Mapped[date] = mapped_column(Date, index=True)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    items: Mapped[list["MealItem"]] = relationship(
        back_populates="meal", cascade="all, delete-orphan", lazy="selectin"
    )


class MealItem(Base):
    __tablename__ = "meal_items"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    meal_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("meals.id", ondelete="CASCADE"))
    product_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("products.id"))
    quantity_servings: Mapped[float] = mapped_column(default=1.0)
    quantity_grams: Mapped[float | None] = mapped_column()
    # Slice 3 / hardening: client-generated id for the offline-retry queue.
    # POST /meals/log is idempotent on (meal_id, client_item_id) so replaying a
    # queued mutation does not create duplicate items. Nullable because items
    # added via the legacy POST /meals/{id}/items route do not carry one.
    client_item_id: Mapped[str | None] = mapped_column(String(64), index=True)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    meal: Mapped["Meal"] = relationship(back_populates="items")
    product: Mapped["Product"] = relationship(lazy="selectin")


from app.models.product import Product  # noqa: E402
