# FitTracker Test Accounts

## Quick Login Credentials

| User | Email | Password |
|------|-------|----------|
| Carlos (Maintainer) | test1@fittracker.dev | test1234 |
| Maria (Cutter) | test2@fittracker.dev | test1234 |
| Roberto (Bulker) | test3@fittracker.dev | test1234 |

## User Profiles

### Carlos Test — "The Maintainer"
- Male, 30 years old, 80 kg, 180 cm
- Activity: Moderate (1.55x) | Goal: Maintenance
- BMR: ~1780 kcal | TDEE: ~2759 kcal
- Macros: 160g protein, 77g fat, 330g carbs
- Seeded: 3 meals today, 1 workout yesterday (Upper/Lower)

### Maria Test — "The Cutter"
- Female, 25 years old, 60 kg, 165 cm
- Activity: Active (1.725x) | Goal: Fat Loss (-500 kcal)
- BMR: ~1345 kcal | TDEE: ~2320 kcal | Target: ~1820 kcal
- Macros: 120g protein, 51g fat, 229g carbs
- Seeded: 3 meals today, 1 workout yesterday (Full Body)

### Roberto Test — "The Bulker"
- Male, 45 years old, 95 kg, 175 cm
- Activity: Sedentary (1.2x) | Goal: Muscle Gain (+500 kcal)
- BMR: ~1824 kcal | TDEE: ~2189 kcal | Target: ~2689 kcal
- Macros: 190g protein, 75g fat, 299g carbs
- Seeded: 4 meals today, 1 workout yesterday (Legs)

## Seeding Commands

```bash
cd backend
# Seed exercises and programs first (if not already done)
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5433/fit_db" uv run python seed_db.py
# Seed test accounts
DATABASE_URL="postgresql://postgres:postgres@localhost:5433/fit_db" uv run python seed_test_accounts.py
```

## Fixed UUIDs
- User 1: `00000000-0000-0000-0000-000000000001`
- User 2: `00000000-0000-0000-0000-000000000002`
- User 3: `00000000-0000-0000-0000-000000000003`

## Seeded Products

| Barcode | Name | Serving | Cal | Protein | Carbs | Fat |
|---------|------|---------|-----|---------|-------|-----|
| SEED-001 | Chicken Breast (grilled) | 150g | 248 | 46.5g | 0g | 5.4g |
| SEED-002 | Brown Rice (cooked) | 200g | 216 | 5g | 44.8g | 1.8g |
| SEED-003 | Oatmeal | 80g | 304 | 10.6g | 54g | 5.3g |
| SEED-004 | Banana | 120g | 107 | 1.3g | 27.5g | 0.4g |
| SEED-005 | Eggs (2 large) | 100g | 155 | 12.6g | 1.1g | 10.6g |
| SEED-006 | Greek Yogurt | 170g | 100 | 17g | 6g | 0.7g |
| SEED-007 | Salmon Fillet | 170g | 354 | 38.7g | 0g | 21.4g |
| SEED-008 | Sweet Potato | 200g | 172 | 3.2g | 40.4g | 0.2g |

## Notes

- All passwords are hashed with bcrypt via `passlib.context.CryptContext`
- The seed script is idempotent: re-running it will skip existing records
- Meals are dated to "today" (the day the script runs)
- Workout sessions are dated to "yesterday"
- Exercise references require `seed_db.py` to have been run first
- The script uses synchronous SQLAlchemy (not asyncpg) since it is a one-off tool
