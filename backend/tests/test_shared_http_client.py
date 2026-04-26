"""Tests for the app-scoped shared `httpx.AsyncClient` (Slice 9.9).

The hot path for `/products/search` cascades through OFF -> USDA ->
FatSecret. Creating a fresh `httpx.AsyncClient` per request defeats
connection pooling. We instead initialize a single client at app startup
and reuse it for the lifetime of the process.

These tests assert the singleton contract:
1. Two consecutive calls to `get_client()` return the same instance.
2. After `close_client()` the slot is cleared and the next `get_client()`
   creates a fresh instance (also the same on follow-up calls).
3. `product_lookup` and (when present) `food_recognition` consume the
   shared client rather than creating their own.
"""

from __future__ import annotations

import httpx
import pytest

import app.core.http as http_mod
from app.core.http import close_client, get_client, init_client


@pytest.fixture(autouse=True)
async def _reset_shared_client():
    """Tear down between tests so we don't leak state."""
    await close_client()
    yield
    await close_client()


async def test_get_client_returns_singleton():
    """Two consecutive calls return the *same* AsyncClient instance."""
    a = await get_client()
    b = await get_client()
    assert isinstance(a, httpx.AsyncClient)
    assert id(a) == id(b), (
        "get_client() must return the singleton; got two distinct instances"
    )


async def test_init_client_is_idempotent():
    """Calling `init_client()` twice yields the same instance."""
    a = await init_client()
    b = await init_client()
    assert id(a) == id(b)


async def test_close_client_clears_singleton():
    """After close, the next get_client() creates a fresh instance."""
    a = await get_client()
    await close_client()
    assert http_mod._client is None  # noqa: SLF001 — internal state assertion
    b = await get_client()
    assert id(a) != id(b)
    # And the new one is also stable:
    c = await get_client()
    assert id(b) == id(c)


async def test_product_lookup_consumes_injected_client(httpx_mock):
    """`lookup_product` accepts an injected AsyncClient and uses it.

    We pass the shared singleton in and assert OFF was hit through it.
    """
    from app.services.product_lookup import lookup_open_food_facts

    httpx_mock.add_response(
        url="https://world.openfoodfacts.org/api/v2/product/123.json",
        json={
            "status": 1,
            "product": {
                "product_name": "Test",
                "brands": "B",
                "serving_quantity": 100,
                "nutriments": {
                    "energy-kcal": 100,
                    "proteins": 1,
                    "carbohydrates": 1,
                    "fat": 1,
                    "fiber": 1,
                },
            },
        },
    )

    client = await get_client()
    result = await lookup_open_food_facts("123", client)
    assert result is not None
    assert result.name == "Test"
