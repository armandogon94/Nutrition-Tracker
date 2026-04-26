"""Rate-limit tests for `/api/v1/products/*` endpoints (Slice 9.8).

Caps from the plan:
- GET /products/search?barcode=...  → 60/minute (per user)
- GET /products/{product_id}        → 120/minute (per user)
"""

import pytest

from app.core.rate_limit import limiter


@pytest.fixture(autouse=True)
def _reset_limiter():
    try:
        limiter.reset()
    except Exception:
        if hasattr(limiter, "_storage") and hasattr(limiter._storage, "storage"):
            limiter._storage.storage.clear()
    yield
    try:
        limiter.reset()
    except Exception:
        if hasattr(limiter, "_storage") and hasattr(limiter._storage, "storage"):
            limiter._storage.storage.clear()


async def test_products_search_under_quota_does_not_429(client, auth_token, httpx_mock):
    """A handful of search requests should not trip the 60/min cap."""
    headers = {"Authorization": f"Bearer {auth_token}"}

    # Mock all upstream lookups so the handler completes quickly.
    httpx_mock.add_response(
        url="https://world.openfoodfacts.org/api/v2/product/0000000000000.json",
        json={"status": 0},
        is_reusable=True,
    )

    for _ in range(3):
        resp = await client.get(
            "/api/v1/products/search?barcode=0000000000000",
            headers=headers,
        )
        # Either 200 (cached) or 404 (not found upstream) is fine — the only
        # forbidden status here is 429.
        assert resp.status_code != 429
