"""Seed test accounts with full data for development and QA."""
import asyncio
import uuid
from datetime import date, datetime, timedelta

import bcrypt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import Base, async_session, engine
from app.models.exercise import Exercise
from app.models.goal import NutritionGoal
from app.models.meal import Meal, MealItem
from app.models.product import Product
from app.models.user import User
from app.models.user_profile import UserProfile
from app.models.workout import WorkoutSession, WorkoutSet

# Fixed UUIDs
USER1_ID = uuid.UUID("00000000-0000-0000-0000-000000000001")
USER2_ID = uuid.UUID("00000000-0000-0000-0000-000000000002")
USER3_ID = uuid.UUID("00000000-0000-0000-0000-000000000003")

TODAY = date.today()
YESTERDAY = TODAY - timedelta(days=1)
YESTERDAY_DT = datetime.combine(YESTERDAY, datetime.min.time()).replace(hour=17, minute=0)

PASSWORD_HASH = bcrypt.hashpw(b"test1234", bcrypt.gensalt()).decode("utf-8")

PRODUCTS = [
    {"barcode": "SEED-001", "name": "Chicken Breast (grilled)", "brand": "FitTracker Seed", "serving_size_g": 150.0, "calories": 248.0, "protein_g": 46.5, "carbs_g": 0.0, "fat_g": 5.4, "fiber_g": 0.0, "source": "seed"},
    {"barcode": "SEED-002", "name": "Brown Rice (cooked)", "brand": "FitTracker Seed", "serving_size_g": 200.0, "calories": 216.0, "protein_g": 5.0, "carbs_g": 44.8, "fat_g": 1.8, "fiber_g": 3.5, "source": "seed"},
    {"barcode": "SEED-003", "name": "Oatmeal", "brand": "FitTracker Seed", "serving_size_g": 80.0, "calories": 304.0, "protein_g": 10.6, "carbs_g": 54.0, "fat_g": 5.3, "fiber_g": 8.0, "source": "seed"},
    {"barcode": "SEED-004", "name": "Banana", "brand": "FitTracker Seed", "serving_size_g": 120.0, "calories": 107.0, "protein_g": 1.3, "carbs_g": 27.5, "fat_g": 0.4, "fiber_g": 2.6, "source": "seed"},
    {"barcode": "SEED-005", "name": "Eggs (2 large)", "brand": "FitTracker Seed", "serving_size_g": 100.0, "calories": 155.0, "protein_g": 12.6, "carbs_g": 1.1, "fat_g": 10.6, "fiber_g": 0.0, "source": "seed"},
    {"barcode": "SEED-006", "name": "Greek Yogurt", "brand": "FitTracker Seed", "serving_size_g": 170.0, "calories": 100.0, "protein_g": 17.0, "carbs_g": 6.0, "fat_g": 0.7, "fiber_g": 0.0, "source": "seed"},
    {"barcode": "SEED-007", "name": "Salmon Fillet", "brand": "FitTracker Seed", "serving_size_g": 170.0, "calories": 354.0, "protein_g": 38.7, "carbs_g": 0.0, "fat_g": 21.4, "fiber_g": 0.0, "source": "seed"},
    {"barcode": "SEED-008", "name": "Sweet Potato", "brand": "FitTracker Seed", "serving_size_g": 200.0, "calories": 172.0, "protein_g": 3.2, "carbs_g": 40.4, "fat_g": 0.2, "fiber_g": 6.0, "source": "seed"},
]


async def get_product_map(session: AsyncSession) -> dict[str, Product]:
    result = await session.execute(select(Product).where(Product.barcode.like("SEED-%")))
    return {p.barcode: p for p in result.scalars().all()}


async def get_exercise_map(session: AsyncSession, names: list[str]) -> dict[str, Exercise]:
    result = await session.execute(select(Exercise).where(Exercise.name.in_(names)))
    return {e.name: e for e in result.scalars().all()}


