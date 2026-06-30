import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class ShoppingList(Base):
    __tablename__ = "shopping_lists"
    # B11: at most one generated list per (user, meal_plan). Without this,
    # concurrent GET /meal-plans/{id}/shopping-list calls both delete-none then
    # both insert, duplicating lists. NULL meal_plan_id rows (ad-hoc lists) are
    # exempt because NULLs are distinct under a UNIQUE constraint in PostgreSQL.
    __table_args__ = (
        UniqueConstraint("user_id", "meal_plan_id", name="uq_shopping_lists_user_plan"),
    )

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    meal_plan_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("meal_plans.id", ondelete="SET NULL"))
    name: Mapped[str | None] = mapped_column(String(255))
    generated_at: Mapped[datetime] = mapped_column(default=_utcnow)
    completed_at: Mapped[datetime | None] = mapped_column()

    items: Mapped[list["ShoppingListItem"]] = relationship(
        back_populates="shopping_list", cascade="all, delete-orphan", lazy="selectin"
    )


class ShoppingListItem(Base):
    __tablename__ = "shopping_list_items"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    shopping_list_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("shopping_lists.id", ondelete="CASCADE"))
    ingredient_name: Mapped[str] = mapped_column(String(255))
    quantity: Mapped[float]
    unit: Mapped[str | None] = mapped_column(String(50))
    category: Mapped[str | None] = mapped_column(String(100))
    is_checked: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)

    shopping_list: Mapped["ShoppingList"] = relationship(back_populates="items")
