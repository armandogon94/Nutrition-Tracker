# Health & Fitness App — Nutrition + Meal Planning + Workout Tracker
## Complete Health Platform: Nutrition Tracking, Meal Planning, Workout Programming & Gym Logging

---

## PROJECT OVERVIEW

Complete health and fitness platform offering:

**Nutrition Module:**
- Barcode/QR code scanning using device camera
- Photo recognition for food identification and portion estimation
- Open Food Facts API + USDA FoodData Central integration
- Meal logging (breakfast, lunch, dinner, snacks)
- Macro tracking (protein, carbs, fat, fiber)
- Daily/weekly visualizations
- Calorie goals and macro targets

**Meal Planning Module:**
- Weekly meal planner with 7-day schedule (breakfast/lunch/dinner/snacks)
- Auto-generated shopping lists grouped by category with aggregated quantities
- TDEE calculator (Mifflin-St Jeor equation) based on user stats
- Macro goal presets (Fat Loss, Maintenance, Lean Bulk, Muscle Gain)
- Custom macro target setting

**Workout Tracker Module:**
- 10+ pre-built workout programs (PPL, Upper/Lower, Full Body, 5/3/1, etc.)
- Exercise database (200+ exercises with video links and muscle group mapping)
- Gym session logging with sets/reps/weight tracking
- Personal record (PR) tracking per exercise
- Progressive overload visualization (weight/rep trends)
- Smart rest timer with exercise previews
- Workout history calendar and volume tracking by muscle group

**Why it matters:** One comprehensive platform for complete health management. Track nutrition from barcode scans, plan meals for the week, generate shopping lists, follow structured workout programs, and log gym sessions in real-time with built-in rest timers and form guidance.

**Subdomain:** fit.armandointeligencia.com

---

## TECH STACK

**Frontend:**
- Next.js 14+ (App Router)
- html5-qrcode library (barcode scanning)
- Claude Vision API (photo food recognition)
- Recharts (nutrition & workout visualizations)
- React DnD (drag-and-drop meal planning)
- TypeScript, TailwindCSS

**Backend:**
- FastAPI 0.104+
- SQLAlchemy ORM
- Python 3.11+
- httpx (async HTTP client)
- APScheduler (background tasks for macro calculations)

**External APIs:**
- Open Food Facts (free, 600K+ foods)
- USDA FoodData Central (detailed nutrition)
- Claude Vision API (food recognition from photos)
- YouTube Data API (exercise video links)

**Database:**
- PostgreSQL 16
- Product & exercise data caching
- Denormalized nutrition summaries for performance

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
    - "traefik.http.routers.nutrition-api.rule=Host(`api.fit.armandointeligencia.com`)"
    - "traefik.http.routers.nutrition-api.entrypoints=websecure"
    - "traefik.http.routers.nutrition-api.tls.certresolver=letsencrypt"
    - "traefik.http.services.nutrition-api.loadbalancer.server.port=8000"

nutrition-web:
  image: ghcr.io/armando/nutrition-web:latest
  depends_on:
    - nutrition-api
  environment:
    NEXT_PUBLIC_API_URL: https://api.fit.armandointeligencia.com
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
    - "traefik.http.routers.nutrition.rule=Host(`fit.armandointeligencia.com`)"
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

## MEAL PLANNING MODULE

### Weekly Meal Planner

**File:** `frontend/components/MealPlanner.tsx`

- Interactive 7-day meal planner with drag-and-drop interface
- Each day has 4 sections: Breakfast, Lunch, Dinner, Snacks
- Users select foods from product database or recent meals
- Real-time macro calculation as foods are added to each meal
- Save as templates for easy reuse
- Sync created meals to actual meal logging section

### Shopping List Generator

**File:** `backend/services/shopping_list.py`

