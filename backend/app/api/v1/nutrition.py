from datetime import date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.schemas.nutrition import DailyNutritionResponse
from app.services.nutrition_calc import calculate_daily_nutrition

router = APIRouter()


@router.get("/daily/{nutrition_date}", response_model=DailyNutritionResponse)
async def get_daily_nutrition(
    nutrition_date: date, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> DailyNutritionResponse:
    """Get daily nutrition summary."""
    return await calculate_daily_nutrition(db, user_id, nutrition_date)


@router.get("/weekly", response_model=list[DailyNutritionResponse])
async def get_weekly_nutrition(
    user_id: UUID = Depends(get_current_user_id),
    start_date: date | None = None,
    end_date: date | None = None,
    db: AsyncSession = Depends(get_db),
) -> list[DailyNutritionResponse]:
    """Get nutrition data for a date range (defaults to last 7 days)."""
    if not end_date:
        end_date = date.today()
    if not start_date:
        start_date = end_date - timedelta(days=6)

    if (end_date - start_date).days > 90:
        raise HTTPException(status_code=400, detail="Date range cannot exceed 90 days")

    results = []
    current = start_date
    while current <= end_date:
        daily = await calculate_daily_nutrition(db, user_id, current)
        results.append(daily)
        current += timedelta(days=1)

    return results
