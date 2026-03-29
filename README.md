# Nutrition Tracker with Barcode Scanner

[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![Next.js 14](https://img.shields.io/badge/Next.js-14+-black.svg)](https://nextjs.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.104+-009688.svg)](https://fastapi.tiangolo.com/)
[![PostgreSQL 16](https://img.shields.io/badge/PostgreSQL-16-336791.svg)](https://www.postgresql.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3+-3178C6.svg)](https://www.typescriptlang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Mobile-first nutrition tracking web app with real-time barcode scanning. Scan food products with your device camera, log meals by type (breakfast, lunch, dinner, snacks), track macros (calories, protein, carbs, fat, fiber), and visualize daily and weekly nutrition trends. Built for Spanish-speaking Latin American users with multi-source food database integration.

**Live:** [nutrition.armandointeligencia.com](https://nutrition.armandointeligencia.com)

---

## Features

- **Barcode scanning** via device camera (EAN-13, UPC-A, Code-128)
- **Manual barcode entry** fallback for iOS PWA and camera-denied scenarios
- **Cascading product lookup**: Open Food Facts → USDA FDC → FatSecret → manual entry
- **Meal logging** with types: breakfast, lunch, dinner, snacks
- **Macro tracking**: calories, protein, carbs, fat, fiber per meal and daily totals
- **Customizable goals** for daily calorie and macro targets
- **Daily/weekly visualizations** with Recharts (donut charts, trend lines, stacked bars)
- **Product caching** in local database for instant repeat lookups
- **PWA support** with offline meal logging and background sync
- **Mobile-first** responsive design optimized for one-handed use

---

## Architecture

```
Mobile Browser (Camera)
       │
   html5-qrcode (barcode decode)
       │
   Next.js Frontend (App Router)
       │
   FastAPI Backend (/api/v1/)
       │
   ┌───┴────────────────────────┐
   │   Product Lookup Service   │
   │                            │
   │   1. Local DB cache        │
   │   2. Open Food Facts v2    │
   │   3. USDA FoodData Central │
   │   4. FatSecret Platform    │
   │   5. Manual entry          │
   └────────────────────────────┘
       │
   PostgreSQL 16
```

---

## Barcode Scanning Technical Approach

The app uses [html5-qrcode](https://github.com/mebjas/html5-qrcode) (v2.3.8) for in-browser barcode scanning. This library provides cross-platform camera access via the `getUserMedia` API and supports all common food barcode formats: EAN-13, UPC-A, and Code-128.

**Browser compatibility:**
- **Desktop Chrome/Firefox/Safari**: Full camera scanning support
- **Android Chrome**: Full support with rear camera auto-selection
- **iOS Safari (browser)**: Works when opened directly in Safari
- **iOS PWA (home screen)**: Camera broken due to [WebKit bug #185448](https://bugs.webkit.org/show_bug.cgi?id=185448) — falls back to manual barcode entry

**Camera access requires HTTPS** (except `localhost` on desktop). For local mobile testing, use [mkcert](https://github.com/FiloSottile/mkcert) for self-signed certificates or [ngrok](https://ngrok.com/) to create an HTTPS tunnel.

**Fallback UX**: When camera is unavailable or permission is denied, the app displays a manual barcode entry field with numeric input. This is a first-class feature, not a hidden fallback — especially important for iOS PWA users.

---

## API Integration

The backend uses a cascading lookup strategy to maximize product coverage while minimizing API calls:

| # | Source | Endpoint | Rate Limit | Coverage | Use Case |
|---|--------|----------|------------|----------|----------|
| 1 | Local DB | PostgreSQL cache | Unlimited | Previously scanned | Instant lookup (TTL 7-14 days) |
| 2 | Open Food Facts v2 | `/api/v2/product/{barcode}` | 100 req/min | 4M+ products, strong LATAM | Primary lookup |
| 3 | USDA FoodData Central | `/fdc/v1/foods/search` | 1,000 req/hr | Detailed US nutrition | Text search fallback |
| 4 | FatSecret Platform | `/rest/food/barcode/find-by-id/v1` | Per plan | 2.3M+ foods, 90%+ barcode hit | Barcode fallback |
| 5 | Manual Entry | User form | N/A | Any product | Last resort |

**Lookup flow**: On barcode scan, the backend checks sources in order. The first successful match is cached locally and returned. If all APIs miss, the user is prompted to enter nutrition data manually. Manual entries are stored locally and available for future lookups.

**Caching**: Products are cached in PostgreSQL with a 7-14 day TTL using a cache-aside pattern. Frequently scanned products resolve instantly without external API calls.

---

## Quick Start

### Prerequisites

- Python 3.12+ (with [uv](https://docs.astral.sh/uv/))
- Node.js 20+ (with [pnpm](https://pnpm.io/))
- PostgreSQL 16 (or Docker Desktop)

### Backend

```bash
cd backend
uv sync
cp ../.env.example ../.env        # Edit with your API keys
uv run alembic upgrade head       # Run database migrations
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
cp .env.example .env              # Edit with your credentials
docker compose up -d
# Frontend: http://localhost:3000
# Backend:  http://localhost:8001
# API docs: http://localhost:8001/docs
```

---

## Mobile Testing (Camera Access)

Camera access requires HTTPS on mobile devices. Two approaches for local development:

### Option 1: mkcert (local HTTPS certificates)

```bash
# Install mkcert (macOS)
brew install mkcert nss
mkcert -install

# Generate certificates
mkcert localhost 127.0.0.1 ::1

# Start frontend with HTTPS
cd frontend && pnpm dev:https
# Access at https://localhost:3000
```

### Option 2: ngrok / Cloudflare Tunnel

```bash
# ngrok
ngrok http 3000
# Opens https://xxxx.ngrok.io — open on mobile device

# Cloudflare Tunnel (free, no account)
cloudflared tunnel --url http://localhost:3000
# Opens https://xxxx.trycloudflare.com
```

---

## Project Structure

```
03-Nutrition-Tracker/
├── frontend/                    # Next.js 14+ (App Router)
│   ├── app/                     # Pages and layouts
│   │   ├── dashboard/           # Daily summary, macro charts
│   │   ├── scan/                # Barcode scanner + manual entry
│   │   ├── meals/               # Meal logging and history
│   │   └── goals/               # Nutrition goal settings
│   ├── components/
│   │   ├── scanner/             # BarcodeScanner, ManualEntry
│   │   ├── meals/               # MealCard, MealItemRow
│   │   ├── charts/              # MacroPieChart, CalorieTrendChart
│   │   └── ui/                  # Shared UI components
│   ├── lib/                     # API client, types, utilities
│   └── public/                  # PWA manifest, icons
├── backend/                     # FastAPI
│   ├── app/
│   │   ├── api/v1/              # Route handlers
│   │   ├── models/              # SQLAlchemy models
│   │   ├── schemas/             # Pydantic v2 schemas
│   │   ├── services/            # Product lookup, nutrition calc
│   │   └── core/                # Config, database, deps
│   ├── alembic/                 # Database migrations
│   └── tests/                   # pytest test suite
├── docker-compose.yml           # Development stack
├── docker-compose.prod.yml      # Production (Traefik + HTTPS)
├── .env.example                 # Environment variables template
└── PLAN.md                      # Detailed project plan
```

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/products/search?barcode=...` | Lookup product by barcode (cascading sources) |
| `POST` | `/api/v1/products` | Create manual product entry |
| `POST` | `/api/v1/meals` | Create new meal |
| `POST` | `/api/v1/meals/{meal_id}/items` | Add food item to meal |
| `GET` | `/api/v1/meals/{date}` | Get all meals for a date |
| `DELETE` | `/api/v1/meals/{meal_id}/items/{item_id}` | Remove food from meal |
| `GET` | `/api/v1/nutrition/daily/{date}` | Daily nutrition summary |
| `GET` | `/api/v1/nutrition/weekly?start_date=...&end_date=...` | Weekly nutrition data |
| `GET` | `/api/v1/nutrition/goals` | Get nutrition goals |
| `PUT` | `/api/v1/nutrition/goals` | Update daily nutrition goals |
| `GET` | `/health` | Health check |

Full interactive docs available at `/docs` (Swagger UI) when the backend is running.

---

## Testing

### Backend

```bash
cd backend
uv run pytest tests/ -v                    # All tests
uv run pytest tests/ -v --cov=app          # With coverage report
uv run pytest tests/test_products.py -v    # Product lookup tests only
```

Tests mock external API calls using `pytest-httpx` — no real API keys needed for testing. Covers:
- Product lookup with mocked Open Food Facts, USDA, and FatSecret responses
- Meal CRUD operations
- Daily/weekly nutrition calculation
- Error handling (API timeouts, missing products, rate limits)

### Frontend

```bash
cd frontend
pnpm test                     # All tests
pnpm test -- --coverage       # With coverage
```

Tests mock camera access (`getUserMedia`) and the html5-qrcode library. Covers:
- Barcode scanner component (camera permission flow, scan detection, cleanup)
- Manual barcode entry fallback
- Nutrition chart rendering
- Meal logging UI interactions

---

## Deployment

Production deployment uses Docker Compose behind Traefik reverse proxy with automatic Let's Encrypt HTTPS:

```bash
# On VPS
docker compose -f docker-compose.prod.yml up -d
```

Services:
- **Frontend**: `nutrition.armandointeligencia.com` (Next.js standalone, port 3000)
- **Backend**: `api.nutrition.armandointeligencia.com` (FastAPI + Uvicorn, port 8001)
- **Database**: PostgreSQL 16 with persistent volume
- **Reverse Proxy**: Traefik v3 with auto-HTTPS via Let's Encrypt

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Next.js 14+, TypeScript, TailwindCSS, html5-qrcode, Recharts |
| Backend | FastAPI, SQLAlchemy 2.0, Alembic, httpx, Python 3.12+ |
| Database | PostgreSQL 16 |
| APIs | Open Food Facts v2, USDA FoodData Central, FatSecret Platform |
| PWA | Serwist, IndexedDB, Background Sync |
| Deployment | Docker Compose, Traefik v3, Let's Encrypt |
| Testing | pytest, pytest-httpx, vitest, Testing Library |
| Package Managers | uv (Python), pnpm (Node.js) |

---

## License

MIT
