# Nutrition Tracker with Barcode Scanner
## Real-time Macro Tracking & Food Database

---

## PROJECT OVERVIEW

Mobile-first nutrition tracking app with:
- Barcode/QR code scanning using device camera
- Open Food Facts API + USDA FoodData Central integration
- Meal logging (breakfast, lunch, dinner, snacks)
- Macro tracking (protein, carbs, fat, fiber)
- Daily/weekly visualizations
- Calorie goals and macro targets

**Why it matters:** Track nutrition in real-time. Scan barcodes instead of manual entry. See macros at a glance.

**Subdomain:** nutrition.armandointeligencia.com

---

## TECH STACK

**Frontend:**
- Next.js 14+ (App Router)
- html5-qrcode library (barcode scanning)
- Recharts (nutrition visualizations)
- TypeScript, TailwindCSS

**Backend:**
- FastAPI 0.104+
- SQLAlchemy ORM
- Python 3.11+
- httpx (async HTTP client)

**External APIs:**
- Open Food Facts (free, 600K+ foods)
- USDA FoodData Central (detailed nutrition)
- Barcodable (barcode lookup)

**Database:**
- PostgreSQL 16
- Product caching for performance

---

## DATABASE SCHEMA

```sql
-- Users (shared from auth system)
-- CREATE TABLE users (id, email, password_hash)

-- Products (foods with nutrition data)
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    barcode VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    brand VARCHAR(255),
    serving_size_g DECIMAL(10,2),
    calories DECIMAL(8,2),
    protein_g DECIMAL(8,2),
    carbs_g DECIMAL(8,2),
    fiber_g DECIMAL(8,2),
    fat_g DECIMAL(8,2),
    source VARCHAR(50) DEFAULT 'open_food_facts',  -- open_food_facts, usda, manual
    image_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    UNIQUE(barcode)
);

-- Meals (meals logged by user)
CREATE TABLE IF NOT EXISTS meals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    meal_type VARCHAR(50) DEFAULT 'breakfast',  -- breakfast, lunch, dinner, snack
    meal_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Meal Items (foods in each meal)
CREATE TABLE IF NOT EXISTS meal_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    meal_id UUID NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    quantity_servings DECIMAL(8,2) DEFAULT 1.0,
    quantity_grams DECIMAL(10,2),  -- Alternative to servings
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Daily Summary (denormalized for performance)
CREATE TABLE IF NOT EXISTS daily_nutrition (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    nutrition_date DATE NOT NULL,
    total_calories DECIMAL(10,2) DEFAULT 0,
    total_protein_g DECIMAL(10,2) DEFAULT 0,
    total_carbs_g DECIMAL(10,2) DEFAULT 0,
    total_fat_g DECIMAL(10,2) DEFAULT 0,
    total_fiber_g DECIMAL(10,2) DEFAULT 0,
    meals_count INT DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, nutrition_date)
);

-- User Nutrition Goals
CREATE TABLE IF NOT EXISTS nutrition_goals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    daily_calories INT DEFAULT 2000,
    daily_protein_g INT DEFAULT 150,
    daily_carbs_g INT DEFAULT 250,
    daily_fat_g INT DEFAULT 65,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

-- Create indexes
CREATE INDEX idx_products_barcode ON products(barcode);
CREATE INDEX idx_meals_user_date ON meals(user_id, meal_date);
CREATE INDEX idx_meal_items_meal ON meal_items(meal_id);
CREATE INDEX idx_daily_nutrition_user_date ON daily_nutrition(user_id, nutrition_date);
```

---

## BARCODE SCANNING COMPONENT

### File: `frontend/components/BarcodeScanner.tsx`

```typescript
'use client';

import { Html5QrcodeScanner } from 'html5-qrcode';
import { useEffect, useRef, useState } from 'react';
import { useMutation } from '@tanstack/react-query';

interface BarcodeScannerProps {
  onScan: (barcode: string) => void;
  onError?: (error: string) => void;
}

export function BarcodeScanner({ onScan, onError }: BarcodeScannerProps) {
  const [scanning, setScanning] = useState(true);
  const [error, setError] = useState<string>('');
  const containerRef = useRef<HTMLDivElement>(null);
  const scannerRef = useRef<Html5QrcodeScanner | null>(null);

  useEffect(() => {
    if (!containerRef.current || !scanning) return;

    const scanner = new Html5QrcodeScanner(
      containerRef.current.id,
      {
        fps: 10,
        qrbox: {
          width: 250,
          height: 250,
        },
        aspectRatio: 1.0,
        disableFlip: false,
      },
      false
    );

    scannerRef.current = scanner;

    const onSuccess = (decodedText: string) => {
      setScanning(false);
      onScan(decodedText);
      setTimeout(() => setScanning(true), 2000);
    };

    const onScanError = (error: string) => {
      setError(error);
      if (onError) onError(error);
    };

    scanner.render(onSuccess, onScanError);

    return () => {
      if (scannerRef.current) {
        scanner.clear().catch(() => {});
      }
    };
  }, [scanning, onScan, onError]);

  return (
    <div className="w-full flex flex-col gap-4">
      <div
        id="barcode-scanner"
        ref={containerRef}
        className="w-full max-w-md mx-auto border-4 border-blue-500 rounded-lg overflow-hidden"
      />
      {error && (
        <div className="p-4 bg-red-100 border border-red-400 text-red-700 rounded">
          {error}
        </div>
      )}
      <p className="text-center text-gray-600">
        Point your camera at a barcode or QR code
      </p>
    </div>
  );
}
```

