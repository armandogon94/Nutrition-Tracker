import uuid

from pydantic import BaseModel, Field

from app.core.datetime_utils import UTCDateTime


class ProductCreate(BaseModel):
    """Product payload.

    Used in two roles: (1) the internal shape that ``product_lookup`` builds for
    a verified external row (where ``source`` is meaningful), and (2) the body of
    the user-facing ``POST /products``. A1: on the user-facing create path the
    route IGNORES any client-supplied ``source`` and forces ``source="manual"``
    plus ``created_by_user_id``, so a client cannot inject a trusted source to
    poison the shared catalog. The pattern below only bounds the allowed values.
    """

    barcode: str = Field(min_length=1, max_length=50)
    name: str = Field(min_length=1, max_length=255)
    brand: str | None = Field(default=None, max_length=255)
    serving_size_g: float = Field(default=100.0, gt=0, le=10000)
    calories: float = Field(default=0.0, ge=0, le=99999)
    protein_g: float = Field(default=0.0, ge=0, le=9999)
    carbs_g: float = Field(default=0.0, ge=0, le=9999)
    fat_g: float = Field(default=0.0, ge=0, le=9999)
    fiber_g: float = Field(default=0.0, ge=0, le=9999)
    source: str = Field(
        default="manual",
        pattern="^(manual|open_food_facts|usda|fatsecret|seed)$",
    )
    image_url: str | None = Field(default=None, max_length=2048)


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
    created_at: UTCDateTime

    model_config = {"from_attributes": True}


class ProductSearchResponse(BaseModel):
    """Envelope for free-text product search results.

    A list *wrapper* (not a bare array) so the response can later grow
    pagination metadata without a breaking change, and so the shape is
    distinct from the single-object barcode/by-id lookups. Mirrors the iOS
    `ProductSearchResponse { results: [ProductDTO] }`.
    """

    results: list[ProductResponse]
