# FitTracker -- Product Requirements Document

**Version:** 1.0
**Last Updated:** 2026-04-03
**Deployment Target:** fit.armandointeligencia.com

---

## 1. Product Vision and Goals

### Vision

FitTracker is a mobile-first health and fitness web application built for Spanish-speaking Latin American users. It provides a single, integrated platform for tracking nutrition via barcode scanning and meal logging, planning weekly meals with auto-generated shopping lists, and following structured workout programs with real-time gym logging.

### Goals

1. **Reduce friction in nutrition tracking** -- users scan a barcode or take a photo to log food in under 10 seconds, with cascading API lookups that cover products sold in Latin American markets.
2. **Simplify meal planning** -- a weekly planner with TDEE-based macro targets and one-click shopping list generation eliminates spreadsheets and guesswork.
3. **Replace pen-and-paper gym logs** -- structured programs, a built-in rest timer, automatic PR detection, and volume analytics keep users progressing without needing a separate notebook.
4. **Deploy as a progressive web app** -- installable on any phone, usable offline, no app store approval required.

### Non-Goals (v1)

- Social features (sharing, leaderboards, friends)
- Wearable device integration (Apple Watch, Fitbit)
- Paid subscription or paywall
- Native iOS/Android app

---

## 2. Target Users

### Persona 1: Carlos the Maintainer

| Attribute | Detail |
|---|---|
| **Age / Sex** | 30 / Male |
| **Location** | Mexico City, Mexico |
| **Activity Level** | Moderate (gym 3x/week, walks daily) |
| **Goal** | Maintain current weight while improving body composition |
| **Pain Points** | Loses track of what he eats during busy work weeks; has no idea how many grams of protein he actually consumes; finds existing apps overwhelming and English-only |
| **TDEE Estimate** | ~2,500 kcal (80 kg, 178 cm, moderate activity) |
| **Key Flows** | Scans breakfast items on the way to work, reviews daily dashboard at night, follows a 3-day Upper/Lower program |

### Persona 2: Maria the Cutter

| Attribute | Detail |
|---|---|
| **Age / Sex** | 25 / Female |
| **Location** | Bogota, Colombia |
| **Activity Level** | Active (gym 5x/week, group classes) |
| **Goal** | Fat loss -- reduce body fat while preserving lean mass |
| **Pain Points** | Needs precise calorie counting; wants a shopping list so she meal-preps on Sundays; existing planners do not account for Latin American grocery items |
| **TDEE Estimate** | ~1,900 kcal (62 kg, 165 cm, active, -500 kcal deficit) |
| **Key Flows** | Sets fat-loss goal preset, plans 7 days of meals, generates a shopping list, logs every meal, reviews weekly macro trend |

### Persona 3: Roberto the Bulker

| Attribute | Detail |
|---|---|
| **Age / Sex** | 45 / Male |
| **Location** | Buenos Aires, Argentina |
| **Activity Level** | Sedentary (desk job, just started training) |
| **Goal** | Muscle gain -- increase lean body mass after years of inactivity |
| **Pain Points** | Needs guided workout programs (does not know exercises); needs a rest timer because he loses track of time; wants to see that he is making progress |
| **TDEE Estimate** | ~2,400 kcal (90 kg, 175 cm, sedentary, +500 kcal surplus) |
| **Key Flows** | Selects a beginner full-body program, starts a session, logs sets with the rest timer running, checks PRs after each session, reviews volume-by-muscle analytics weekly |

---

## 3. Feature Requirements

### 3.1 Authentication and User Management

| # | Feature | Description | Status |
|---|---|---|---|
| A-01 | User Registration | Email/password sign-up with validation | Not Implemented |
| A-02 | User Login (JWT) | Token-based authentication with refresh | Not Implemented |
| A-03 | Multi-User Isolation | All data scoped to authenticated user_id | Not Implemented |

> **Note:** The current system passes `user_id` as a query parameter. Authentication will replace this with JWT-derived user identity.

### 3.2 Nutrition Tracking