async def seed_users(session: AsyncSession) -> None:
    users = [
        User(id=USER1_ID, email="test1@fittracker.dev", password_hash=PASSWORD_HASH, display_name="Carlos Test"),
        User(id=USER2_ID, email="test2@fittracker.dev", password_hash=PASSWORD_HASH, display_name="Maria Test"),
        User(id=USER3_ID, email="test3@fittracker.dev", password_hash=PASSWORD_HASH, display_name="Roberto Test"),
    ]
    for u in users:
        existing = (await session.execute(select(User).where(User.id == u.id))).scalar_one_or_none()
        if existing:
            print(f"  User '{existing.display_name}' already exists, skipping")
            continue
        session.add(u)
    await session.flush()
    print(f"Seeded {len(users)} test users")


async def seed_profiles(session: AsyncSession) -> None:
    profiles = [
        UserProfile(id=uuid.uuid4(), user_id=USER1_ID, weight_kg=80.0, height_cm=180.0, age=30, sex="male", activity_level="moderate", goal_preset="maintenance", bmr=1780.0, tdee=2759.0, custom_daily_calories=2759, custom_protein_g=160, custom_carbs_g=330, custom_fat_g=77),
        UserProfile(id=uuid.uuid4(), user_id=USER2_ID, weight_kg=60.0, height_cm=165.0, age=25, sex="female", activity_level="active", goal_preset="fat_loss", bmr=1345.0, tdee=2320.0, custom_daily_calories=1820, custom_protein_g=120, custom_carbs_g=229, custom_fat_g=51),
        UserProfile(id=uuid.uuid4(), user_id=USER3_ID, weight_kg=95.0, height_cm=175.0, age=45, sex="male", activity_level="sedentary", goal_preset="muscle_gain", bmr=1824.0, tdee=2189.0, custom_daily_calories=2689, custom_protein_g=190, custom_carbs_g=299, custom_fat_g=75),
    ]
    for p in profiles:
        existing = (await session.execute(select(UserProfile).where(UserProfile.user_id == p.user_id))).scalar_one_or_none()
        if existing:
            print(f"  Profile for user {p.user_id} already exists, skipping")
            continue
        session.add(p)
    await session.flush()
    print(f"Seeded {len(profiles)} user profiles")


async def seed_goals(session: AsyncSession) -> None:
    goals = [
        NutritionGoal(id=uuid.uuid4(), user_id=USER1_ID, daily_calories=2759, daily_protein_g=160, daily_carbs_g=330, daily_fat_g=77),
        NutritionGoal(id=uuid.uuid4(), user_id=USER2_ID, daily_calories=1820, daily_protein_g=120, daily_carbs_g=229, daily_fat_g=51),
        NutritionGoal(id=uuid.uuid4(), user_id=USER3_ID, daily_calories=2689, daily_protein_g=190, daily_carbs_g=299, daily_fat_g=75),
    ]
    for g in goals:
        existing = (await session.execute(select(NutritionGoal).where(NutritionGoal.user_id == g.user_id))).scalar_one_or_none()
        if existing:
            print(f"  Goal for user {g.user_id} already exists, skipping")
            continue
        session.add(g)
    await session.flush()
    print(f"Seeded {len(goals)} nutrition goals")


async def seed_products(session: AsyncSession) -> None:
    count = 0
    for pdata in PRODUCTS:
        existing = (await session.execute(select(Product).where(Product.barcode == pdata["barcode"]))).scalar_one_or_none()
        if existing:
            continue
        session.add(Product(id=uuid.uuid4(), **pdata))
        count += 1
    await session.flush()
    print(f"Seeded {count} products ({len(PRODUCTS) - count} already existed)")


async def _create_meal(session: AsyncSession, user_id: uuid.UUID, meal_type: str, meal_date: date, items: list[tuple]) -> None:
    existing = (await session.execute(select(Meal).where(Meal.user_id == user_id, Meal.meal_type == meal_type, Meal.meal_date == meal_date))).scalar_one_or_none()
    if existing:
        return
    meal = Meal(id=uuid.uuid4(), user_id=user_id, meal_type=meal_type, meal_date=meal_date)
    session.add(meal)
    await session.flush()
    for product, qty_servings, qty_grams in items:
        session.add(MealItem(id=uuid.uuid4(), meal_id=meal.id, product_id=product.id, quantity_servings=qty_servings, quantity_grams=qty_grams))


