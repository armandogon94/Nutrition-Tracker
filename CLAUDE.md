# Nutrition Tracker with Barcode Scanner

Mobile-first nutrition tracking web app with real-time barcode scanning via device camera. Scan food products, log meals, track macros, and visualize daily/weekly nutrition trends. Built for Spanish-speaking Latin American users with Open Food Facts + USDA FDC + FatSecret integration. Deploys to nutrition.armandointeligencia.com.

## Tech Stack

Next.js 14+ (App Router, TypeScript, TailwindCSS), FastAPI 0.104+, SQLAlchemy 2.0+ (async), PostgreSQL 16, html5-qrcode, Recharts, httpx, Serwist (PWA), Python 3.12+, uv (backend), pnpm (frontend)

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
├── frontend/                    # Next.js 14+ (App Router)
│   ├── app/                     # App Router pages
│   │   ├── dashboard/           # Daily summary, macro donut, recent meals
│   │   ├── scan/                # Barcode scanner + manual entry
│   │   ├── meals/               # Meal logging & history
│   │   └── goals/               # Nutrition goal settings
│   ├── components/
│   │   ├── scanner/             # BarcodeScanner, ManualEntry
│   │   ├── meals/               # MealCard, MealItemRow
│   │   ├── charts/              # MacroPieChart, CalorieTrendChart, NutrientBarChart
│   │   └── ui/                  # Shared UI components
│   ├── lib/                     # API client, types, utils
│   └── public/                  # Static assets, PWA manifest, icons
├── backend/                     # FastAPI
│   ├── app/
│   │   ├── api/v1/              # Route handlers (products, meals, nutrition, goals)
│   │   ├── models/              # SQLAlchemy models
│   │   ├── schemas/             # Pydantic v2 schemas
│   │   ├── services/            # Business logic (product_lookup, nutrition_calc)
│   │   └── core/                # Config, database, dependencies
│   ├── alembic/                 # Database migrations
│   └── tests/                   # pytest tests
├── docker-compose.yml           # Development
├── docker-compose.prod.yml      # Production (Traefik labels)
├── .env.example                 # All env vars documented
└── PLAN.md                      # Original project plan
```

## External APIs

- **Open Food Facts v2**: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json` — 100 req/min products, 10 req/min search. Requires custom User-Agent header. Use `mx.openfoodfacts.org` for Mexico-specific queries.
- **USDA FoodData Central**: `GET https://api.nal.usda.gov/fdc/v1/foods/search` — 1,000 req/hour. API key required. NO native barcode lookup (text search only).
- **FatSecret Platform API**: `GET https://platform.fatsecret.com/rest/food/barcode/find-by-id/v1` — OAuth 1.0a auth. 90%+ barcode success rate, 2.3M+ foods. Free Premier tier for startups.
- **Lookup order**: Local DB cache → Open Food Facts → USDA FDC → FatSecret → Manual entry
- **Caching**: Products cached in local DB, TTL 7-14 days, cache-aside pattern

## Conventions

- Pydantic v2 for all request/response schemas
- SQLAlchemy 2.0 async style with AsyncSession
- All API endpoints versioned under /api/v1/
- Shared httpx.AsyncClient (not per-request) for external API calls
- `'use client'` directive only where needed (scanner, charts, interactive forms)
- html5-qrcode must use `next/dynamic` with `ssr: false` (accesses window/navigator)
- All user-facing strings should support Spanish localization
- Mock external APIs in tests (pytest-httpx for backend, vi.mock for frontend)
- Cache product lookups in PostgreSQL (TTL 7-14 days)
- Frontend design skill at `.claude/skills/frontend-design.md` — use for all UI work

## Known Limitations

- **iOS PWA camera**: WebKit bug #185448 breaks camera in standalone PWA mode. Do NOT set `apple-mobile-web-app-capable` meta tag. Provide manual barcode entry as first-class feature.
- **html5-qrcode**: v2.3.8 stalled since 2023 but functional. Monitor for replacement.
- **HTTPS for camera**: Camera API requires secure context. Localhost exempt on desktop. Use mkcert/ngrok for mobile testing.
- **USDA barcode gap**: No barcode endpoint; text-search product name. Use as fallback only.
- **FatSecret free tier**: Requires attribution. LATAM coverage limited on free tier but barcode DB is global.

## Database

PostgreSQL 16 with 6 tables: users, products (barcode-indexed cache), meals, meal_items, daily_nutrition (denormalized summary), nutrition_goals. Full schema in PLAN.md.

## Testing

- **Backend**: `uv run pytest` — pytest + pytest-httpx for mocking OFF/USDA/FatSecret calls, pytest-asyncio for async endpoints
- **Frontend**: `pnpm test` — vitest + @testing-library/react + jsdom environment
- **Camera tests**: Mock html5-qrcode module entirely via `vi.mock()`, mock `navigator.mediaDevices.getUserMedia`
- **Integration**: Docker Compose with test PostgreSQL instance
