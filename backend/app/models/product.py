import uuid
from datetime import datetime, timezone

from sqlalchemy import String, Text
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
    created_at: Mapped[datetime] = mapped_column(default=_utcnow)
    updated_at: Mapped[datetime | None] = mapped_column(onupdate=_utcnow)