```python
async def generate_shopping_list(
    session: AsyncSession,
    meal_plan_id: UUID
) -> ShoppingListResponse:
    """
    Auto-generate shopping list from meal plan
    Groups items by category (produce, dairy, proteins, grains, etc.)
    Aggregates quantities across all meals in the plan
    """
    # Query all food items in the meal plan
    # Extract ingredients from each product
    # Group by category
    # Aggregate quantities (sum grams/servings)
    # Return with checkboxes for marking off items
```

**Shopping List Categories:**
- Produce (vegetables, fruits)
- Dairy & Eggs
- Proteins (meat, fish, poultry, plant-based)
- Grains & Bread
- Pantry (oils, spices, sauces)
- Frozen Foods
- Beverages

### TDEE Calculator & Macro Goal System

**File:** `backend/services/tdee_calculator.py`

```python
from enum import Enum
from pydantic import BaseModel

class ActivityLevel(str, Enum):
    SEDENTARY = "sedentary"  # 1.2 (little/no exercise)
    LIGHT = "light"  # 1.375 (1-3 days/week)
    MODERATE = "moderate"  # 1.55 (3-5 days/week)
    ACTIVE = "active"  # 1.725 (6-7 days/week)
    VERY_ACTIVE = "very_active"  # 1.9 (intense training 2x/day)

class GoalPreset(str, Enum):
    FAT_LOSS = "fat_loss"  # -500 cal deficit
    MAINTENANCE = "maintenance"  # TDEE
    LEAN_BULK = "lean_bulk"  # +250 cal surplus
    MUSCLE_GAIN = "muscle_gain"  # +500 cal surplus

class UserProfile(BaseModel):
    weight_kg: float
    height_cm: float
    age: int
    sex: str  # "male", "female", "other"
    activity_level: ActivityLevel

def calculate_bmr(profile: UserProfile) -> float:
    """
    Mifflin-St Jeor Equation
    BMR = 10 × weight(kg) + 6.25 × height(cm) - 5 × age + s
    s = +5 for male, -161 for female
    """
    sex_factor = 5 if profile.sex.lower() == "male" else -161
    bmr = (10 * profile.weight_kg +
           6.25 * profile.height_cm -
           5 * profile.age +
           sex_factor)
    return bmr

def calculate_tdee(bmr: float, activity_level: ActivityLevel) -> float:
    """TDEE = BMR × activity multiplier"""
    multipliers = {
        ActivityLevel.SEDENTARY: 1.2,
        ActivityLevel.LIGHT: 1.375,
        ActivityLevel.MODERATE: 1.55,
        ActivityLevel.ACTIVE: 1.725,
        ActivityLevel.VERY_ACTIVE: 1.9
    }
    return bmr * multipliers[activity_level]

def calculate_macros(
    tdee: float,
    goal: GoalPreset,
    weight_kg: float
) -> dict:
    """
    Calculate daily macro targets based on goal
    Protein: 2g per kg bodyweight (adjustable)
    Fat: 25% of calories
    Carbs: Remaining calories
    """
    goal_calories = {
        GoalPreset.FAT_LOSS: tdee - 500,
        GoalPreset.MAINTENANCE: tdee,
        GoalPreset.LEAN_BULK: tdee + 250,
        GoalPreset.MUSCLE_GAIN: tdee + 500
    }

    target_cals = goal_calories[goal]
    protein_g = weight_kg * 2.0  # 2g per kg
    fat_g = (target_cals * 0.25) / 9  # 25% of cals, 9 cal/g
    carbs_g = (target_cals - (protein_g * 4) - (fat_g * 9)) / 4  # 4 cal/g

    return {
        "daily_calories": int(target_cals),
        "protein_g": int(protein_g),
        "fat_g": int(fat_g),
        "carbs_g": int(carbs_g),
        "goal": goal.value
    }
```

### Food Input Methods (Expanded)

**Photo Food Recognition:**

**File:** `backend/services/food_recognition.py`