| # | Feature | Description | Status |
|---|---|---|---|
| N-01 | Barcode Scanning | Camera-based scanning via html5-qrcode with beep feedback | Implemented |
| N-02 | Manual Barcode Entry | Text input for barcode when camera is unavailable (iOS PWA fallback) | Implemented |
| N-03 | Product Lookup Cascade | Local DB cache -> Open Food Facts (mx, then world) -> FatSecret -> USDA FDC | Implemented |
| N-04 | Manual Product Entry | Create custom products with full nutrition info | Implemented |
| N-05 | Meal Logging (CRUD) | Create meals (breakfast/lunch/dinner/snack), add items with serving sizes, delete meals and items | Implemented |
| N-06 | Daily Nutrition Summary | Aggregate macros (calories, protein, carbs, fat, fiber) from logged meals for a given date | Implemented |
| N-07 | Weekly Nutrition Summary | 7-day macro trend data for chart visualization | Implemented |
| N-08 | Macro Charts (Recharts) | Pie chart for daily macro breakdown, line/bar chart for weekly calorie trend | Implemented |
| N-09 | Nutrition Goals | Set and retrieve daily calorie/macro targets with sensible defaults (2000 kcal) | Implemented |
| N-10 | Photo Food Recognition | Claude Vision API analysis of food photos with cross-reference to food databases | Not Implemented |

### 3.3 Meal Planning

| # | Feature | Description | Status |
|---|---|---|---|
| P-01 | TDEE Calculator | Mifflin-St Jeor BMR with activity multiplier; warns if calories < 1200 (F) or < 1500 (M) | Implemented |
| P-02 | Goal Presets | Fat Loss (-500), Maintenance, Lean Bulk (+250), Muscle Gain (+500) with auto macro calculation (2g protein/kg, 25% fat, remainder carbs) | Implemented |
| P-03 | Custom Macro Goals | Override preset with user-defined calorie and macro targets | Implemented |
| P-04 | User Profile | Store weight, height, age, sex, activity level; auto-calculate BMR/TDEE | Implemented |
| P-05 | Weekly Meal Planner | Create 7-day plans with items assigned to day/meal-type slots | Implemented |
| P-06 | Shopping List Generation | Aggregate ingredients from a meal plan, group by food category | Implemented |
| P-07 | Shopping List Checkoff | Toggle individual items as checked/unchecked | Implemented |
| P-08 | Drag-and-Drop Meal Rearrangement | @dnd-kit integration for moving meals between days/slots | Not Implemented |

### 3.4 Workout Tracker

| # | Feature | Description | Status |
|---|---|---|---|
| W-01 | Program Browser | List preset and user-created workout programs (9 presets, 56+ exercises) | Implemented |
| W-02 | Program Detail View | View program days with scheduled exercises, sets, and rep ranges | Implemented |
| W-03 | Custom Program Creation | Users create their own programs | Implemented |
| W-04 | Session Logging | Start a workout session linked to a program/day; mark complete with duration | Implemented |
| W-05 | Set Logging | Record exercise, weight (kg), reps per set within a session | Implemented |
| W-06 | Rest Timer | Countdown timer with Web Audio API beep; exercise preview during rest | Implemented |
| W-07 | PR Detection | Automatic personal record check using Brzycki + Epley 1RM averaging (accurate 2-10 rep range) | Implemented |
| W-08 | Workout History | Calendar view of past sessions with program name, total sets, total volume | Implemented |
| W-09 | Volume Analytics | Volume (sets x reps x weight) aggregated by muscle group for weekly/monthly periods | Implemented |
| W-10 | Personal Records List | View all PRs per exercise with date achieved and estimated 1RM | Implemented |

### 3.5 Global / Cross-Cutting

| # | Feature | Description | Status |
|---|---|---|---|
| G-01 | Spanish Localization | All user-facing strings in Spanish with i18n framework | Not Implemented |
| G-02 | PWA / Offline Support | Service worker (Serwist), offline caching, installable manifest | Not Implemented |
| G-03 | Error Boundaries | React error boundaries on every route with friendly fallback UI | Not Implemented |
| G-04 | CSV Data Export | Export nutrition logs and workout history as CSV | Not Implemented |

---

