"""Rate-limit primitives for FastAPI endpoints (Slice 9.8).

A single `Limiter` instance is exported for use across the API. The key
function picks the *strongest available* identifier for each request:

1. If the request was authenticated and `request.state.user_id` was set by an
   earlier dependency / middleware, key on that user UUID.
2. Otherwise fall back to the client IP — which is what slowapi's stock
   `get_remote_address` returns. This keeps brute-force attempts per IP for
   unauthenticated routes (login, register).

The 429 handler in `app.main` returns the project-standard error shape:
`{detail: "rate_limited", retry_after: <seconds>}` plus a `Retry-After`
HTTP header.
"""

from __future__ import annotations

import jwt
from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address


def _key_func(request: Request) -> str:
    """Pick the strongest identifier available on the request."""
    user_id = getattr(request.state, "user_id", None)
    if user_id is not None:
        return f"user:{user_id}"
    return f"ip:{get_remote_address(request)}"


# Single shared Limiter instance. We use the in-memory storage backend by
# default. For multi-process production we should swap in a Redis backend
# via `storage_uri="redis://..."` — left as a follow-up.
limiter = Limiter(key_func=_key_func)


async def tag_user_from_optional_token(request: Request) -> None:
    """Best-effort dependency that tags `request.state.user_id` if a valid
    bearer token is present.

    Used on routes that *can* be authenticated but don't require it (e.g.
    `/products/search`). Lets the rate limiter key per-user when possible
    and gracefully fall back to per-IP otherwise.

    Never raises — a missing or invalid token just leaves `user_id` unset.
    """
    auth = request.headers.get("authorization")
    if not auth or not auth.lower().startswith("bearer "):
        return
    token = auth.split(" ", 1)[1].strip()
    if not token:
        return
    try:
        # Local import avoids a circular dep between deps and rate_limit.
        from app.core.security import decode_access_token

        payload = decode_access_token(token)
        sub = payload.get("sub")
        if sub:
            request.state.user_id = str(sub)
    except (jwt.ExpiredSignatureError, jwt.InvalidTokenError, Exception):
        # Bad/expired tokens just leave the limiter on its IP fallback.
        return