```python
import anthropic
from base64 import b64encode

async def recognize_food_from_photo(
    image_path: str,
    client: anthropic.Anthropic
) -> dict:
    """
    Use Claude Vision API to identify food and estimate portions
    Returns: food_name, estimated_serving_size_g, confidence
    """
    with open(image_path, "rb") as f:
        image_data = b64encode(f.read()).decode('utf-8')

    message = client.messages.create(
        model="claude-3-5-sonnet-20241022",
        max_tokens=1024,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image_data,
                        },
                    },
                    {
                        "type": "text",
                        "text": """Analyze this food image and provide:
1. Food name/description (be specific - e.g., "grilled chicken breast" not just "chicken")
2. Estimated serving size in grams (consider the portion shown)
3. Confidence level (high/medium/low)

Respond in JSON: {"food": "...", "grams": 150, "confidence": "high"}"""
                    }
                ],
            }
        ],
    )

    # Parse response and return
    return json.loads(message.content[0].text)
```

---

## WORKOUT TRACKER MODULE

### Workout Program Types

**File:** `backend/models/workout_programs.py`

Pre-built programs with detailed educational UI descriptions:

1. **Push/Pull/Legs (PPL)** — 6 days/week
   - Description: High volume split training each muscle group twice weekly. Ideal for advanced lifters seeking maximum hypertrophy. Expect 60-90 minute sessions.
   - Expected Results: Significant muscle growth and strength gains with consistent nutrition.

2. **Upper/Lower Split** — 4 days/week
   - Description: Balanced approach hitting upper body twice and lower body twice per week. Moderate volume, excellent for strength and size development. Great for busy schedules.
   - Expected Results: Steady muscle and strength gains with good recovery.

3. **Full Body** — 3 days/week
   - Description: Efficient program hitting all muscle groups each session. Perfect for beginners or those training 3 days per week. Compound movement focused (squats, bench, deadlifts).
   - Expected Results: Foundational strength development and muscle building with minimal time commitment.

4. **Bro Split (IBB)** — 5 days/week
   - Description: One muscle group per day (Chest, Back, Legs, Shoulders, Arms). High frequency for isolation work. Requires consistent training schedule.
   - Expected Results: Detailed muscle development with higher risk of plateauing without progressive overload.

5. **PHUL (Power Hypertrophy Upper Lower)** — 4 days/week
   - Description: Two upper days (one power, one hypertrophy) + two lower days. Combines strength and size development.
   - Expected Results: Balanced gains in both strength and muscle mass.

6. **PHAT (Power Hypertrophy Adaptive Training)** — 5 days/week
   - Description: Advanced program cycling between power and hypertrophy phases. Requires experience with progressive overload.
   - Expected Results: Accelerated strength and hypertrophy gains for intermediate+ lifters.

7. **5/3/1 (Wendler)** — 4 days/week
   - Description: Periodized strength program based on main lifts (Squat, Bench, Deadlift, OHP). Progressive overload built into weekly cycles.
   - Expected Results: Consistent strength progression month over month. Ideal for strength-focused training.

8. **Starting Strength / StrongLifts 5x5** — 3 days/week
   - Description: Beginner program using 5 compound lifts per session. Perfect entry point for new lifters. Emphasizes form and progressive overload.
   - Expected Results: Rapid strength gains for first 8-12 weeks. Excellent foundation building.

9. **German Volume Training (GVT)** — 4 days/week
   - Description: 10 sets of 10 reps per exercise. High volume hypertrophy specialization. Intense but effective for muscle growth.
   - Expected Results: Significant muscle gain with moderate strength increase.

10. **Custom Program** — User Defined
    - Description: Build your own program by selecting exercises, sets, reps, and rest periods. Full control over training structure.

### Exercise Database

**File:** `backend/data/exercises.json` (seed data)

~200 exercises with:
- Exercise name (e.g., "Barbell Bench Press")
- Primary muscle group (chest, back, legs, shoulders, arms, core, etc.)
- Secondary muscles worked
- Equipment needed (barbell, dumbbell, machine, bodyweight, cable)
- Difficulty level (beginner, intermediate, advanced)
- Video tutorial URL (link to reputable YouTube channels like JeffNippard, AthleanX)
- Form cues / instructions