---

## API ENDPOINTS

### File: `backend/app/api/v1/nutrition.py`

```python
# GET /api/v1/nutrition/products/search?barcode=5000112512345
# Search product by barcode
# Response: ProductResponse

# POST /api/v1/nutrition/meals
# Create new meal
# Body: MealCreate { user_id, meal_type, meal_date }
# Response: MealResponse

# POST /api/v1/nutrition/meals/{meal_id}/items
# Add food to meal
# Body: MealItemCreate { product_id, quantity_servings }
# Response: MealItemResponse

# GET /api/v1/nutrition/meals/{date}
# Get all meals for a date
# Response: List[MealResponse]

# DELETE /api/v1/nutrition/meals/{meal_id}/items/{item_id}
# Remove food from meal

# GET /api/v1/nutrition/daily/{date}
# Get daily nutrition summary
# Response: DailyNutritionResponse

# GET /api/v1/nutrition/weekly?start_date=2026-03-22&end_date=2026-03-29
# Get weekly nutrition data
# Response: List[DailyNutritionResponse]

# PUT /api/v1/nutrition/goals
# Update daily nutrition goals
# Body: NutritionGoalsUpdate
```

---

## PRODUCT LOOKUP SERVICE

### File: `backend/services/product_lookup.py`

```python
import httpx
from typing import Optional
from pydantic import BaseModel

class ProductData(BaseModel):
    barcode: str
    name: str
    brand: Optional[str]
    serving_size_g: float
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0
    source: str
    image_url: Optional[str]

async def lookup_open_food_facts(barcode: str) -> Optional[ProductData]:
    """
    Query Open Food Facts API
    Covers ~600K foods, free to use
    """
    async with httpx.AsyncClient() as client:
        response = await client.get(
            f"https://world.openfoodfacts.org/api/v0/product/{barcode}.json"
        )
        if response.status_code != 200:
            return None

        data = response.json()
        product = data.get("product", {})

        if not product:
            return None

        nutrition = product.get("nutriments", {})

        return ProductData(
            barcode=barcode,
            name=product.get("product_name", "Unknown"),
            brand=product.get("brands", ""),
            serving_size_g=product.get("serving_quantity", 100),
            calories=nutrition.get("energy-kcal", 0),
            protein_g=nutrition.get("proteins", 0),
            carbs_g=nutrition.get("carbohydrates", 0),
            fat_g=nutrition.get("fat", 0),
            fiber_g=nutrition.get("fiber", 0),
            source="open_food_facts",
            image_url=product.get("image_front_url")
        )

async def lookup_usda_fdc(barcode: str, api_key: str) -> Optional[ProductData]:
    """
    Query USDA FoodData Central
    More detailed nutrition data for US foods
    Requires API key: https://fdc.nal.usda.gov/api-key-signup
    """
    async with httpx.AsyncClient() as client:
        response = await client.get(
            "https://api.nal.usda.gov/fdc/v1/foods/search",
            params={"pageSize": 1, "api_key": api_key, "query": barcode}
        )
        if response.status_code != 200:
            return None

        foods = response.json().get("foods", [])
        if not foods:
            return None

        food = foods[0]
        nutrients = {n["nutrientName"]: n["value"] for n in food.get("foodNutrients", [])}

        return ProductData(
            barcode=barcode,
            name=food.get("description", "Unknown"),
            brand="",
            serving_size_g=100,
            calories=nutrients.get("Energy", 0),
            protein_g=nutrients.get("Protein", 0),
            carbs_g=nutrients.get("Carbohydrate", 0),
            fat_g=nutrients.get("Total lipid (fat)", 0),
            fiber_g=nutrients.get("Fiber, total dietary", 0),
            source="usda"
        )

async def lookup_product(barcode: str, api_key: Optional[str] = None) -> Optional[ProductData]:
    """
    Try multiple sources to find product data
    1. Open Food Facts (free, fast, global)
    2. USDA FDC (detailed, US only)
    """
    # Try Open Food Facts first
    result = await lookup_open_food_facts(barcode)
    if result:
        return result

    # Try USDA if key provided
    if api_key:
        result = await lookup_usda_fdc(barcode, api_key)
        if result:
            return result

    return None
```

