# FitTracker - Complete Health & Fitness Platform

[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![Next.js 14](https://img.shields.io/badge/Next.js-14+-black.svg)](https://nextjs.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.104+-009688.svg)](https://fastapi.tiangolo.com/)
[![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-336791.svg)](https://www.postgresql.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3+-3178C6.svg)](https://www.typescriptlang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

All-in-one health and fitness platform combining **nutrition tracking**, **meal planning**, and **workout programming** in a single mobile-first web app. Scan barcodes to log food, plan weekly meals with auto-generated shopping lists, follow structured workout programs, and track progressive overload in the gym.

Built for Spanish-speaking Latin American users. Deploys via Docker Compose behind Traefik with automatic HTTPS.

**Live:** [fit.armandointeligencia.com](https://fit.armandointeligencia.com)

---

## Modules

### Nutrition Tracking

- **Barcode scanning** via device camera (EAN-13, UPC-A, Code-128) using html5-qrcode
- **Photo food recognition** via Claude Vision API -- snap a photo and AI identifies food + estimates portion size
- **Manual barcode entry** as first-class fallback for iOS PWA and camera-denied scenarios
- **Cascading product lookup**: Local DB cache -> Open Food Facts v2 -> USDA FDC -> FatSecret -> manual entry
- **Meal logging** by type: breakfast, lunch, dinner, snacks
- **Macro tracking**: calories, protein, carbs, fat, fiber per meal and daily totals
- **Daily/weekly visualizations**: macro donut charts, calorie trend lines, nutrient stacked bars (Recharts)
- **Product caching** in PostgreSQL (TTL 7-14 days) for instant repeat lookups

### Meal Planning

- **Weekly meal planner** with 7-day x 4-meal grid (Desayuno, Almuerzo, Cena, Snacks)
- **Drag-and-drop** meal assignment using @dnd-kit (touch-friendly, accessible)
- **TDEE calculator** using the Mifflin-St Jeor equation with 5 activity levels
- **Goal presets**: Fat Loss (-500 kcal), Maintenance, Lean Bulk (+250 kcal), Muscle Gain (+500 kcal)
- **Smart macro distribution**: protein at 2g/kg bodyweight, fat at 25% of calories, carbs as remainder
- **Auto-generated shopping lists** grouped by grocery section (12 Latin American market categories)
- **Ingredient aggregation** across meals with unit conversion (cups -> grams, pieces -> grams)
- **Meal templates**: save favorite meals and full-day templates for quick reuse

### Workout Tracker

- **10 pre-built workout programs** with science-backed descriptions:
  - PPL (Push/Pull/Legs) -- 6 days/week, 2x frequency per muscle
  - Upper/Lower Split -- 4 days/week, balanced strength + size
  - Full Body 3x/week -- compound-focused, ideal for beginners
  - Bro Split -- 5 days/week, high per-session volume
  - PHUL (Power Hypertrophy Upper Lower) -- 4 days/week, strength + hypertrophy
  - PHAT (Power Hypertrophy Adaptive Training) -- 5 days/week, advanced
  - 5/3/1 (Wendler) -- periodized strength with Training Max concept
  - Starting Strength / StrongLifts 5x5 -- linear progression for novices
  - German Volume Training -- 10x10 methodology for hypertrophy blocks
  - Custom Program -- user-defined structure
- **Exercise database** with 800+ exercises (primary/secondary muscles, equipment, difficulty, instructions)
- **Gym session logging** with pre-fill from last session, +/- weight buttons, 1-2 tap set completion
- **Smart rest timer** with auto-suggested rest periods (compound: 2-3 min, isolation: 60-90s)
  - Web Audio API beep + Vibration API haptic feedback
  - Screen Wake Lock to prevent screen dimming
  - Accurate even when backgrounded (timestamp-based calculation)
- **Progressive overload tracking**: weight/volume trends per exercise (Recharts line charts)
- **Personal records (PRs)** tracked per exercise with estimated 1RM (Brzycki + Epley formulas)
- **Workout history calendar** with volume-by-muscle-group breakdown

---

## Architecture

```
Mobile Browser (Camera / Touch)
       |
   +---+---+---+---+
   |       |       |
 html5  @dnd-kit  Claude
 -qrcode (DnD)   Vision
   |       |       |
   +---+---+---+---+
       |
   Next.js 14 Frontend (App Router, TypeScript, TailwindCSS)
       |
   FastAPI Backend (/api/v1/)
       |
   +---+---+---+---+---+---+
   |       |       |       |
 Product  TDEE   Workout  Shopping
 Lookup   Calc   Programs  List
 Service  Service Service  Generator
   |
   +---+---+---+---+
   |   |   |       |
  OFF USDA FatSecret Claude
  v2  FDC  API     Vision
   |
   PostgreSQL 16
   (products, meals, exercises, workouts, plans, PRs)
```

### Data Flow

1. **Barcode scan** -> html5-qrcode decodes -> backend checks DB cache -> cascading API lookup -> cache result -> return to frontend
2. **Photo recognition** -> Claude Vision identifies food + estimates grams -> cross-reference with USDA/OFF for precise nutrition -> user confirms -> log to meal
3. **Meal planning** -> user drags foods into weekly grid -> backend calculates daily macros -> generates aggregated shopping list
4. **Workout logging** -> user selects program + day -> logs sets/reps/weight -> backend calculates volume, checks PRs -> updates progressive overload charts

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Next.js 14+, TypeScript, TailwindCSS, @dnd-kit, html5-qrcode, Recharts |
| Backend | FastAPI 0.104+, SQLAlchemy 2.0 (async), Alembic, httpx, Python 3.12+ |
| Database | PostgreSQL 16 (20+ tables: users, products, meals, exercises, workouts, plans, PRs) |
| Food APIs | Open Food Facts v2, USDA FoodData Central, FatSecret Platform (OAuth 1.0a) |
| AI | Claude Vision API (Sonnet) for photo food recognition |
| Timer/Audio | Web Audio API, Vibration API, Screen Wake Lock API |
| PWA | Serwist (service worker), IndexedDB (offline), Background Sync |
| Deployment | Docker Compose, Traefik v3, Let's Encrypt auto-HTTPS |
| Testing | pytest + pytest-httpx (backend), vitest + Testing Library (frontend) |
| Package Managers | uv (Python), pnpm (Node.js) |

---

## Quick Start

### Prerequisites

- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Node.js 20+ with [pnpm](https://pnpm.io/)
- PostgreSQL 16 (or Docker Desktop)

### Backend

```bash
cd backend
uv sync                                    # Install dependencies
cp ../.env.example ../.env                 # Configure API keys
uv run alembic upgrade head                # Run database migrations
uv run uvicorn app.main:app --reload --port 8001
# API docs: http://localhost:8001/docs
```

### Frontend

```bash
cd frontend
pnpm install
pnpm dev
# App: http://localhost:3000
```

### Docker (Full Stack)

```bash
cp .env.example .env                       # Configure credentials
docker compose up -d
# Frontend: http://localhost:3030
# Backend:  http://localhost:8030
# API docs: http://localhost:8030/docs
```

---

## API Endpoints

### Nutrition

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/products/search?barcode=...` | Lookup product by barcode (cascading sources) |
| `POST` | `/api/v1/products` | Create manual product entry |
| `POST` | `/api/v1/products/recognize` | Photo food recognition via Claude Vision |
| `POST` | `/api/v1/meals` | Create new meal |
| `POST` | `/api/v1/meals/{meal_id}/items` | Add food item to meal |
| `GET` | `/api/v1/meals/{date}` | Get all meals for a date |
| `DELETE` | `/api/v1/meals/{meal_id}/items/{item_id}` | Remove food from meal |
| `GET` | `/api/v1/nutrition/daily/{date}` | Daily nutrition summary |
| `GET` | `/api/v1/nutrition/weekly?start_date=...&end_date=...` | Weekly nutrition data |
| `GET` | `/api/v1/nutrition/goals` | Get nutrition goals |
| `PUT` | `/api/v1/nutrition/goals` | Update nutrition goals |

### Meal Planning

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/meals/plans` | Create weekly meal plan |
| `GET` | `/api/v1/meals/plans/{plan_id}` | Get meal plan with all items |
| `PUT` | `/api/v1/meals/plans/{plan_id}` | Update meal plan |
| `POST` | `/api/v1/meals/plans/{plan_id}/items` | Add food to plan slot |
| `DELETE` | `/api/v1/meals/plans/{plan_id}/items/{item_id}` | Remove food from plan |
| `GET` | `/api/v1/meals/shopping-list/generate/{plan_id}` | Generate shopping list from plan |
| `PATCH` | `/api/v1/meals/shopping-lists/{id}/items/{id}/check` | Toggle item checked |

### Profile & TDEE

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/profile` | Create/update user profile (weight, height, age, sex, activity) |
| `GET` | `/api/v1/profile/tdee` | Get calculated BMR, TDEE, and macro targets |
| `POST` | `/api/v1/profile/goals` | Set goal preset or custom macros |

### Workouts

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/workouts/programs` | List all programs (presets + custom) |
| `GET` | `/api/v1/workouts/programs/{id}` | Get program with days and exercises |
| `POST` | `/api/v1/workouts/programs` | Create custom program |
| `POST` | `/api/v1/workouts/sessions` | Start workout session |
| `POST` | `/api/v1/workouts/sessions/{id}/sets` | Log a completed set |
| `PATCH` | `/api/v1/workouts/sessions/{id}/complete` | End workout session |
| `GET` | `/api/v1/workouts/history?start_date=...&end_date=...` | Workout history |
| `GET` | `/api/v1/workouts/volume?period=week` | Volume by muscle group |

### Exercises

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/exercises` | List exercises (filter by muscle, equipment, difficulty) |
| `GET` | `/api/v1/exercises/{id}` | Exercise details with instructions |
| `GET` | `/api/v1/exercises/search?q=...&muscle=...` | Search exercises |

---

## Database Schema

20+ tables organized across three modules:

**Nutrition**: `users`, `products` (barcode-indexed cache), `meals`, `meal_items`, `daily_nutrition` (denormalized), `nutrition_goals`

**Meal Planning**: `user_profiles` (weight/height/TDEE), `meal_plans`, `meal_plan_items`, `shopping_lists`, `shopping_list_items`

**Workouts**: `exercises` (800+), `workout_programs`, `workout_program_days`, `workout_program_exercises`, `workout_sessions`, `workout_sets`, `personal_records`

All tables use UUID primary keys, `TIMESTAMPTZ` for timestamps, `NUMERIC` for measurements. Foreign keys are indexed. Full schema in [PLAN.md](PLAN.md).

---

## Project Structure

```
03-Nutrition-Tracker/
├── frontend/                        # Next.js 14+ (App Router)
│   ├── app/                         # Pages
│   │   ├── dashboard/               # Daily summary, macro charts
│   │   ├── scan/                    # Barcode scanner + photo recognition
│   │   ├── meals/                   # Meal logging and history
│   │   │   ├── plan/                # Weekly meal planner (drag-and-drop)
│   │   │   └── shopping/            # Shopping list viewer
│   │   ├── goals/                   # Nutrition goals + TDEE calculator
│   │   ├── profile/                 # User profile setup
│   │   ├── workouts/                # Program selector + session logger
│   │   │   ├── log/                 # Active workout with rest timer
│   │   │   └── history/             # Calendar + analytics
│   │   └── exercises/               # Exercise database browser
│   ├── components/
│   │   ├── scanner/                 # BarcodeScanner, ManualEntry, PhotoCapture
│   │   ├── meals/                   # MealCard, MealPlannerGrid, ShoppingList
│   │   ├── charts/                  # MacroPieChart, CalorieTrendChart, VolumeTrend
│   │   ├── workouts/                # WorkoutLogger, RestTimer, ExerciseCard
│   │   └── ui/                      # Shared UI components
│   ├── lib/                         # API client, types, utilities
│   └── public/                      # PWA manifest, icons
├── backend/                         # FastAPI
│   ├── app/
│   │   ├── api/v1/                  # Route handlers (products, meals, workouts, exercises, profile)
│   │   ├── models/                  # SQLAlchemy models (20+ tables)
│   │   ├── schemas/                 # Pydantic v2 request/response schemas
│   │   ├── services/                # Business logic
│   │   │   ├── product_lookup.py    # Cascading OFF -> USDA -> FatSecret
│   │   │   ├── food_recognition.py  # Claude Vision photo analysis
│   │   │   ├── nutrition_calc.py    # Daily macro aggregation
│   │   │   ├── tdee_calculator.py   # Mifflin-St Jeor + macro distribution
│   │   │   ├── shopping_list.py     # Ingredient aggregation + unit conversion
│   │   │   └── workout_service.py   # Session logging, PR detection, volume calc
│   │   └── core/                    # Config, database, dependencies
│   ├── alembic/                     # Database migrations
│   ├── data/                        # Seed data (exercises.json, programs.json)
│   └── tests/                       # pytest test suite
├── docker-compose.yml               # Development stack
├── docker-compose.prod.yml          # Production (Traefik + auto-HTTPS)
├── .env.example                     # All environment variables documented
├── PLAN.md                          # Detailed project plan (v2.0)
├── AGENTS.md                        # 7 specialist agent roles
└── .claude/                         # AI assistant context and memory
```

---

## Testing

### Backend (pytest)

```bash
cd backend
uv run pytest tests/ -v                    # All tests
uv run pytest tests/ -v --cov=app          # With coverage
```

Tests mock all external API calls via `pytest-httpx`. Coverage includes:
- Product lookup with mocked OFF, USDA, FatSecret responses
- Meal CRUD and daily/weekly nutrition calculations
- TDEE calculator (Mifflin-St Jeor equation, all activity levels, all goal presets)
- Workout session logging, PR detection, volume calculation
- Shopping list generation and ingredient aggregation
- Error handling (API timeouts, rate limits, missing data)

### Frontend (vitest)

```bash
cd frontend
pnpm test                                  # All tests
pnpm test -- --coverage                    # With coverage
```

Tests mock camera access, html5-qrcode, and @dnd-kit interactions. Coverage includes:
- Barcode scanner component (camera permissions, scan detection, cleanup)
- Manual barcode entry and photo capture
- Meal planner drag-and-drop grid
- Workout logger (set/rep/weight input, rest timer countdown)
- All Recharts visualizations (macro donut, calorie trends, volume charts)

---

## Mobile Testing (Camera Access)

Camera access requires HTTPS on mobile. Localhost is exempt on desktop.

```bash
# Option 1: mkcert (local HTTPS certificates)
brew install mkcert nss
mkcert -install && mkcert localhost 127.0.0.1 ::1
cd frontend && pnpm dev:https

# Option 2: ngrok tunnel
ngrok http 3000

# Option 3: Cloudflare Tunnel (free, no account)
cloudflared tunnel --url http://localhost:3000
```

**iOS PWA note**: Camera breaks in standalone PWA mode due to [WebKit bug #185448](https://bugs.webkit.org/show_bug.cgi?id=185448). The `apple-mobile-web-app-capable` meta tag is intentionally NOT set. Manual barcode entry is always available as a first-class alternative.

---

## Deployment

Production uses Docker Compose behind Traefik with automatic Let's Encrypt HTTPS:

```bash
# On VPS
docker compose -f docker-compose.prod.yml up -d
```

| Service | Domain | Port |
|---------|--------|------|
| Frontend | `fit.armandointeligencia.com` | 3000 |
| Backend | `api.fit.armandointeligencia.com` | 8000 |
| Database | Internal network only | 5432 |
| Traefik | Reverse proxy | 80/443 |

**Infrastructure**: Hostinger KVM2 VPS (2 vCPU, 8GB RAM, Ubuntu), Docker Compose, Traefik v3 with ACME HTTP challenge.

---

## Environment Variables

```bash
# Database
DATABASE_URL=postgresql+asyncpg://postgres:password@localhost:5432/fit_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=change-me
POSTGRES_DB=fit_db

# Open Food Facts (no key needed)
OFF_BASE_URL=https://world.openfoodfacts.org
OFF_USER_AGENT=FitTracker/2.0 (fit.armandointeligencia.com)

# USDA FoodData Central (free key: https://fdc.nal.usda.gov/api-key-signup)
USDA_FDC_KEY=your_key

# FatSecret (OAuth 1.0a: https://platform.fatsecret.com/platform-api)
FATSECRET_CONSUMER_KEY=your_key
FATSECRET_CONSUMER_SECRET=your_secret

# Claude Vision (for photo food recognition)
ANTHROPIC_API_KEY=your_key

# Application
ENVIRONMENT=development
SECRET_KEY=change-me-in-production
BACKEND_PORT=8030
FRONTEND_PORT=3030
NEXT_PUBLIC_API_URL=http://localhost:8030
```

---

## External APIs

| API | Auth | Rate Limit | Coverage | Used For |
|-----|------|------------|----------|----------|
| [Open Food Facts v2](https://world.openfoodfacts.org) | User-Agent header | 100/min (product), 10/min (search) | 4M+ products, strong Mexico coverage | Primary barcode lookup |
| [USDA FoodData Central](https://fdc.nal.usda.gov) | Free API key | 1,000/hour | Detailed US nutrition data | Text search fallback |
| [FatSecret Platform](https://platform.fatsecret.com) | OAuth 1.0a | ~5,000/day (free) | 2.3M+ foods, 90%+ barcode hit rate | Barcode fallback |
| [Claude Vision API](https://docs.anthropic.com) | API key | Standard limits | AI-powered | Photo food recognition |

---

## Workout Programs

| Program | Days/Week | Duration | Level | Best For |
|---------|-----------|----------|-------|----------|
| PPL (Push/Pull/Legs) | 6 | 60-90 min | Beginner+ | Maximum hypertrophy, 2x/week frequency |
| Upper/Lower Split | 4 | 60-75 min | Intermediate | Balanced strength + size, busy schedules |
| Full Body | 3 | 45-60 min | Beginner | Foundation building, compound focus |
| Bro Split | 5 | 60-90 min | Intermediate+ | High per-muscle volume, isolation focus |
| PHUL | 4 | 60-75 min | Intermediate+ | Combined power + hypertrophy |
| PHAT | 5 | 75-90 min | Advanced | Layne Norton's power-hypertrophy system |
| 5/3/1 (Wendler) | 3-4 | 45-75 min | Intermediate | Periodized strength, long-term progression |
| Starting Strength / 5x5 | 3 | 45-60 min | Beginner | Linear progression, rapid novice gains |
| German Volume Training | 4-5 | 60-75 min | Advanced | 10x10 hypertrophy shock, short-term blocks |
| Custom | User-defined | Variable | Any | Full control over structure |

---

## TDEE Calculator

Uses the **Mifflin-St Jeor equation** (recommended by the Academy of Nutrition and Dietetics as the most accurate predictive formula):

```
Males:   BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) + 5
Females: BMR = (10 x weight_kg) + (6.25 x height_cm) - (5 x age) - 161
TDEE = BMR x Activity Multiplier
```

| Activity Level | Multiplier | Description |
|---------------|------------|-------------|
| Sedentary | 1.2 | Desk job, no exercise |
| Lightly Active | 1.375 | Light exercise 1-3 days/week |
| Moderately Active | 1.55 | Moderate exercise 3-5 days/week |
| Very Active | 1.725 | Hard exercise 6-7 days/week |
| Extra Active | 1.9 | Intense training 2x/day |

**Macro distribution**: Protein = 2g/kg bodyweight, Fat = 25% of target calories, Carbs = remaining calories. Warns if carbs fall below 100g/day or total calories below 1200 (women) / 1500 (men).

---

## License

MIT