Example structure:
```json
{
  "id": "exercise_001",
  "name": "Barbell Back Squat",
  "primary_muscle": "legs",
  "secondary_muscles": ["glutes", "core", "back"],
  "equipment": ["barbell", "rack"],
  "difficulty": "intermediate",
  "video_url": "https://youtube.com/watch?v=...",
  "instructions": "Place bar across shoulders, squat to parallel or below, drive through heels"
}
```

### Gym Session Logging

**File:** `frontend/components/WorkoutLogger.tsx`

- Real-time set/rep/weight logging interface
- One exercise at a time with clear input fields
- Auto-calculate estimated 1RM based on entered weight/reps
- Mark sets as completed with checkmarks
- Log personal records (PRs) with date stamped
- Session notes (optional)
- Total session duration timer

### Rest Timer with Exercise Preview

**File:** `frontend/components/RestTimer.tsx`

```typescript
// Auto-suggest rest times based on exercise type:
// - Compound movements (squats, bench, deadlifts): 2-3 minutes
// - Isolation exercises (curls, leg press variations): 60-90 seconds
// - Core/calves: 30-60 seconds
// - User can adjust override

// Features:
// - Countdown timer (shows remaining seconds)
// - Sound + vibration alert when rest time is complete
// - During rest: Show preview of next set
//   - Exercise name
//   - Target reps
//   - Suggested weight based on last session
//   - Video preview thumbnail (one-click full video)
```

### Workout History & Analytics

**File:** `frontend/pages/workouts/history.tsx`

- Calendar view of completed workouts (color-coded by program)
- Volume per muscle group per week (chart)
- Total volume trend over time (bar chart)
- Exercises with most volume
- Longest time between sessions per muscle group
- Export workout history as CSV

---

## DATABASE SCHEMA ADDITIONS

