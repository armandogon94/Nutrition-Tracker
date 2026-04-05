import uuid
from datetime import datetime

from sqlalchemy import Boolean, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class ShoppingList(Base):
    __tablename__ = "shopping_lists"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(index=True)
    meal_plan_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("meal_plans.id", ondelete="SET NULL"))
    name: Mapped[str | None] = mapped_column(String(255))
    generated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
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
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

    shopping_list: Mapped["ShoppingList"] = relationship(back_populates="items")
