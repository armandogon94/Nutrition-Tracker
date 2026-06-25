"""Account-deletion tests (backend hardening, Task 4).

Covers ``DELETE /api/v1/users/me``:

- auth required
- deletes ALL of the caller's data across every user-scoped table, including
  rows cascaded from parents (meal_items, workout_sets, etc.)
- revokes the caller's refresh tokens and removes the user row (the access
  token stops working)
- never touches another user's data or shared workout presets
"""

import uuid
from datetime import date, datetime, timezone

from sqlalchemy import func, select

from app.core.security import create_refresh_token
from app.models.exercise import Exercise
from app.models.goal import NutritionGoal
from app.models.meal import Meal, MealItem
from app.models.meal_plan import MealPlan, MealPlanItem
from app.models.product import Product
from app.models.refresh_token import RefreshToken
from app.models.shopping_list import ShoppingList, ShoppingListItem
from app.models.user_profile import UserProfile
from app.models.workout import (
    PersonalRecord,
    WorkoutProgram,
    WorkoutSession,
    WorkoutSet,
)


def _naive_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


async def _seed_full_user_data(db_session, user_id: uuid.UUID, *, tag: str) -> dict:
    """Create one row in every user-scoped table for ``user_id``.

    Returns ids useful for later assertions. Also exercises the cascade paths
    (meal_items, meal_plan_items, shopping_list_items, workout_sets).
    """
    product = Product(
        barcode=f"DEL-{tag}-{uuid.uuid4().hex[:6]}",
        name=f"Del Product {tag}",
        serving_size_g=100.0,
        calories=100.0,
        source="manual",
    )
    exercise = Exercise(
        name=f"Del Exercise {tag} {uuid.uuid4().hex[:6]}",
        primary_muscle="chest",
    )
    db_session.add_all([product, exercise])
    await db_session.flush()

    meal = Meal(user_id=user_id, meal_type="lunch", meal_date=date(2026, 6, 25))
    meal.items.append(
        MealItem(product_id=product.id, quantity_servings=2.0)
    )

    plan = MealPlan(
        user_id=user_id, name=f"Plan {tag}", week_start_date=date(2026, 6, 22)
    )
    plan.items.append(
        MealPlanItem(
            product_id=product.id, day_of_week=0, meal_type="lunch",
            quantity_servings=1.0,
        )
    )

    shopping = ShoppingList(user_id=user_id, name=f"List {tag}")
    shopping.items.append(
        ShoppingListItem(ingredient_name="Eggs", quantity=12.0, unit="unit")
    )

    session = WorkoutSession(user_id=user_id, started_at=_naive_now())
    session.sets.append(
        WorkoutSet(exercise_id=exercise.id, set_number=1, reps=5, weight_kg=100.0)
    )

    pr = PersonalRecord(
        user_id=user_id, exercise_id=exercise.id, max_weight_kg=100.0,
        estimated_1rm=116.0, achieved_at=_naive_now(),
    )

    program = WorkoutProgram(
        user_id=user_id, name=f"My Program {tag}", days_per_week=3,
        is_preset=False,
    )

    goal = NutritionGoal(user_id=user_id, daily_calories=2200)
    profile = UserProfile(
        user_id=user_id, weight_kg=80.0, height_cm=180.0, age=30, sex="male"
    )

    db_session.add_all(
        [meal, plan, shopping, session, pr, program, goal, profile]
    )
    await db_session.commit()

    # Two refresh tokens to confirm bulk revocation.
    await create_refresh_token(db_session, user_id)
    await create_refresh_token(db_session, user_id)
    await db_session.commit()

    return {"program_id": program.id, "session_id": session.id}


async def _count(db_session, model, **filters) -> int:
    stmt = select(func.count()).select_from(model)
    for attr, value in filters.items():
        stmt = stmt.where(getattr(model, attr) == value)
    return await db_session.scalar(stmt)


async def test_delete_account_requires_auth(client):
    resp = await client.delete("/api/v1/users/me")
    assert resp.status_code == 401


async def test_delete_account_removes_all_user_data(auth_client, db_session, test_user):
    user_id = test_user.id
    await _seed_full_user_data(db_session, user_id, tag="A")

    # Sanity: data exists before deletion.
    assert await _count(db_session, Meal, user_id=user_id) == 1
    assert await _count(db_session, WorkoutSession, user_id=user_id) == 1
    assert await _count(db_session, RefreshToken, user_id=user_id) == 2

    resp = await auth_client.delete("/api/v1/users/me")
    assert resp.status_code == 204, resp.text

    # Every user-scoped table is empty for this user.
    assert await _count(db_session, Meal, user_id=user_id) == 0
    assert await _count(db_session, MealPlan, user_id=user_id) == 0
    assert await _count(db_session, ShoppingList, user_id=user_id) == 0
    assert await _count(db_session, WorkoutSession, user_id=user_id) == 0
    assert await _count(db_session, PersonalRecord, user_id=user_id) == 0
    assert await _count(db_session, WorkoutProgram, user_id=user_id) == 0
    assert await _count(db_session, NutritionGoal, user_id=user_id) == 0
    assert await _count(db_session, UserProfile, user_id=user_id) == 0

    # Child rows cascaded from their (now-deleted) parents.
    assert await _count(db_session, MealItem) == 0
    assert await _count(db_session, MealPlanItem) == 0
    assert await _count(db_session, ShoppingListItem) == 0
    assert await _count(db_session, WorkoutSet) == 0

    # Refresh tokens gone (FK cascade on user delete) and user row removed.
    assert await _count(db_session, RefreshToken, user_id=user_id) == 0
    from app.models.user import User

    assert await _count(db_session, User, id=user_id) == 0


async def test_delete_account_invalidates_token(auth_client):
    """After deletion the caller's access token no longer authenticates."""
    resp = await auth_client.delete("/api/v1/users/me")
    assert resp.status_code == 204

    # Same bearer token, but the user no longer exists -> 401.
    me = await auth_client.get("/api/v1/auth/me")
    assert me.status_code == 401


async def test_delete_account_does_not_touch_other_user_or_presets(
    auth_client, db_session, test_user, test_user_b
):
    """Deleting user A leaves user B's data and shared presets intact."""
    a_id = test_user.id
    b_id = test_user_b.id
    await _seed_full_user_data(db_session, a_id, tag="A")
    b_ids = await _seed_full_user_data(db_session, b_id, tag="B")

    # A shared preset program (user_id NULL) must never be deleted.
    preset = WorkoutProgram(
        user_id=None, name="Shared Preset", days_per_week=3, is_preset=True
    )
    db_session.add(preset)
    await db_session.commit()

    resp = await auth_client.delete("/api/v1/users/me")
    assert resp.status_code == 204

    # User B's data is fully intact.
    assert await _count(db_session, Meal, user_id=b_id) == 1
    assert await _count(db_session, MealPlan, user_id=b_id) == 1
    assert await _count(db_session, ShoppingList, user_id=b_id) == 1
    assert await _count(db_session, WorkoutSession, user_id=b_id) == 1
    assert await _count(db_session, PersonalRecord, user_id=b_id) == 1
    assert await _count(db_session, NutritionGoal, user_id=b_id) == 1
    assert await _count(db_session, UserProfile, user_id=b_id) == 1
    assert await _count(db_session, WorkoutProgram, id=b_ids["program_id"]) == 1
    assert await _count(db_session, RefreshToken, user_id=b_id) == 2

    # The shared preset survives.
    assert await _count(db_session, WorkoutProgram, id=preset.id) == 1