```sql
-- User Profiles (extended from auth)
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    weight_kg DECIMAL(6,2) NOT NULL,
    height_cm DECIMAL(6,2) NOT NULL,
    age INT NOT NULL,
    sex VARCHAR(20) NOT NULL,  -- male, female, other
    activity_level VARCHAR(50) DEFAULT 'moderate',  -- sedentary, light, moderate, active, very_active
    goal_preset VARCHAR(50),  -- fat_loss, maintenance, lean_bulk, muscle_gain
    custom_daily_calories INT,
    custom_protein_g INT,
    custom_carbs_g INT,
    custom_fat_g INT,
    bmr DECIMAL(8,2),  -- Calculated BMR
    tdee DECIMAL(8,2),  -- Calculated TDEE
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

-- Meal Plans (weekly templates)
CREATE TABLE IF NOT EXISTS meal_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,  -- "Lean Bulk Week 1", "Summer Cut Plan", etc.
    week_start_date DATE NOT NULL,
    notes TEXT,
    is_template BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Meal Plan Items (foods in each day)
CREATE TABLE IF NOT EXISTS meal_plan_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    meal_plan_id UUID NOT NULL REFERENCES meal_plans(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    day_of_week INT NOT NULL,  -- 0-6 (Monday-Sunday)
    meal_type VARCHAR(50) NOT NULL,  -- breakfast, lunch, dinner, snack
    quantity_servings DECIMAL(8,2) DEFAULT 1.0,
    quantity_grams DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Shopping Lists (generated from meal plans)
CREATE TABLE IF NOT EXISTS shopping_lists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    meal_plan_id UUID REFERENCES meal_plans(id) ON DELETE SET NULL,
    name VARCHAR(255),
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

-- Shopping List Items
CREATE TABLE IF NOT EXISTS shopping_list_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shopping_list_id UUID NOT NULL REFERENCES shopping_lists(id) ON DELETE CASCADE,
    ingredient_name VARCHAR(255) NOT NULL,
    quantity DECIMAL(10,2) NOT NULL,
    unit VARCHAR(50),  -- grams, ml, pieces, etc.
    category VARCHAR(100),  -- produce, dairy, proteins, grains, pantry, frozen, beverages
    is_checked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Workout Programs (predefined and custom)
CREATE TABLE IF NOT EXISTS workout_programs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,  -- NULL for global presets
    name VARCHAR(255) NOT NULL,
    description TEXT,
    program_type VARCHAR(100),  -- ppl, upper_lower, full_body, bro_split, phul, phat, 531, stronglifts, gvt, custom
    days_per_week INT NOT NULL,
    difficulty VARCHAR(50),  -- beginner, intermediate, advanced
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Workout Program Days (structure of each program)
CREATE TABLE IF NOT EXISTS workout_program_days (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    program_id UUID NOT NULL REFERENCES workout_programs(id) ON DELETE CASCADE,
    day_number INT NOT NULL,  -- 1-6 or more
    day_name VARCHAR(100),  -- "Push", "Pull", "Legs", "Upper Power", etc.
    focus VARCHAR(255),  -- "Chest, Shoulders, Triceps", "Back, Biceps", etc.
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Workout Program Exercises (exercises in each day)
CREATE TABLE IF NOT EXISTS workout_program_exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    program_day_id UUID NOT NULL REFERENCES workout_program_days(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    set_count INT NOT NULL,  -- 3, 4, 5, 10, etc.
    rep_min INT,  -- 5, 6, 8, 10, etc.
    rep_max INT,
    rest_seconds INT,  -- auto-suggested rest time
    exercise_order INT NOT NULL,  -- Order in the workout (1, 2, 3, ...)
    notes TEXT,  -- Optional special instructions
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Exercise Database
CREATE TABLE IF NOT EXISTS exercises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    primary_muscle VARCHAR(100) NOT NULL,
    secondary_muscles VARCHAR(255),  -- comma-separated or JSON array in code
    equipment VARCHAR(255),  -- barbell, dumbbell, machine, bodyweight, cable, etc.
    difficulty VARCHAR(50),  -- beginner, intermediate, advanced
    video_url TEXT,
    instructions TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, equipment)
);

-- Workout Sessions (actual workouts logged)
CREATE TABLE IF NOT EXISTS workout_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    program_id UUID REFERENCES workout_programs(id) ON DELETE SET NULL,
    program_day_id UUID REFERENCES workout_program_days(id) ON DELETE SET NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    duration_minutes INT,  -- calculated from started_at to completed_at
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Workout Sets (individual sets logged in a session)
CREATE TABLE IF NOT EXISTS workout_sets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    set_number INT NOT NULL,
    reps INT NOT NULL,
    weight_kg DECIMAL(8,2),  -- NULL for bodyweight exercises
    is_pr BOOLEAN DEFAULT FALSE,  -- Marked as personal record
    completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Personal Records (PRs per user per exercise)
CREATE TABLE IF NOT EXISTS personal_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    exercise_id UUID NOT NULL REFERENCES exercises(id),
    max_weight_kg DECIMAL(8,2),
    max_reps_at_weight INT,
    achieved_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, exercise_id)
);

-- Create indexes for performance
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);
CREATE INDEX idx_meal_plans_user_date ON meal_plans(user_id, week_start_date);
CREATE INDEX idx_meal_plan_items_plan ON meal_plan_items(meal_plan_id);
CREATE INDEX idx_shopping_lists_user ON shopping_lists(user_id);
CREATE INDEX idx_workout_programs_user ON workout_programs(user_id);
CREATE INDEX idx_workout_sessions_user_date ON workout_sessions(user_id, started_at);
CREATE INDEX idx_workout_sets_session ON workout_sets(session_id);
CREATE INDEX idx_exercises_muscle ON exercises(primary_muscle);
CREATE INDEX idx_personal_records_user ON personal_records(user_id);
```

---

## NEW API ENDPOINTS

**Meal Planning Endpoints:**

