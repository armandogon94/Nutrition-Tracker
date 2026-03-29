from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.goal import NutritionGoal
from app.schemas.nutrition import NutritionGoalResponse, NutritionGoalUpdate

router = APIRouter()

DEFAULT_GOALS = NutritionGoalResponse(
    daily_calories=2000, daily_protein_g=150, daily_carbs_g=250, daily_fat_g=65
)


@router.get("", response_model=NutritionGoalResponse)
async def get_goals(user_id: UUID, db: AsyncSession = Depends(get_db)) -> NutritionGoalResponse:
    """Get nutrition goals for a user."""
    result = await db.execute(select(NutritionGoal).where(NutritionGoal.user_id == user_id))
    goal = result.scalar_one_or_none()
    if not goal:
        return DEFAULT_GOALS
    return NutritionGoalResponse.model_validate(goal)


@router.put("", response_model=NutritionGoalResponse)
async def update_goals(
    user_id: UUID, data: NutritionGoalUpdate, db: AsyncSession = Depends(get_db)
) -> NutritionGoalResponse:
    """Create or update nutrition goals."""
    result = await db.execute(select(NutritionGoal).where(NutritionGoal.user_id == user_id))
    goal = result.scalar_one_or_none()

    if goal:
        for field, value in data.model_dump().items():
            setattr(goal, field, value)
    else:
        goal = NutritionGoal(user_id=user_id, **data.model_dump())
        db.add(goal)

    await db.flush()
    await db.refresh(goal)
    return NutritionGoalResponse.model_validate(goal)