async def seed_meals(session: AsyncSession) -> None:
    pm = await get_product_map(session)
    if not pm:
        print("  WARNING: No seed products found.")
        return

    # Carlos (User 1): 3 meals, maintenance
    await _create_meal(session, USER1_ID, "breakfast", TODAY, [(pm["SEED-003"], 1.0, 80.0), (pm["SEED-004"], 1.0, 120.0), (pm["SEED-005"], 1.0, 100.0)])
    await _create_meal(session, USER1_ID, "lunch", TODAY, [(pm["SEED-001"], 1.5, 225.0), (pm["SEED-002"], 1.0, 200.0), (pm["SEED-008"], 0.5, 100.0)])
    await _create_meal(session, USER1_ID, "dinner", TODAY, [(pm["SEED-007"], 1.0, 170.0), (pm["SEED-002"], 1.0, 200.0), (pm["SEED-006"], 1.0, 170.0)])

    # Maria (User 2): 3 meals, fat loss
    await _create_meal(session, USER2_ID, "breakfast", TODAY, [(pm["SEED-006"], 1.0, 170.0), (pm["SEED-004"], 1.0, 120.0)])
    await _create_meal(session, USER2_ID, "lunch", TODAY, [(pm["SEED-001"], 1.0, 150.0), (pm["SEED-008"], 1.0, 200.0)])
    await _create_meal(session, USER2_ID, "dinner", TODAY, [(pm["SEED-007"], 0.75, 127.5), (pm["SEED-002"], 0.75, 150.0)])

    # Roberto (User 3): 4 meals, muscle gain
    await _create_meal(session, USER3_ID, "breakfast", TODAY, [(pm["SEED-003"], 1.5, 120.0), (pm["SEED-005"], 1.5, 150.0), (pm["SEED-004"], 1.0, 120.0)])
    await _create_meal(session, USER3_ID, "lunch", TODAY, [(pm["SEED-001"], 2.0, 300.0), (pm["SEED-002"], 1.5, 300.0)])
    await _create_meal(session, USER3_ID, "snack", TODAY, [(pm["SEED-006"], 1.5, 255.0), (pm["SEED-004"], 1.0, 120.0)])
    await _create_meal(session, USER3_ID, "dinner", TODAY, [(pm["SEED-007"], 1.5, 255.0), (pm["SEED-008"], 1.0, 200.0), (pm["SEED-002"], 1.0, 200.0)])

    await session.flush()
    print("Seeded meals for all 3 users (today's date)")


async def _create_workout(session: AsyncSession, user_id: uuid.UUID, started_at: datetime, duration_minutes: int, notes: str, sets: list[tuple]) -> None:
    session_date = started_at.date()
    existing = (await session.execute(
        select(WorkoutSession).where(WorkoutSession.user_id == user_id, WorkoutSession.started_at >= datetime.combine(session_date, datetime.min.time()), WorkoutSession.started_at < datetime.combine(session_date + timedelta(days=1), datetime.min.time()))
    )).scalar_one_or_none()
    if existing:
        print(f"  Workout for user {user_id} on {session_date} exists, skipping")
        return
    ws = WorkoutSession(id=uuid.uuid4(), user_id=user_id, started_at=started_at, completed_at=started_at + timedelta(minutes=duration_minutes), duration_minutes=duration_minutes, notes=notes)
    session.add(ws)
    await session.flush()
    for exercise, set_number, reps, weight_kg, rpe in sets:
        session.add(WorkoutSet(id=uuid.uuid4(), session_id=ws.id, exercise_id=exercise.id, set_number=set_number, reps=reps, weight_kg=weight_kg, rpe=rpe, is_pr=False))


