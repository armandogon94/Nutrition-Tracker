"""Rate-limit tests for `/api/v1/products/*` endpoints (Slice 9.8).

Caps from the plan:
- GET /products/search?q=...         → 60/minute (per user)
- GET /products/barcode/{barcode}    → 60/minute (per user)
- GET /products/{product_id}         → 120/minute (per user)
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


async def test_products_search_under_quota_does_not_429(client, auth_token):
    """A handful of search requests should not trip the 60/min cap.

    Text search reads only the local cache, so no upstream mock is needed —
    an empty DB just yields ``{"results": []}`` (200).
    """
    headers = {"Authorization": f"Bearer {auth_token}"}

    for _ in range(3):
        resp = await client.get(
            "/api/v1/products/search?q=avena",
            headers=headers,
        )
        # An empty/200 result is expected here — the only forbidden status is 429.
        assert resp.status_code != 429
