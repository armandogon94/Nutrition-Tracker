from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.core.http import get_client
from app.core.rate_limit import limiter, tag_user_from_optional_token
from app.models.product import Product
from app.schemas.product import ProductCreate, ProductResponse, ProductSearchResponse
from app.services.product_lookup import lookup_product

router = APIRouter()


def escape_like(s: str) -> str:
    """Escape SQL LIKE wildcard characters so user input can't act as a
    wildcard or force a full-table scan. Mirrors `exercises.escape_like`."""
    return s.replace("\\", "\\\\").replace("%", r"\%").replace("_", r"\_")


@router.get("/search", response_model=ProductSearchResponse)
@limiter.limit("60/minute")
async def search_products(
    request: Request,
    q: str = Query(
        min_length=1,
        max_length=100,
        description="Case-insensitive match against product name and brand.",
    ),
    limit: int = Query(default=20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(tag_user_from_optional_token),
) -> ProductSearchResponse:
    """Free-text search over **locally cached** products by name or brand.

    Returns an envelope ``{"results": [...]}`` (possibly empty — an empty
    result set is a normal outcome, not a 404). This only reads the local
    cache; resolving an unknown barcode against external APIs is the job of
    ``GET /barcode/{barcode}``. Rate-limited at 60/minute per user or IP.
    """
    pattern = f"%{escape_like(q)}%"
    result = await db.execute(
        select(Product)
        .where(or_(Product.name.ilike(pattern), Product.brand.ilike(pattern)))
        .order_by(Product.name)
        .limit(limit)
    )
    products = list(result.scalars().all())
    return ProductSearchResponse(
        results=[ProductResponse.model_validate(p) for p in products]
    )


@router.get("/barcode/{barcode}", response_model=ProductResponse)
@limiter.limit("60/minute")
async def lookup_product_by_barcode(
    request: Request,
    barcode: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(tag_user_from_optional_token),
) -> Product:
    """Look up a product by barcode. Checks the local cache first, then
    cascades through external APIs (OFF -> FatSecret -> USDA), caching any
    hit. Returns 404 when no source recognizes the barcode.

    The path segment is a *raw barcode string*, deliberately distinct from
    ``GET /{product_id}`` (which validates a UUID and would 422 on a numeric
    barcode). Rate-limited at 60/minute per user or IP.
    """
    # 1. Check local DB cache
    result = await db.execute(select(Product).where(Product.barcode == barcode))
    cached = result.scalar_one_or_none()
    if cached:
        return cached

    # 2. Cascade through external APIs using the app-scoped shared client.
    client = await get_client()
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
