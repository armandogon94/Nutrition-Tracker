from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.http import close_client, init_client
from app.core.rate_limit import limiter


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.environment == "production" and settings.secret_key == "change-me-in-production":
        raise RuntimeError("SECRET_KEY must be changed in production!")
    # Slice 9.9: shared httpx.AsyncClient lives for the lifetime of the app.
    await init_client()
    try:
        yield
    finally:
        await close_client()


app = FastAPI(
    title="FitTracker API",
    description="Health & fitness platform: nutrition tracking, meal planning, and workout programming",
    version="2.0.0",
    lifespan=lifespan,
)

# Slice 9.8: rate limiter wiring.
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)


@app.exception_handler(RateLimitExceeded)
async def _rate_limit_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    """Project-standard 429 shape: `{detail, retry_after}` plus header."""
    # `exc.limit.limit.get_expiry()` returns the per-window seconds (e.g. 60).
    retry_after = 60
    try:
        retry_after = int(exc.limit.limit.get_expiry())
    except Exception:
        pass
    return JSONResponse(
        status_code=429,
        content={"detail": "rate_limited", "retry_after": retry_after},
        headers={"Retry-After": str(retry_after)},
    )


app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.frontend_url, "http://localhost:3003", "http://localhost:3030", "http://localhost:3099"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

app.include_router(api_router)


@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "fittracker-api", "version": "2.0.0"}
