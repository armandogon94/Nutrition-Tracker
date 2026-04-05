from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.environment == "production" and settings.secret_key == "change-me-in-production":
        raise RuntimeError("SECRET_KEY must be changed in production!")
    yield


app = FastAPI(
    title="FitTracker API",
    description="Health & fitness platform: nutrition tracking, meal planning, and workout programming",
    version="2.0.0",
    lifespan=lifespan,
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
