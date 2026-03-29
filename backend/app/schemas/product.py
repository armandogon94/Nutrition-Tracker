import uuid
from datetime import datetime

from pydantic import BaseModel


class ProductCreate(BaseModel):
    barcode: str
    name: str
    brand: str | None = None
    serving_size_g: float = 100.0
    calories: float = 0.0
    protein_g: float = 0.0
    carbs_g: float = 0.0
    fat_g: float = 0.0
    fiber_g: float = 0.0
    source: str = "manual"
    image_url: str | None = None


class ProductResponse(BaseModel):
    id: uuid.UUID
    barcode: str
    name: str
    brand: str | None
    serving_size_g: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float
    source: str
    image_url: str | None
    created_at: datetime

    model_config = {"from_attributes": True}