## 4. Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Responsiveness** | Mobile-first design; functional on 320px width; optimized for 375px-428px (common phones) |
| **Performance** | Page load under 3 seconds on 4G; API response under 500ms for local queries |
| **Accessibility** | WCAG 2.1 AA compliance; sufficient color contrast; screen reader labels on interactive elements |
| **Security** | HTTPS everywhere; JWT auth with httpOnly refresh tokens; bcrypt password hashing; SQL injection prevention via ORM |
| **Deployment** | Docker Compose with Traefik reverse proxy; TLS via Let's Encrypt; deployed to fit.armandointeligencia.com |
| **Availability** | 99.5% uptime target; health check endpoint at /health |
| **Data Integrity** | PostgreSQL with foreign key constraints; cascading deletes where appropriate; unique constraints on barcodes and user-date nutrition |
| **External API Resilience** | Timeout (10s per API), retry with backoff, graceful degradation to manual entry |

---

## 5. Tech Stack

| Layer | Technology | Version |
|---|---|---|
| **Frontend Framework** | Next.js (App Router) | 14+ |
| **Language** | TypeScript | 5.x |
| **Styling** | TailwindCSS | 3.x |
| **Charts** | Recharts | 2.x |
| **Barcode Scanning** | html5-qrcode | 2.3.8 |
| **Drag and Drop** | @dnd-kit | 6.x |
| **PWA** | Serwist | -- |
| **Backend Framework** | FastAPI | 0.104+ |
| **ORM** | SQLAlchemy (async) | 2.0+ |
| **Validation** | Pydantic v2 | 2.x |
| **HTTP Client** | httpx | 0.25+ |
| **Database** | PostgreSQL | 16 |
| **Python Runtime** | Python | 3.12+ |
| **Package Manager (Backend)** | uv | -- |
| **Package Manager (Frontend)** | pnpm | -- |
| **Containerization** | Docker + Docker Compose | -- |
| **Reverse Proxy** | Traefik | 2.x |

---

## 6. Database Schema Summary

The database consists of 17 models across three modules.

### 6.1 Nutrition Module (6 models)

| Model | Table | Key Columns | Relationships |
|---|---|---|---|
| **Product** | `products` | id, barcode (unique), name, brand, serving_size_g, calories, protein_g, carbs_g, fiber_g, fat_g, source, image_url | Referenced by MealItem, MealPlanItem |
| **Meal** | `meals` | id, user_id (FK), meal_type, meal_date | Has many MealItems |
| **MealItem** | `meal_items` | id, meal_id (FK), product_id (FK), quantity_servings, quantity_grams | Belongs to Meal and Product |
| **DailyNutrition** | `daily_nutrition` | id, user_id, nutrition_date, total_calories, total_protein_g, total_carbs_g, total_fat_g, total_fiber_g, meals_count | Unique on (user_id, nutrition_date) |
| **NutritionGoal** | `nutrition_goals` | id, user_id (FK, unique), daily_calories, daily_protein_g, daily_carbs_g, daily_fat_g | One per user |

### 6.2 Meal Planning Module (5 models)

| Model | Table | Key Columns | Relationships |
|---|---|---|---|
| **UserProfile** | `user_profiles` | id, user_id (FK, unique), weight_kg, height_cm, age, sex, activity_level, bmr, tdee, goal_preset, custom_daily_calories, custom_protein_g, custom_carbs_g, custom_fat_g | One per user |
| **MealPlan** | `meal_plans` | id, user_id (FK), name, week_start_date | Has many MealPlanItems |
| **MealPlanItem** | `meal_plan_items` | id, meal_plan_id (FK), product_id (FK), day_of_week, meal_type, servings | Belongs to MealPlan and Product |
| **ShoppingList** | `shopping_lists` | id, meal_plan_id (FK), user_id (FK), generated_at | Has many ShoppingListItems |
| **ShoppingListItem** | `shopping_list_items` | id, shopping_list_id (FK), product_name, quantity, unit, category, is_checked | Belongs to ShoppingList |

### 6.3 Workout Module (6 models)

