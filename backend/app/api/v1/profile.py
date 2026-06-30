from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user_id
from app.models.user_profile import UserProfile
from app.schemas.profile import (
    ActivityLevel,
    CustomGoalUpdate,
    GoalPreset,
    GoalPresetUpdate,
    ProfileCreate,
    ProfileResponse,
    TDEEResponse,
)
from app.services.tdee_calculator import calculate_bmr, calculate_macros, calculate_tdee

router = APIRouter()


@router.post("", response_model=ProfileResponse)
async def create_or_update_profile(
    data: ProfileCreate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> ProfileResponse:
    """Create or update user profile. Calculates BMR and TDEE."""
    bmr = calculate_bmr(data.weight_kg, data.height_cm, data.age, data.sex)
    tdee = calculate_tdee(bmr, data.activity_level)

    # B8: single upsert keyed by the unique user_id instead of select-then-insert,
    # so two concurrent first-time POSTs cannot both INSERT and violate
    # uq_user_profiles_user_id (one would 500). ON CONFLICT updates the demographic
    # fields + recomputed bmr/tdee but DELIBERATELY leaves goal_preset / custom_*
    # untouched — those are owned by the /goals endpoints, matching the previous
    # "update only the ProfileCreate fields" behaviour.
    profile_fields = {
        "weight_kg": data.weight_kg,
        "height_cm": data.height_cm,
        "age": data.age,
        "sex": data.sex,
        "activity_level": data.activity_level.value
        if isinstance(data.activity_level, ActivityLevel)
        else data.activity_level,
    }
    stmt = pg_insert(UserProfile).values(
        user_id=user_id, bmr=bmr, tdee=tdee, **profile_fields
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=["user_id"],
        set_={**profile_fields, "bmr": bmr, "tdee": tdee},
    ).returning(UserProfile)
    profile = (await db.execute(stmt)).scalar_one()

    # Calculate default macros if goal exists
    macros = None
    if profile.goal_preset:
        macros = calculate_macros(tdee, GoalPreset(profile.goal_preset), data.weight_kg)
    elif profile.custom_daily_calories:
        macros = {
            "daily_calories": profile.custom_daily_calories,
            "daily_protein_g": profile.custom_protein_g,
            "daily_carbs_g": profile.custom_carbs_g,
            "daily_fat_g": profile.custom_fat_g,
        }

    return ProfileResponse(
        weight_kg=profile.weight_kg,
        height_cm=profile.height_cm,
        age=profile.age,
        sex=profile.sex,
        activity_level=profile.activity_level,
        bmr=profile.bmr,
        tdee=profile.tdee,
        goal_preset=profile.goal_preset,
        daily_calories=macros["daily_calories"] if macros else None,
        daily_protein_g=macros["daily_protein_g"] if macros else None,
        daily_carbs_g=macros["daily_carbs_g"] if macros else None,
        daily_fat_g=macros["daily_fat_g"] if macros else None,
    )


@router.get("/tdee", response_model=TDEEResponse)
async def get_tdee(user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)) -> TDEEResponse:
    """Get current TDEE and macro targets."""
    result = await db.execute(select(UserProfile).where(UserProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found. Create a profile first.")

    bmr = profile.bmr or calculate_bmr(profile.weight_kg, profile.height_cm, profile.age, profile.sex)
    tdee = profile.tdee or calculate_tdee(bmr, ActivityLevel(profile.activity_level))

    if profile.custom_daily_calories:
        macros = {
            "daily_calories": profile.custom_daily_calories,
            "daily_protein_g": profile.custom_protein_g or 0,
            "daily_carbs_g": profile.custom_carbs_g or 0,
            "daily_fat_g": profile.custom_fat_g or 0,
        }
    elif profile.goal_preset:
        macros = calculate_macros(tdee, GoalPreset(profile.goal_preset), profile.weight_kg)
    else:
        macros = calculate_macros(tdee, GoalPreset.MAINTENANCE, profile.weight_kg)

    return TDEEResponse(
        bmr=round(bmr, 1),
        tdee=round(tdee, 1),
        activity_level=profile.activity_level,
        goal_preset=profile.goal_preset,
        **macros,
    )


@router.post("/goals", response_model=TDEEResponse)
async def set_goals(
    data: GoalPresetUpdate, user_id: UUID = Depends(get_current_user_id), db: AsyncSession = Depends(get_db)
) -> TDEEResponse:
    """Set goal preset (fat_loss, maintenance, lean_bulk, muscle_gain)."""
    result = await db.execute(select(UserProfile).where(UserProfile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")

    profile.goal_preset = data.goal_preset.value
    profile.custom_daily_calories = None
    profile.custom_protein_g = None
    profile.custom_carbs_g = None
    profile.custom_fat_g = None

    await db.flush()

    bmr = profile.bmr or calculate_bmr(profile.weight_kg, profile.height_cm, profile.age, profile.sex)
    tdee = profile.tdee or calculate_tdee(bmr, ActivityLevel(profile.activity_level))
    macros = calculate_macros(tdee, data.goal_preset, profile.weight_kg)

    return TDEEResponse(
        bmr=round(bmr, 1),
        tdee=round(tdee, 1),
        activity_level=profile.activity_level,
        goal_preset=profile.goal_preset,
        **macros,
    )
