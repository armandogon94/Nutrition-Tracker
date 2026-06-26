import uuid
from datetime import datetime, timezone

from sqlalchemy import ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Product(Base):
    __tablename__ = "products"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    barcode: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255))
    brand: Mapped[str | None] = mapped_column(String(255))
    serving_size_g: Mapped[float] = mapped_column(default=100.0)
    calories: Mapped[float] = mapped_column(default=0.0)
    protein_g: Mapped[float] = mapped_column(default=0.0)
    carbs_g: Mapped[float] = mapped_column(default=0.0)
    fat_g: Mapped[float] = mapped_column(default=0.0)
    fiber_g: Mapped[float] = mapped_column(default=0.0)
    source: Mapped[str] = mapped_column(String(50), default="manual")
    image_url: Mapped[str | None] = mapped_column(Text)
    # A1: who created this row when source="manual". NULL for trusted catalog
    # rows imported from external sources (open_food_facts / fatsecret / usda /
    # seed). Used to keep user-supplied manual rows from poisoning the shared
    # barcode lookup for everyone else (a manual row is usable to its creator but
    # never shadows an authoritative external row). MAIN owns the migration that
    # adds the matching DB column/index; declared here so metadata.create_all
    # covers it under tests.
    created_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id"), nullable=True, index=True, default=None
    )
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)
    updated_at: Mapped[datetime | None] = mapped_column(onupdate=_utcnow)