| Model | Table | Key Columns | Relationships |
|---|---|---|---|
| **Exercise** | `exercises` | id, name, primary_muscle, secondary_muscles, equipment, difficulty, instructions, image_url | Referenced by WorkoutProgramExercise, WorkoutSet, PersonalRecord |
| **WorkoutProgram** | `workout_programs` | id, user_id, name, description, days_per_week, difficulty, is_preset | Has many WorkoutProgramDays |
| **WorkoutProgramDay** | `workout_program_days` | id, program_id (FK), day_name, day_order | Has many WorkoutProgramExercises |
| **WorkoutProgramExercise** | `workout_program_exercises` | id, program_day_id (FK), exercise_id (FK), sets, reps_min, reps_max, rest_seconds | Belongs to WorkoutProgramDay and Exercise |
| **WorkoutSession** | `workout_sessions` | id, user_id, program_id, program_day_id, started_at, completed_at, duration_minutes, notes | Has many WorkoutSets |
| **WorkoutSet** | `workout_sets` | id, session_id (FK), exercise_id (FK), set_number, weight_kg, reps, is_pr | Belongs to WorkoutSession and Exercise |
| **PersonalRecord** | `personal_records` | id, user_id, exercise_id (FK), weight_kg, reps, estimated_1rm, achieved_at | Belongs to Exercise |

### Key Indexes

- `idx_products_barcode` on products(barcode)
- `idx_meals_user_date` on meals(user_id, meal_date)
- `idx_meal_items_meal` on meal_items(meal_id)
- `idx_daily_nutrition_user_date` on daily_nutrition(user_id, nutrition_date)

---

## 7. API Endpoints Summary

All endpoints are versioned under `/api/v1/`. The API is organized across 8 routers with 40+ endpoints.

### 7.1 Products (`/api/v1/products`)

| Method | Path | Description |
|---|---|---|
| GET | `/products/search?barcode={barcode}` | Look up product by barcode (cache -> OFF -> FatSecret -> USDA) |
| POST | `/products` | Create manual product entry |
| GET | `/products/{product_id}` | Get product by ID |

### 7.2 Meals (`/api/v1/meals`)

| Method | Path | Description |
|---|---|---|
| POST | `/meals` | Create a new meal (breakfast/lunch/dinner/snack) |
| GET | `/meals/{meal_date}?user_id={id}` | Get all meals for a date |
| POST | `/meals/{meal_id}/items` | Add food item to a meal |
| DELETE | `/meals/{meal_id}/items/{item_id}` | Remove food item from a meal |
| DELETE | `/meals/{meal_id}` | Delete an entire meal |

### 7.3 Nutrition (`/api/v1/nutrition`)

| Method | Path | Description |
|---|---|---|
| GET | `/nutrition/daily/{date}?user_id={id}` | Daily macro summary |
| GET | `/nutrition/weekly?user_id={id}&start_date=&end_date=` | Weekly macro trend (defaults to last 7 days) |

### 7.4 Nutrition Goals (`/api/v1/nutrition/goals`)

| Method | Path | Description |
|---|---|---|
| GET | `/nutrition/goals?user_id={id}` | Get nutrition goals (defaults: 2000 cal, 150g protein, 250g carbs, 65g fat) |
| PUT | `/nutrition/goals?user_id={id}` | Create or update nutrition goals |

### 7.5 Profile (`/api/v1/profile`)

| Method | Path | Description |
|---|---|---|
| POST | `/profile?user_id={id}` | Create or update profile (auto-calculates BMR/TDEE) |
| GET | `/profile/tdee?user_id={id}` | Get current TDEE and macro targets |
| POST | `/profile/goals?user_id={id}` | Set goal preset (fat_loss, maintenance, lean_bulk, muscle_gain) |

### 7.6 Meal Plans (`/api/v1/meal-plans`)

| Method | Path | Description |
|---|---|---|
| POST | `/meal-plans?user_id={id}` | Create a meal plan |
| GET | `/meal-plans?user_id={id}` | List all meal plans (ordered by week start, newest first) |
| GET | `/meal-plans/{plan_id}` | Get a specific meal plan |
| DELETE | `/meal-plans/{plan_id}` | Delete a meal plan |
| POST | `/meal-plans/{plan_id}/items` | Add item to meal plan |
| DELETE | `/meal-plans/{plan_id}/items/{item_id}` | Remove item from meal plan |
| GET | `/meal-plans/{plan_id}/shopping-list?user_id={id}` | Generate shopping list for a plan |
| PATCH | `/meal-plans/shopping-lists/{list_id}/items/{item_id}/check` | Toggle shopping item check |

