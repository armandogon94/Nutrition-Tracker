from uuid import UUID

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.core.rate_limit import limiter, tag_user_from_optional_token
from app.models.product import Product
from app.schemas.product import ProductCreate, ProductResponse
from app.services.product_lookup import lookup_product

router = APIRouter()


@router.get("/search", response_model=ProductResponse)
@limiter.limit("60/minute")
async def search_product_by_barcode(
    request: Request,
    barcode: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(tag_user_from_optional_token),
) -> Product:
    """Look up a product by barcode. Checks local cache first, then external APIs.

    Rate-limited at 60/minute per user (when authenticated) or per IP otherwise.
    """
    # 1. Check local DB cache
    result = await db.execute(select(Product).where(Product.barcode == barcode))
    cached = result.scalar_one_or_none()
    if cached:
        return cached

    # 2. Cascade through external APIs
    async with httpx.AsyncClient() as client:
        product_data = await lookup_product(barcode, client)

    if not product_data:
        raise HTTPException(status_code=404, detail="Product not found in any source")

    # 3. Cache in local DB
    product = Product(**product_data.model_dump())
    db.add(product)
    await db.flush()
    await db.refresh(product)
    return product


@router.post("", response_model=ProductResponse, status_code=201)
async def create_product(
    data: ProductCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> Product:
    """Create a manual product entry."""
    # Check for existing barcode
    result = await db.execute(select(Product).where(Product.barcode == data.barcode))
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail="Product with this barcode already exists")

    product = Product(**data.model_dump())
    db.add(product)
    await db.flush()
    await db.refresh(product)
    return product


@router.get("/{product_id}", response_model=ProductResponse)
@limiter.limit("120/minute")
async def get_product(
    request: Request,
    product_id: UUID,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(tag_user_from_optional_token),
) -> Product:
    """Get a product by ID. Rate-limited at 120/minute per user or per IP."""
    result = await db.execute(select(Product).where(Product.id == product_id))
    product = result.scalar_one_or_none()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product
