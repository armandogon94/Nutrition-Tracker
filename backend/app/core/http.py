"""App-scoped shared `httpx.AsyncClient` (Slice 9.9).

Creating an `AsyncClient` per request defeats connection pooling and forces a
fresh TCP/TLS handshake on every external API call. We instead create one
client at app startup (FastAPI `lifespan`) and reuse it for the lifetime of
the process.

Service modules (`product_lookup`, `food_recognition` once it exists) call
`get_client()` to retrieve the shared instance. Tests can monkeypatch the
private `_client` directly or call `close_client()` between cases.
"""

from __future__ import annotations

import httpx

# Module-private singleton. `init_client()` populates it; `close_client()`
# tears it down. `get_client()` returns it (lazily creating one if the
# lifespan hook hasn't run yet, e.g. inside a unit test that imports a
# service without booting the full app).
_client: httpx.AsyncClient | None = None


def _build_client() -> httpx.AsyncClient:
    """Construct the shared client with sane defaults for outbound API calls.

    - 10s default timeout (matches the per-call timeout that previously lived
      inline in `product_lookup.py`).
    - HTTP/2 explicitly disabled because we don't yet ship the optional
      `h2` dependency.
    - 20 max connections is plenty for the cascading OFF -> USDA -> FatSecret
      pattern; bump if we add concurrent in-flight workloads.
    """
    return httpx.AsyncClient(
        timeout=httpx.Timeout(10.0),
        http2=False,
        limits=httpx.Limits(max_connections=20),
    )


async def init_client() -> httpx.AsyncClient:
    """Create the shared client. Called from the FastAPI lifespan."""
    global _client
    if _client is None:
        _client = _build_client()
    return _client


async def get_client() -> httpx.AsyncClient:
    """Return the shared client, lazily initializing if needed."""
    global _client
    if _client is None:
        _client = _build_client()
    return _client


async def close_client() -> None:
    """Close the shared client. Called from the FastAPI lifespan."""
    global _client
    if _client is not None:
        await _client.aclose()
        _client = None
