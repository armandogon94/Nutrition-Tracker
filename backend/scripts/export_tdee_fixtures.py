"""Export deterministic TDEE fixture cases for cross-platform parity tests.

The iOS client mirrors the backend's `app.services.tdee_calculator` exactly so
the live preview never lags by a network round-trip. This script is the
authoritative bridge between the two: it imports the backend calculator,
generates a structured matrix of (input -> expected) tuples covering edge
cases, and writes them as JSON. The Swift test target loads the same JSON
and asserts iOS output matches each tuple within a 0.5 kcal tolerance.

If the backend formula ever changes, re-run this script. The iOS test will
go red and the Swift implementation must catch up — backend is the source
of truth for nutrition math.

Usage (from repo root):
    cd backend
    PYTHONPATH=. uv run python scripts/export_tdee_fixtures.py

Output:
    ../ios/FitTrackerTests/Resources/tdee_fixtures.json
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.schemas.profile import ActivityLevel, GoalPreset
from app.services.tdee_calculator import (
    calculate_bmr,
    calculate_macros,
    calculate_tdee,
)


# Edge-case matrix
AGES = [13, 30, 60, 120]
WEIGHTS_KG = [40.0, 80.0, 120.0]
HEIGHTS_CM = [150.0, 175.0, 200.0]
SEXES = ["male", "female"]
ACTIVITIES = list(ActivityLevel)
GOALS = list(GoalPreset)


def make_case(
    weight_kg: float,
    height_cm: float,
    age: int,
    sex: str,
    activity: ActivityLevel,
    goal: GoalPreset,
) -> dict[str, Any]:
    bmr = calculate_bmr(weight_kg, height_cm, age, sex)
    tdee = calculate_tdee(bmr, activity)
    macros = calculate_macros(tdee, goal, weight_kg)
    return {
        "input": {
            "weight_kg": weight_kg,
            "height_cm": height_cm,
            "age": age,
            "sex": sex,
            "activity_level": activity.value,
            "goal_preset": goal.value,
        },
        "expected": {
            "bmr": bmr,
            "tdee": tdee,
            "daily_calories": macros["daily_calories"],
            "daily_protein_g": macros["daily_protein_g"],
            "daily_fat_g": macros["daily_fat_g"],
            "daily_carbs_g": macros["daily_carbs_g"],
        },
    }


def main() -> None:
    cases: list[dict[str, Any]] = []

    # 1. Boundary ages on a typical body (each activity level)
    for age in AGES:
        for activity in ACTIVITIES:
            cases.append(
                make_case(80.0, 175.0, age, "male", activity, GoalPreset.MAINTENANCE)
            )

    # 2. Boundary weights on a typical adult (both sexes, moderate)
    for weight in WEIGHTS_KG:
        for sex in SEXES:
            cases.append(
                make_case(
                    weight, 175.0, 30, sex,
                    ActivityLevel.MODERATE, GoalPreset.MAINTENANCE,
                )
            )

    # 3. Boundary heights (moderate, both sexes)
    for height in HEIGHTS_CM:
        for sex in SEXES:
            cases.append(
                make_case(
                    80.0, height, 30, sex,
                    ActivityLevel.MODERATE, GoalPreset.MAINTENANCE,
                )
            )

    # 4. All goal presets (hits the 1200-kcal floor for the small female)
    for goal in GOALS:
        cases.append(
            make_case(
                40.0, 150.0, 60, "female", ActivityLevel.SEDENTARY, goal
            )
        )

    # 5. Reference case: 80kg / 180cm / 30y male / moderate.
    cases.append(
        make_case(
            80.0, 180.0, 30, "male", ActivityLevel.MODERATE, GoalPreset.MAINTENANCE
        )
    )

    # 6. Fat-loss goal at the floor.
    cases.append(
        make_case(
            40.0, 150.0, 30, "female", ActivityLevel.SEDENTARY, GoalPreset.FAT_LOSS
        )
    )

    cases_sorted = sorted(
        cases,
        key=lambda c: (
            c["input"]["sex"],
            c["input"]["age"],
            c["input"]["weight_kg"],
            c["input"]["height_cm"],
            c["input"]["activity_level"],
            c["input"]["goal_preset"],
        ),
    )

    payload = {
        "version": 1,
        "source": "backend.app.services.tdee_calculator",
        "tolerance_kcal": 0.5,
        "case_count": len(cases_sorted),
        "cases": cases_sorted,
    }

    out_path = (
        Path(__file__).resolve().parent.parent.parent
        / "ios"
        / "FitTrackerTests"
        / "Resources"
        / "tdee_fixtures.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(cases_sorted)} cases -> {out_path}")


if __name__ == "__main__":
    main()