async def seed_workouts(session: AsyncSession) -> None:
    names = ["Barbell Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown", "Dumbbell Curl", "Tricep Pushdown", "Barbell Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Leg Extension", "Calf Raises", "Push-Up", "Dumbbell Shoulder Press", "Dumbbell Row", "Plank"]
    em = await get_exercise_map(session, names)
    if not em:
        print("  WARNING: No exercises found. Run seed_db.py first.")
        return

    # Carlos: Upper body
    await _create_workout(session, USER1_ID, YESTERDAY_DT, 65, "Upper body day - felt strong", [
        (em["Barbell Bench Press"], 1, 8, 80.0, 7.0), (em["Barbell Bench Press"], 2, 8, 80.0, 7.5), (em["Barbell Bench Press"], 3, 7, 80.0, 8.0),
        (em["Barbell Row"], 1, 10, 70.0, 7.0), (em["Barbell Row"], 2, 10, 70.0, 7.5), (em["Barbell Row"], 3, 9, 70.0, 8.0),
        (em["Overhead Press"], 1, 8, 50.0, 7.0), (em["Overhead Press"], 2, 7, 50.0, 7.5),
        (em["Lat Pulldown"], 1, 12, 55.0, 6.5), (em["Lat Pulldown"], 2, 11, 55.0, 7.0),
        (em["Dumbbell Curl"], 1, 12, 14.0, 7.0), (em["Tricep Pushdown"], 1, 15, 25.0, 6.5),
    ])

    # Maria: Full body
    await _create_workout(session, USER2_ID, YESTERDAY_DT.replace(hour=7, minute=30), 50, "Full body morning session", [
        (em["Barbell Back Squat"], 1, 10, 40.0, 6.5), (em["Barbell Back Squat"], 2, 10, 40.0, 7.0), (em["Barbell Back Squat"], 3, 8, 40.0, 7.5),
        (em["Push-Up"], 1, 15, None, 6.0), (em["Push-Up"], 2, 12, None, 7.0),
        (em["Dumbbell Row"], 1, 12, 12.0, 6.5), (em["Dumbbell Row"], 2, 12, 12.0, 7.0),
        (em["Dumbbell Shoulder Press"], 1, 10, 10.0, 7.0), (em["Dumbbell Shoulder Press"], 2, 8, 10.0, 7.5),
    ])

    # Roberto: Legs
    await _create_workout(session, USER3_ID, YESTERDAY_DT.replace(hour=18, minute=0), 75, "Legs day - heavy squats", [
        (em["Barbell Back Squat"], 1, 8, 100.0, 7.0), (em["Barbell Back Squat"], 2, 8, 100.0, 7.5), (em["Barbell Back Squat"], 3, 6, 100.0, 8.0),
        (em["Romanian Deadlift"], 1, 10, 80.0, 7.0), (em["Romanian Deadlift"], 2, 10, 80.0, 7.5), (em["Romanian Deadlift"], 3, 8, 80.0, 8.0),
        (em["Leg Press"], 1, 12, 140.0, 6.5), (em["Leg Press"], 2, 12, 140.0, 7.0), (em["Leg Press"], 3, 10, 140.0, 7.5),
        (em["Leg Curl"], 1, 12, 35.0, 7.0), (em["Leg Curl"], 2, 10, 35.0, 7.5),
        (em["Leg Extension"], 1, 15, 40.0, 6.5), (em["Leg Extension"], 2, 12, 40.0, 7.0),
        (em["Calf Raises"], 1, 15, 60.0, 6.0), (em["Calf Raises"], 2, 15, 60.0, 6.5),
    ])

    await session.flush()
    print("Seeded workout sessions for all 3 users (yesterday)")


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        print("=== Seeding test accounts ===")
        await seed_users(session)
        await seed_profiles(session)
        await seed_goals(session)
        await seed_products(session)
        await seed_meals(session)
        await seed_workouts(session)
        await session.commit()

    await engine.dispose()
    print("\nTest accounts seeded successfully!")
    print("  test1@fittracker.dev / test1234  (Carlos - Maintainer)")
    print("  test2@fittracker.dev / test1234  (Maria  - Cutter)")
    print("  test3@fittracker.dev / test1234  (Roberto - Bulker)")


if __name__ == "__main__":
    asyncio.run(main())
