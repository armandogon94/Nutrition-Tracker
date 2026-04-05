import pytest
from app.services.tdee_calculator import calculate_bmr, calculate_macros, calculate_tdee
from app.schemas.profile import ActivityLevel, GoalPreset


class TestCalculateBMR:
    def test_male_bmr(self):
        # 80kg, 180cm, 30yo male
        bmr = calculate_bmr(80, 180, 30, "male")
        # 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5 = 1780
        assert bmr == 1780.0

    def test_female_bmr(self):
        # 60kg, 165cm, 25yo female
        bmr = calculate_bmr(60, 165, 25, "female")
        # 10*60 + 6.25*165 - 5*25 - 161 = 600 + 1031.25 - 125 - 161 = 1345.25
        assert bmr == 1345.25

    def test_edge_case_young(self):
        bmr = calculate_bmr(50, 150, 18, "male")
        assert bmr > 0

    def test_edge_case_heavy(self):
        bmr = calculate_bmr(150, 190, 40, "male")
        assert bmr > 2000


class TestCalculateTDEE:
    def test_sedentary(self):
        tdee = calculate_tdee(1780, ActivityLevel.SEDENTARY)
        assert tdee == pytest.approx(1780 * 1.2, rel=0.01)

    def test_moderate(self):
        tdee = calculate_tdee(1780, ActivityLevel.MODERATE)
        assert tdee == pytest.approx(1780 * 1.55, rel=0.01)

    def test_very_active(self):
        tdee = calculate_tdee(1780, ActivityLevel.VERY_ACTIVE)
        assert tdee == pytest.approx(1780 * 1.9, rel=0.01)


class TestCalculateMacros:
    def test_maintenance_macros(self):
        macros = calculate_macros(2500, GoalPreset.MAINTENANCE, 80)
        assert macros["daily_calories"] == 2500
        assert macros["daily_protein_g"] == 160  # 80 * 2
        assert macros["daily_fat_g"] == int((2500 * 0.25) / 9)
        assert macros["daily_carbs_g"] > 0

    def test_fat_loss_macros(self):
        macros = calculate_macros(2500, GoalPreset.FAT_LOSS, 80)
        assert macros["daily_calories"] == 2000  # 2500 - 500

    def test_muscle_gain_macros(self):
        macros = calculate_macros(2500, GoalPreset.MUSCLE_GAIN, 80)
        assert macros["daily_calories"] == 3000  # 2500 + 500

    def test_lean_bulk_macros(self):
        macros = calculate_macros(2500, GoalPreset.LEAN_BULK, 80)
        assert macros["daily_calories"] == 2750  # 2500 + 250

    def test_floor_prevents_very_low_calories(self):
        macros = calculate_macros(1500, GoalPreset.FAT_LOSS, 50)
        assert macros["daily_calories"] >= 1200

    def test_macros_sum_to_calories(self):
        macros = calculate_macros(2500, GoalPreset.MAINTENANCE, 80)
        calculated_cals = macros["daily_protein_g"] * 4 + macros["daily_carbs_g"] * 4 + macros["daily_fat_g"] * 9
        # Allow rounding tolerance
        assert abs(calculated_cals - macros["daily_calories"]) < 20


class TestWorkoutService:
    def test_estimate_1rm_basic(self):
        from app.services.workout_service import estimate_1rm
        # 100kg x 5 reps
        e1rm = estimate_1rm(100, 5)
        assert 110 < e1rm < 125  # Should be around 116-117

    def test_estimate_1rm_single_rep(self):
        from app.services.workout_service import estimate_1rm
        assert estimate_1rm(100, 1) == 100

    def test_estimate_1rm_zero_weight(self):
        from app.services.workout_service import estimate_1rm
        assert estimate_1rm(0, 5) == 0.0

    def test_estimate_1rm_zero_reps(self):
        from app.services.workout_service import estimate_1rm
        assert estimate_1rm(100, 0) == 0.0
