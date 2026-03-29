from fastapi import APIRouter

from app.api.v1.goals import router as goals_router
from app.api.v1.meals import router as meals_router
from app.api.v1.nutrition import router as nutrition_router
from app.api.v1.products import router as products_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(products_router, prefix="/products", tags=["products"])
api_router.include_router(meals_router, prefix="/meals", tags=["meals"])
api_router.include_router(nutrition_router, prefix="/nutrition", tags=["nutrition"])
api_router.include_router(goals_router, prefix="/nutrition/goals", tags=["goals"])
