from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.models.goal import NutritionGoal
from app.schemas.nutrition import NutritionGoalResponse, NutritionGoalUpdate

router = APIRouter()

DEFAULT_GOALS = NutritionGoalResponse(
    daily_calories=2000, daily_protein_g=150, daily_carbs_g=250, daily_fat_g=65
)


@router.get("", response_model=NutritionGoalResponse)
async def get_goals(user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)) -> NutritionGoalResponse:
    """Get nutrition goals for a user."""
    result = await db.execute(select(NutritionGoal).where(NutritionGoal.user_id == user_id))
    goal = result.scalar_one_or_none()
    if not goal:
        return DEFAULT_GOALS
    return NutritionGoalResponse.model_validate(goal)


@router.put("", response_model=NutritionGoalResponse)
async def update_goals(
    data: NutritionGoalUpdate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> NutritionGoalResponse:
    """Create or update nutrition goals.

    B8: this is a single PostgreSQL upsert keyed by the unique user_id, not a
    select-then-insert. Two concurrent first-time PUTs would otherwise both miss
    the SELECT, both INSERT, and one would violate uq_nutrition_goals_user_id and
    500. ON CONFLICT (user_id) DO UPDATE makes the second writer update instead.
    """
    values = data.model_dump()
    stmt = pg_insert(NutritionGoal).values(user_id=user_id, **values)
    stmt = stmt.on_conflict_do_update(
        index_elements=["user_id"],
        set_=values,
    ).returning(
        NutritionGoal.daily_calories,
        NutritionGoal.daily_protein_g,
        NutritionGoal.daily_carbs_g,
        NutritionGoal.daily_fat_g,
    )
    row = (await db.execute(stmt)).one()
    return NutritionGoalResponse(
        daily_calories=row.daily_calories,
        daily_protein_g=row.daily_protein_g,
        daily_carbs_g=row.daily_carbs_g,
        daily_fat_g=row.daily_fat_g,
    )
