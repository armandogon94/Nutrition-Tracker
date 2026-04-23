# FitTracker - Health & Fitness Platform

> **Port allocation:** See [PORTS.md](PORTS.md) before changing any docker-compose ports. All ports outside the assigned ranges are taken by other projects.

Mobile-first health and fitness web app with three modules: **Nutrition Tracking** (barcode scanning, photo recognition, meal logging), **Meal Planning** (weekly planner, shopping lists, TDEE calculator), and **Workout Tracker** (programs, gym logging, rest timer, progressive overload). Built for Spanish-speaking Latin American users. Deploys to fit.armandointeligencia.com.

## Tech Stack

Next.js 14+ (App Router, TypeScript, TailwindCSS), FastAPI 0.104+, SQLAlchemy 2.0+ (async), PostgreSQL 16, html5-qrcode, @dnd-kit, Recharts, httpx, Serwist (PWA), Python 3.12+, uv (backend), pnpm (frontend)

## Commands

### Backend
```bash
cd backend
uv sync                                              # Install dependencies
uv run uvicorn app.main:app --reload --port 8001     # Dev server
uv run pytest tests/ -v                              # Run tests
uv run pytest tests/ -v --cov=app                    # Tests with coverage
uv run alembic upgrade head                          # Run migrations
uv run alembic revision --autogenerate -m "desc"     # Create migration
uv run ruff check app/                               # Lint
```

### Frontend
```bash
cd frontend
pnpm install                    # Install dependencies
pnpm dev                        # Dev server (port 3000)
pnpm dev:https                  # Dev with HTTPS (for camera testing)
pnpm test                       # Run vitest
pnpm test -- --coverage         # Tests with coverage
pnpm build                      # Production build
pnpm lint                       # ESLint
```

### Infrastructure
```bash
docker compose up -d                                  # Dev stack (postgres + backend + frontend)
docker compose -f docker-compose.prod.yml up -d       # Production (with Traefik)
```

### Mobile Camera Testing
```bash
# Option 1: mkcert (local HTTPS)
mkcert -install && mkcert localhost 127.0.0.1 ::1

# Option 2: ngrok tunnel
ngrok http 3000

# Option 3: Cloudflare Tunnel
cloudflared tunnel --url http://localhost:3000
```

## Architecture

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
├── docker-compose.yml               # Development
├── docker-compose.prod.yml          # Production (Traefik labels)
├── .env.example                     # All env vars documented
├── PLAN.md                          # Detailed project plan (v2.0)
├── AGENTS.md                        # 7 specialist agent roles
└── .claude/                         # AI assistant context and memory
```

## External APIs

- **Open Food Facts v2**: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json` — 100 req/min products, 10 req/min search. Requires custom User-Agent header. Use `mx.openfoodfacts.org` for Mexico-specific queries.
- **USDA FoodData Central**: `GET https://api.nal.usda.gov/fdc/v1/foods/search` — 1,000 req/hour. API key required. NO native barcode lookup (text search only).
- **FatSecret Platform API**: `GET https://platform.fatsecret.com/rest/food/barcode/find-by-id/v1` — OAuth 1.0a auth. 90%+ barcode success rate, 2.3M+ foods. Free Premier tier. Always pass `format=json`.
- **Claude Vision API**: Photo food recognition via Sonnet model. Base64 image input, ~$0.005-0.015/image. Cross-reference results with USDA/OFF for precise nutrition.
- **Lookup order**: Local DB cache → Open Food Facts (mx then world) → FatSecret → USDA FDC → Claude Vision (photos) → Manual entry
- **Caching**: Products cached in local DB, TTL 7-14 days, cache-aside pattern

## Conventions

- Pydantic v2 for all request/response schemas
- SQLAlchemy 2.0 async style with AsyncSession
- All API endpoints versioned under /api/v1/
- Shared httpx.AsyncClient (not per-request) for external API calls
- `'use client'` directive only where needed (scanner, charts, DnD, interactive forms)
- html5-qrcode must use `next/dynamic` with `ssr: false` (accesses window/navigator)
- @dnd-kit needs `'use client'` but does NOT need `next/dynamic` (no browser API at import)
- All user-facing strings should support Spanish localization
- Mock external APIs in tests (pytest-httpx for backend, vi.mock for frontend)
- Cache product lookups in PostgreSQL (TTL 7-14 days)
- Exercise database seeded from free-exercise-db (800+ exercises, public domain)
- Frontend design skill at `.claude/skills/frontend-design.md` — use for all UI work
- TDEE uses Mifflin-St Jeor equation. Warn if calories < 1200/1500 or carbs < 100g
- 1RM estimation: average of Brzycki and Epley formulas (accurate for 2-10 rep range)

## Known Limitations

- **iOS PWA camera**: WebKit bug #185448 breaks camera in standalone PWA mode. Do NOT set `apple-mobile-web-app-capable` meta tag. Provide manual barcode entry as first-class feature.
- **html5-qrcode**: v2.3.8 stalled since 2023 but functional. Monitor native BarcodeDetector API.
- **HTTPS for camera**: Camera API requires secure context. Localhost exempt on desktop. Use mkcert/ngrok for mobile testing.
- **USDA barcode gap**: No barcode endpoint; text-search product name. Use as fallback only.
- **FatSecret free tier**: Requires "Powered by FatSecret" attribution. `servings.serving` can be object OR array.
- **Vibration API**: Not supported on iOS Safari. Always pair with Web Audio API beep as fallback.
- **Background timers**: Chrome throttles setTimeout to 1/minute after 5min hidden. Use timestamp-based calculation + recalculate on visibilitychange.
- **Claude Vision portions**: Portion weight estimation is ±25-40% — always cross-reference with food databases.

## Database

PostgreSQL 16 with 20+ tables across three modules:
- **Nutrition**: users, products (barcode-indexed), meals, meal_items, daily_nutrition (denormalized), nutrition_goals
- **Meal Planning**: user_profiles (TDEE), meal_plans, meal_plan_items, shopping_lists, shopping_list_items
- **Workouts**: exercises (800+), workout_programs, workout_program_days, workout_program_exercises, workout_sessions, workout_sets, personal_records

Full schema in PLAN.md.

## Testing

- **Backend**: `uv run pytest` — pytest + pytest-httpx for mocking OFF/USDA/FatSecret/Claude calls, pytest-asyncio for async endpoints
- **Frontend**: `pnpm test` — vitest + @testing-library/react + jsdom environment
- **Camera tests**: Mock html5-qrcode module entirely via `vi.mock()`, mock `navigator.mediaDevices.getUserMedia`
- **DnD tests**: Mock @dnd-kit interactions with Testing Library user-event
- **Timer tests**: Mock Web Audio API, performance.now(), and visibilitychange events
- **Integration**: Docker Compose with test PostgreSQL instance