```
POST /api/v1/meals/plans
- Create new weekly meal plan
- Body: { name, week_start_date, notes }

GET /api/v1/meals/plans/{plan_id}
- Get meal plan with all items

PUT /api/v1/meals/plans/{plan_id}
- Update meal plan

POST /api/v1/meals/plans/{plan_id}/items
- Add food to meal plan
- Body: { product_id, day_of_week, meal_type, quantity_servings }

DELETE /api/v1/meals/plans/{plan_id}/items/{item_id}
- Remove food from meal plan

GET /api/v1/meals/shopping-list/generate/{plan_id}
- Auto-generate shopping list from meal plan
- Returns grouped items by category with aggregated quantities

POST /api/v1/meals/shopping-lists
- Create manual shopping list

GET /api/v1/meals/shopping-lists/{list_id}
- Get shopping list items

PATCH /api/v1/meals/shopping-lists/{list_id}/items/{item_id}/check
- Mark item as checked/unchecked
```

**User Profile & TDEE Endpoints:**

```
POST /api/v1/profile
- Create/update user profile
- Body: { weight_kg, height_cm, age, sex, activity_level }
- Returns: Calculated BMR, TDEE, and current macro targets

GET /api/v1/profile/tdee
- Get current TDEE calculation

POST /api/v1/profile/goals
- Set macro goals (preset or custom)
- Body: { goal_preset: "fat_loss"|"maintenance"|"lean_bulk"|"muscle_gain" }
- OR
- Body: { custom_calories, custom_protein_g, custom_carbs_g, custom_fat_g }
```

**Workout Program Endpoints:**

```
GET /api/v1/workouts/programs
- List all available programs (global presets + user custom)

GET /api/v1/workouts/programs/{program_id}
- Get program with all days and exercises

POST /api/v1/workouts/programs
- Create custom program
- Body: { name, program_type, days_per_week, description }

GET /api/v1/workouts/programs/{program_id}/days/{day_id}
- Get exercises for a specific day

POST /api/v1/workouts/programs/{program_id}/start
- Start a workout session (log timestamp, select day)
- Returns: SessionID + exercise list for the day
```

**Gym Logging Endpoints:**

```
POST /api/v1/workouts/sessions
- Start new workout session
- Body: { program_id, program_day_id, started_at }
- Returns: { session_id }

POST /api/v1/workouts/sessions/{session_id}/sets
- Log a completed set
- Body: { exercise_id, set_number, reps, weight_kg, is_pr }

GET /api/v1/workouts/sessions/{session_id}
- Get active session details (exercise preview, rest suggestions)

PATCH /api/v1/workouts/sessions/{session_id}/complete
- Mark workout as completed
- Body: { completed_at, notes }

GET /api/v1/workouts/history?start_date=&end_date=
- Get workout history calendar

GET /api/v1/workouts/volume?period=week|month
- Get volume by muscle group
```

**Exercise Database Endpoints:**

```
GET /api/v1/exercises
- List all exercises (searchable, filterable by muscle group, equipment, difficulty)

GET /api/v1/exercises/{exercise_id}
- Get exercise details (video URL, form cues)

GET /api/v1/exercises/search?q=bench&muscle=chest
- Search exercises by name and muscle group
```

---

## NEW FRONTEND PAGES

