from app.schemas.profile import ActivityLevel, GoalPreset

ACTIVITY_MULTIPLIERS = {
    ActivityLevel.SEDENTARY: 1.2,
    ActivityLevel.LIGHT: 1.375,
    ActivityLevel.MODERATE: 1.55,
    ActivityLevel.ACTIVE: 1.725,
    ActivityLevel.VERY_ACTIVE: 1.9,
}

GOAL_ADJUSTMENTS = {
    GoalPreset.FAT_LOSS: -500,
    GoalPreset.MAINTENANCE: 0,
    GoalPreset.LEAN_BULK: 250,
    GoalPreset.MUSCLE_GAIN: 500,
}


def calculate_bmr(weight_kg: float, height_cm: float, age: int, sex: str) -> float:
    """Mifflin-St Jeor Equation."""
    sex_factor = 5 if sex == "male" else -161
    return (10 * weight_kg) + (6.25 * height_cm) - (5 * age) + sex_factor


def calculate_tdee(bmr: float, activity_level: ActivityLevel) -> float:
    return bmr * ACTIVITY_MULTIPLIERS[activity_level]


def calculate_macros(tdee: float, goal: GoalPreset, weight_kg: float) -> dict:
    """Calculate daily macro targets. Protein: 2g/kg, Fat: 25% cal, Carbs: remainder."""
    target_cals = tdee + GOAL_ADJUSTMENTS[goal]
    # Floor: 1200 kcal minimum
    target_cals = max(target_cals, 1200)

    protein_g = weight_kg * 2.0
    fat_g = (target_cals * 0.25) / 9
    carbs_g = (target_cals - (protein_g * 4) - (fat_g * 9)) / 4
    # Ensure carbs don't go negative
    carbs_g = max(carbs_g, 0)

    return {
        "daily_calories": int(target_cals),
        "daily_protein_g": int(protein_g),
        "daily_fat_g": int(fat_g),
        "daily_carbs_g": int(carbs_g),
    }
