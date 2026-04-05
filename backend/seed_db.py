"""Seed database with exercises and workout programs."""
import asyncio
import json
from pathlib import Path
from uuid import uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import async_session, engine, Base
from app.models.exercise import Exercise
from app.models.workout import WorkoutProgram, WorkoutProgramDay


DATA_DIR = Path(__file__).parent / "data"


async def seed_exercises(session: AsyncSession) -> dict[str, Exercise]:
    """Seed exercises from JSON file. Returns name->Exercise map."""
    with open(DATA_DIR / "seed_exercises.json") as f:
        exercises_data = json.load(f)

    exercise_map = {}
    for ex_data in exercises_data:
        # Check if already exists
        result = await session.execute(
            select(Exercise).where(Exercise.name == ex_data["name"])
        )
        existing = result.scalar_one_or_none()
        if existing:
            exercise_map[existing.name] = existing
            continue

        exercise = Exercise(id=uuid4(), **ex_data)
        session.add(exercise)
        exercise_map[exercise.name] = exercise

    await session.flush()
    print(f"Seeded {len(exercise_map)} exercises")
    return exercise_map


async def seed_programs(session: AsyncSession) -> None:
    """Seed workout programs from JSON file."""
    with open(DATA_DIR / "seed_programs.json") as f:
        programs_data = json.load(f)

    for prog_data in programs_data:
        # Check if already exists
        result = await session.execute(
            select(WorkoutProgram).where(WorkoutProgram.name == prog_data["name"])
        )
        if result.scalar_one_or_none():
            continue

        days_data = prog_data.pop("days", [])
        program = WorkoutProgram(
            id=uuid4(),
            is_preset=True,
            user_id=None,
            **prog_data,
        )
        session.add(program)
        await session.flush()

        for day_data in days_data:
            day = WorkoutProgramDay(
                id=uuid4(),
                program_id=program.id,
                **day_data,
            )
            session.add(day)

    await session.flush()
    print(f"Seeded {len(programs_data)} workout programs")


async def main():
    # Create all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session() as session:
        await seed_exercises(session)
        await seed_programs(session)
        await session.commit()

    await engine.dispose()
    print("Database seeded successfully!")


if __name__ == "__main__":
    asyncio.run(main())
