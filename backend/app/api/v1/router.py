from fastapi import APIRouter

from app.api.v1.auth import router as auth_router
from app.api.v1.exercises import router as exercises_router
from app.api.v1.goals import router as goals_router
from app.api.v1.meal_plans import router as meal_plans_router
from app.api.v1.meals import router as meals_router
from app.api.v1.nutrition import router as nutrition_router
from app.api.v1.products import router as products_router
from app.api.v1.profile import router as profile_router
from app.api.v1.users import router as users_router
from app.api.v1.workouts import router as workouts_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth_router, prefix="/auth", tags=["auth"])
api_router.include_router(users_router, prefix="/users", tags=["users"])
api_router.include_router(products_router, prefix="/products", tags=["products"])
api_router.include_router(meals_router, prefix="/meals", tags=["meals"])
api_router.include_router(nutrition_router, prefix="/nutrition", tags=["nutrition"])
api_router.include_router(goals_router, prefix="/nutrition/goals", tags=["goals"])
api_router.include_router(profile_router, prefix="/profile", tags=["profile"])
api_router.include_router(meal_plans_router, prefix="/meal-plans", tags=["meal-plans"])
api_router.include_router(exercises_router, prefix="/exercises", tags=["exercises"])
api_router.include_router(workouts_router, prefix="/workouts", tags=["workouts"])