### 7.7 Exercises (`/api/v1/exercises`)

| Method | Path | Description |
|---|---|---|
| GET | `/exercises?muscle=&equipment=&difficulty=&q=&limit=&offset=` | List/search exercises (paginated, filterable) |
| GET | `/exercises/{exercise_id}` | Get exercise detail |

### 7.8 Workouts (`/api/v1/workouts`)

| Method | Path | Description |
|---|---|---|
| GET | `/workouts/programs?user_id={id}` | List programs (presets + user-created) |
| GET | `/workouts/programs/{program_id}` | Get program detail with days and exercises |
| POST | `/workouts/programs?user_id={id}` | Create custom program |
| POST | `/workouts/sessions?user_id={id}` | Start a workout session |
| GET | `/workouts/sessions/{session_id}` | Get session detail |
| POST | `/workouts/sessions/{session_id}/sets?user_id={id}` | Log a set (with automatic PR check) |
| PATCH | `/workouts/sessions/{session_id}/complete` | Mark session complete |
| GET | `/workouts/history?user_id={id}&start_date=&end_date=` | Workout history (defaults to 30 days) |
| GET | `/workouts/volume?user_id={id}&period=week|month` | Volume by muscle group |
| GET | `/workouts/prs?user_id={id}` | List all personal records |

---

## 8. Frontend Pages

| Route | Page | Module |
|---|---|---|
| `/` | Landing / Home | -- |
| `/dashboard` | Daily summary with macro charts | Nutrition |
| `/scan` | Barcode scanner + manual entry | Nutrition |
| `/meals` | Meal logging and history | Nutrition |
| `/meals/plan` | Weekly meal planner | Planning |
| `/goals` | Nutrition goals editor | Nutrition |
| `/profile` | User profile + TDEE setup | Planning |
| `/workouts` | Program browser | Workouts |
| `/workouts/[programId]` | Program detail with day/exercise view | Workouts |
| `/workouts/log/[sessionId]` | Active session logger with rest timer | Workouts |
| `/workouts/history` | Workout history + volume analytics | Workouts |
| `/exercises` | Exercise database browser (search, filter) | Workouts |

---

## 9. External API Integration

### Lookup Cascade Order

```
1. Local PostgreSQL cache (barcode index)
2. Open Food Facts -- mx.openfoodfacts.org (Mexico-specific)
3. Open Food Facts -- world.openfoodfacts.org (global)
4. FatSecret Platform API (OAuth 1.0a, 90%+ barcode hit rate)
5. USDA FoodData Central (text search only, no barcode endpoint)
6. Claude Vision API (photo recognition, future)
7. Manual entry (always available)
```

### Rate Limits

| API | Limit | Auth |
|---|---|---|
| Open Food Facts | 100 req/min (products), 10 req/min (search) | Custom User-Agent |
| USDA FDC | 1,000 req/hour | API key |
| FatSecret | Tier-dependent | OAuth 1.0a |
| Claude Vision | Pay-per-use (~$0.005-0.015/image) | API key |

---

## 10. Success Metrics

| Metric | Target | Measurement |
|---|---|---|
| **Barcode scan success rate** | >80% of scans return a product | Count of 200-responses / total scan attempts |
| **Time to log a meal** | <30 seconds (scan + confirm) | Frontend timing from scan page open to meal item saved |
| **Weekly active meal plans** | >50% of active users have a current-week plan | Users with a meal_plan.week_start_date = current week / total active users |
| **Workout session completion rate** | >70% of started sessions are marked complete | Sessions with completed_at / total sessions |
| **Page load (LCP)** | <3 seconds on 4G | Lighthouse / Web Vitals |
| **API latency (p95)** | <500ms for local queries, <3s for external lookups | Server-side timing middleware |
| **PR detection accuracy** | 100% of valid PRs detected | Unit tests on Brzycki + Epley 1RM logic |
| **Shopping list generation time** | <2 seconds | Server-side timing on shopping list endpoint |
| **Crash-free sessions** | >99% | Error boundary catch rate + server 500 count |
| **User retention (7-day)** | >40% of new users return within 7 days | Return visits tracked by user_id |
