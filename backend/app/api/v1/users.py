"""User account management routes.

Currently exposes account deletion (``DELETE /api/v1/users/me``), a TestFlight
/ App Store review requirement for a health app that stores nutrition, workout,
and profile data.
"""

from fastapi import APIRouter, Depends, Response
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.deps import get_current_user
from app.core.security import revoke_user_refresh_tokens
from app.models.goal import NutritionGoal
from app.models.meal import Meal
from app.models.meal_plan import MealPlan
from app.models.shopping_list import ShoppingList
from app.models.user import User
from app.models.user_profile import UserProfile
from app.models.workout import PersonalRecord, WorkoutProgram, WorkoutSession

router = APIRouter()


@router.delete("/me", status_code=204)
async def delete_my_account(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Response:
    """Permanently delete the authenticated user and all of their data.

    Removes the user's meals, meal plans, shopping lists, workout sessions,
    personal records, their (non-preset) workout programs, nutrition goals, and
    profile, revokes every refresh token, and finally deletes the user row.

    Most child tables (``meal_items``, ``meal_plan_items``, ``shopping_list_items``,
    ``workout_sets``, program days/exercises) are removed by ``ON DELETE CASCADE``
    from their parent rows, so we only issue the parent deletes here. The
    user-scoped tables hold a plain ``user_id`` column (no FK to ``users``), so
    deleting the user row would NOT cascade them — they must be deleted
    explicitly by ``user_id``.

    Shared workout presets (``user_id IS NULL`` / ``is_preset = true``) are never
    touched: the program delete is scoped to ``user_id == me``.
    """
    user_id = user.id

    # Revoke refresh tokens first so any in-flight session is severed even if a
    # later statement were to fail. (The refresh_tokens FK also cascades on the
    # final user delete, but revoking is the explicit, auditable step.)
    await revoke_user_refresh_tokens(db, user_id)

    # User-scoped data. Children cascade from these parents.
    await db.execute(delete(Meal).where(Meal.user_id == user_id))
    await db.execute(delete(ShoppingList).where(ShoppingList.user_id == user_id))
    await db.execute(delete(MealPlan).where(MealPlan.user_id == user_id))
    await db.execute(
        delete(WorkoutSession).where(WorkoutSession.user_id == user_id)
    )
    await db.execute(
        delete(PersonalRecord).where(PersonalRecord.user_id == user_id)
    )
    # Only the user's OWN programs — never global presets.
    await db.execute(
        delete(WorkoutProgram).where(WorkoutProgram.user_id == user_id)
    )
    await db.execute(delete(NutritionGoal).where(NutritionGoal.user_id == user_id))
    await db.execute(delete(UserProfile).where(UserProfile.user_id == user_id))

    # Finally remove the account itself (cascades remaining refresh_tokens).
    await db.execute(delete(User).where(User.id == user_id))

    return Response(status_code=204)
