from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.core.http import get_client
from app.core.rate_limit import limiter, tag_user_from_optional_token
from app.models.product import Product
from app.schemas.product import ProductCreate, ProductResponse, ProductSearchResponse
from app.services.product_lookup import lookup_product

router = APIRouter()

# A1: a barcode row sourced from a real external provider is trusted as the
# authoritative shared-catalog answer. A "manual" row is user-supplied and must
# never shadow/poison the global barcode lookup for other users — it stays
# usable to its creator but is treated as a non-authoritative cache miss when a
# different user resolves the same barcode.
_TRUSTED_SOURCES: frozenset[str] = frozenset(
    {"open_food_facts", "fatsecret", "usda", "seed"}
)

# Cache-aside TTL: a trusted barcode row older than this is re-fetched from the
# external sources so stale nutrition data (e.g. an Open Food Facts entry that
# was later corrected) eventually refreshes. CLAUDE.md specifies a 7–14 day
# product cache TTL.
_CACHE_TTL = timedelta(days=14)


def _is_stale(product: Product) -> bool:
    """True when a cached product is older than the TTL and should be re-fetched.

    Timestamps are stored as naive UTC; ``updated_at`` is None until the row is
    first refreshed, so we fall back to ``created_at``.
    """
    ts = product.updated_at or product.created_at
    if ts is None:
        return True
    return datetime.now(timezone.utc).replace(tzinfo=None) - ts > _CACHE_TTL


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
    # 1. Check local DB cache.
    result = await db.execute(select(Product).where(Product.barcode == barcode))
    cached = result.scalar_one_or_none()

    # A1: only a TRUSTED (external-sourced) cache row is authoritative. A manual
    # row is user-supplied and must not shadow the global lookup, so we fall
    # through to external sources and let a verified row win. We still keep the
    # manual row as a last-resort answer if no external source recognizes it.
    # A *fresh* trusted row short-circuits; a *stale* one (older than the TTL)
    # falls through to re-fetch and upsert current data (cache-aside refresh),
    # and is still returned below if the external lookup is unavailable.
    if cached is not None and cached.source in _TRUSTED_SOURCES and not _is_stale(cached):
        return cached

    # 2. Cascade through external APIs using the app-scoped shared client.
    client = await get_client()
    product_data = await lookup_product(barcode, client)

    if not product_data:
        if cached is not None:
            # No external source recognizes it; the manual row is all we have.
            return cached
        raise HTTPException(status_code=404, detail="Product not found in any source")

    # 3. Upsert the verified external row, preferring external-source data. A
    # concurrent first-resolution of the same barcode (B3 race) or a pre-existing
    # manual row both resolve via ON CONFLICT (barcode): a manual row is upgraded
    # to the trusted external data; a concurrent insert never raises. We then
    # re-select the single canonical row by barcode.
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    values = product_data.model_dump()
    update_cols = {k: v for k, v in values.items() if k != "barcode"}
    # Stamp the refresh time so a re-fetched row counts as fresh again — the Core
    # upsert bypasses the ORM unit of work, so the model's `onupdate` never fires.
    update_cols["updated_at"] = now
    # Upgrading a row to a trusted external source makes it a shared catalog row,
    # so clear any manual creator id — otherwise an upgraded row keeps a stale
    # created_by_user_id while its source becomes e.g. open_food_facts, leaving
    # inconsistent provenance (self-review Wave 9).
    update_cols["created_by_user_id"] = None
    await db.execute(
        pg_insert(Product)
        .values(**values, updated_at=now)
        .on_conflict_do_update(index_elements=["barcode"], set_=update_cols)
    )
    # The upsert is a Core statement that bypasses the ORM unit of work, so any
    # row already loaded into this session's identity map (the manual `cached`
    # row) is now stale. populate_existing forces the re-select to overwrite it
    # with the freshly-upserted (external) column values.
    refreshed = await db.execute(
        select(Product)
        .where(Product.barcode == barcode)
        .execution_options(populate_existing=True)
    )
    product = refreshed.scalar_one_or_none()
    if product is None:  # pragma: no cover - row must exist after upsert
        raise HTTPException(status_code=500, detail="Failed to resolve product")
    return product


@router.post("", response_model=ProductResponse, status_code=201)
async def create_product(
    data: ProductCreate,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> Product:
    """Create a manual product entry owned by the caller.

    A1: the client cannot inject a trusted ``source`` to poison the shared
    catalog — we IGNORE any client-supplied ``source`` and force
    ``source="manual"``, stamping ``created_by_user_id`` with the caller. A
    manual row never shadows the authoritative barcode lookup for other users.

    B3: barcode creation is conflict-safe. ``INSERT ... ON CONFLICT (barcode) DO
    NOTHING`` never raises under a concurrent first-create, so the session is
    never poisoned; if the row already exists we return a deterministic 409.
    """
    values = data.model_dump()
    # Strip client control of trust-bearing fields.
    values["source"] = "manual"
    values["created_by_user_id"] = user_id

    inserted_id = (
        await db.execute(
            pg_insert(Product)
            .values(**values)
            .on_conflict_do_nothing(index_elements=["barcode"])
            .returning(Product.id)
        )
    ).scalar_one_or_none()

    if inserted_id is None:
        # Lost the race or the barcode already existed — deterministic 409.
        raise HTTPException(
            status_code=409, detail="Product with this barcode already exists"
        )

    product = await db.get(Product, inserted_id)
    if product is None:  # pragma: no cover - row must exist after insert
        raise HTTPException(status_code=500, detail="Failed to resolve product")
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