```
/profile
- User profile setup (weight, height, age, sex, activity level)
- TDEE calculator with real-time updates
- Goal preset selector (Fat Loss, Maintenance, Lean Bulk, Muscle Gain)
- Custom macro input option
- Display calculated BMR, TDEE, and recommended daily macros

/meals/plan
- Interactive weekly meal planner (7-day view)
- Drag-and-drop to add foods to meals
- Real-time macro calculation for each day
- Save as template
- Load previous plans

/meals/shopping
- Generated shopping list from selected meal plan
- Grouped by category (produce, dairy, proteins, grains, pantry, frozen, beverages)
- Checkboxes to mark items as purchased
- Quantity and units clearly shown
- Export to text or PDF

/workouts
- Workout program selector with educational descriptions
- 10 programs + custom option
- Start workout button (loads program/day)
- User's active program display

/workouts/log
- Active workout session interface
- Current exercise details
- Set/rep/weight input with validation
- "Set Complete" button
- Rest timer (countdown with sound alert)
- Next set preview (exercise, target reps, suggested weight)
- Video preview link for current exercise
- Session notes field
- "End Workout" button

/workouts/history
- Calendar view of completed workouts
- Color-coded by program type
- Workout details modal (exercises, sets, weight progression)
- Volume chart by muscle group (weekly)
- Total volume trend over time
- Longest gap between muscle group sessions

/exercises
- Exercise database browser
- Filter by muscle group, equipment, difficulty
- Search by name
- Exercise details: Video link, form cues, difficulty rating
- Used-in programs indicator
```

---

## UPDATED DOCKER COMPOSE

```yaml
fit-api:
  image: ghcr.io/armando/fit-api:latest
  depends_on:
    postgres:
      condition: service_healthy
  environment:
    DATABASE_URL: postgresql+asyncpg://postgres:${DB_PASSWORD}@postgres:5432/fit_db
    OPEN_FOOD_FACTS_API: https://world.openfoodfacts.org
    USDA_FDC_KEY: ${USDA_FDC_KEY}
    CLAUDE_API_KEY: ${CLAUDE_API_KEY}
    YOUTUBE_API_KEY: ${YOUTUBE_API_KEY}
  networks:
    - backend
    - frontend
  deploy:
    resources:
      limits:
        cpus: '1.0'
        memory: 1024M
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.fit-api.rule=Host(`api.fit.armandointeligencia.com`)"
    - "traefik.http.routers.fit-api.entrypoints=websecure"
    - "traefik.http.routers.fit-api.tls.certresolver=letsencrypt"
    - "traefik.http.services.fit-api.loadbalancer.server.port=8000"

fit-web:
  image: ghcr.io/armando/fit-web:latest
  depends_on:
    - fit-api
  environment:
    NEXT_PUBLIC_API_URL: https://api.fit.armandointeligencia.com
    NEXT_PUBLIC_CLAUDE_API_KEY: ${CLAUDE_API_KEY}
  networks:
    - frontend
  deploy:
    resources:
      limits:
        cpus: '0.5'
        memory: 512M
  restart: unless-stopped
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.fit.rule=Host(`fit.armandointeligencia.com`)"
    - "traefik.http.routers.fit.entrypoints=websecure"
    - "traefik.http.routers.fit.tls.certresolver=letsencrypt"
    - "traefik.http.services.fit.loadbalancer.server.port=3000"
```

---

## ESTIMATED TIMELINE

**Existing Features (Nutrition Module):**
- Database Schema: 1.5 hours
- Product Lookup Service: 3 hours
- API Endpoints: 4 hours
- Frontend Components: 4 hours
- Barcode Scanner Integration: 2 hours

**New Features (Meal Planning Module):**
- Database Schema Additions: 2 hours
- Shopping List Generator Service: 3 hours
- TDEE Calculator & Macro Goal System: 2.5 hours
- Photo Recognition Integration: 2 hours
- Meal Planner UI (drag-and-drop): 3 hours
- Shopping List UI: 2 hours

**New Features (Workout Module):**
- Database Schema Additions: 2.5 hours
- Exercise Database Seeding (200 exercises): 3 hours
- Workout Program Logic & Endpoints: 3 hours
- Gym Session Logging Backend: 2.5 hours
- Rest Timer Component: 2 hours
- Workout Logger UI: 3 hours
- Workout History & Analytics UI: 3 hours
- Progressive Overload Tracking: 2 hours

**Testing & Deployment:**
- Integration Testing: 3 hours
- Deployment & Optimization: 2 hours

**Total:** ~55-65 hours

---

**Application Version:** 2.0 (Full Health App Expansion)
**Status:** In Development