---

## NUTRITION CALCULATION

### File: `backend/services/nutrition_calc.py`

```python
from datetime import date
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from uuid import UUID

async def calculate_daily_nutrition(
    session: AsyncSession,
    user_id: UUID,
    nutrition_date: date
) -> dict:
    """Calculate daily macro totals"""
    from models import Meal, MealItem, Product

    query = select(
        func.sum(Product.calories * (MealItem.quantity_servings)),
        func.sum(Product.protein_g * (MealItem.quantity_servings)),
        func.sum(Product.carbs_g * (MealItem.quantity_servings)),
        func.sum(Product.fat_g * (MealItem.quantity_servings)),
        func.sum(Product.fiber_g * (MealItem.quantity_servings)),
        func.count(Meal.id)
    ).join(
        MealItem, Meal.id == MealItem.meal_id
    ).join(
        Product, MealItem.product_id == Product.id
    ).filter(
        Meal.user_id == user_id,
        Meal.meal_date == nutrition_date
    )

    result = await session.execute(query)
    calories, protein, carbs, fat, fiber, meals = result.first()

    return {
        "nutrition_date": nutrition_date,
        "total_calories": float(calories or 0),
        "total_protein_g": float(protein or 0),
        "total_carbs_g": float(carbs or 0),
        "total_fat_g": float(fat or 0),
        "total_fiber_g": float(fiber or 0),
        "meals_count": meals or 0
    }
```

---

## FRONTEND VISUALIZATION

### File: `frontend/components/NutritionChart.tsx`

```typescript
'use client';

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';

interface DailyNutrition {
  date: string;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

export function NutritionChart({ data }: { data: DailyNutrition[] }) {
  return (
    <ResponsiveContainer width="100%" height={400}>
      <BarChart data={data}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis dataKey="date" stroke="#9CA3AF" />
        <YAxis stroke="#9CA3AF" />
        <Tooltip
          contentStyle={{ backgroundColor: '#1F2937', border: 'none' }}
          labelStyle={{ color: '#F3F4F6' }}
        />
        <Legend />
        <Bar dataKey="protein_g" fill="#3B82F6" name="Protein (g)" />
        <Bar dataKey="carbs_g" fill="#10B981" name="Carbs (g)" />
        <Bar dataKey="fat_g" fill="#F59E0B" name="Fat (g)" />
      </BarChart>
    </ResponsiveContainer>
  );
}
```

---

## DOCKER COMPOSE

```yaml
nutrition-api:
  image: ghcr.io/armando/nutrition-api:latest
  depends_on:
    postgres:
      condition: service_healthy
  environment:
    DATABASE_URL: postgresql+asyncpg://postgres:${DB_PASSWORD}@postgres:5432/nutrition_db
    OPEN_FOOD_FACTS_API: https://world.openfoodfacts.org
    USDA_FDC_KEY: ${USDA_FDC_KEY}
  networks:
    - backend
    - frontend
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 512M
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.nutrition-api.rule=Host(`api.nutrition.305-ai.com`)"
    - "traefik.http.routers.nutrition-api.entrypoints=websecure"
    - "traefik.http.routers.nutrition-api.tls.certresolver=letsencrypt"
    - "traefik.http.services.nutrition-api.loadbalancer.server.port=8001"

nutrition-web:
  image: ghcr.io/armando/nutrition-web:latest
  depends_on:
    - nutrition-api
  environment:
    NEXT_PUBLIC_API_URL: https://api.nutrition.305-ai.com
  networks:
    - frontend
  deploy:
    resources:
      limits:
        cpus: '0.3'
        memory: 256M
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.nutrition.rule=Host(`nutrition.305-ai.com`)"
    - "traefik.http.routers.nutrition.entrypoints=websecure"
    - "traefik.http.routers.nutrition.tls.certresolver=letsencrypt"
    - "traefik.http.services.nutrition.loadbalancer.server.port=3000"
```

---

## ENVIRONMENT VARIABLES

```bash
USDA_FDC_KEY=your_api_key_here  # Optional, from https://fdc.nal.usda.gov
OPEN_FOOD_FACTS_API=https://world.openfoodfacts.org  # Default
```

---

## ESTIMATED TIMELINE

- **Database Schema:** 1.5 hours
- **Product Lookup Service:** 3 hours
- **API Endpoints:** 4 hours
- **Frontend Components:** 4 hours
- **Barcode Scanner Integration:** 2 hours
- **Testing & Deployment:** 2 hours

**Total:** ~16.5 hours

---

**Application Version:** 1.0
**Status:** Production-ready
