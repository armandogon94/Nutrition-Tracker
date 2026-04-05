# FitTracker -- User Story Map

**Version:** 1.0
**Last Updated:** 2026-04-03

---

## Story Map Overview

```
Activities (columns):
  Onboarding | Daily Nutrition Tracking | Meal Planning | Workout Training | Progress Review

Walking Skeleton (MVP):
  Profile setup | Scan barcode + log meal | Create plan | Browse programs | View dashboard
              |                          |               | Start session   |

Release 1 (US-001 -- US-015):  Must-have features across all modules
Release 2 (US-016 -- US-020):  Nice-to-have features (DnD, photo AI, i18n, PWA, export)
```

---

## Walking Skeleton (MVP)

The minimum path a user takes through all five activities:

1. **Onboarding** -- Enter profile stats (weight, height, age, sex, activity level), receive TDEE calculation
2. **Daily Nutrition Tracking** -- Scan one barcode, confirm product, add to a breakfast meal, see the item logged
3. **Meal Planning** -- Create a weekly plan, add one item to Monday breakfast, generate a shopping list
4. **Workout Training** -- Browse programs, select one, start a session, log one set, complete the session
5. **Progress Review** -- View dashboard with today's macros and a weekly calorie chart

---

## Release 1 -- Must-Have Features

### Onboarding

#### US-001: User Registration and Login

> As a new user, I want to create an account and log in so that my data is private and persisted across devices.

**Acceptance Criteria:**
- User can register with email and password; duplicate emails are rejected with a clear error
- Login returns a JWT access token and httpOnly refresh token; all subsequent API calls require the token
- Unauthenticated requests to any endpoint return 401

**Status:** Not Implemented

**Touches:**
- Backend: New `/api/v1/auth/register`, `/api/v1/auth/login`, `/api/v1/auth/refresh` endpoints
- Frontend: New `/login` and `/register` pages
- Database: `users` table (id, email, password_hash, created_at)

---

#### US-002: User Profile and TDEE Setup

> As a user, I want to enter my physical stats and activity level so that the app can calculate my daily calorie needs.

**Acceptance Criteria:**
- Profile form collects weight (kg), height (cm), age, sex (male/female), and activity level (sedentary through very active)
- On save, the backend calculates BMR (Mifflin-St Jeor) and TDEE; both values are returned and displayed
- If the resulting calorie target falls below 1200 kcal, a warning is shown

**Status:** Implemented

**Touches:**
- Backend: `POST /api/v1/profile`, `GET /api/v1/profile/tdee`
- Frontend: `/profile` page
- Database: `user_profiles` table

---

### Daily Nutrition Tracking

#### US-003: Barcode Scanning

> As a user, I want to scan a product barcode with my phone camera so that I can look up its nutrition information without typing.

**Acceptance Criteria:**
- Camera viewfinder opens with a scan region; a beep plays on successful decode
- The decoded barcode triggers the product lookup cascade (cache -> OFF -> FatSecret -> USDA)
- If no product is found, the user is prompted to enter nutrition data manually

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/products/search?barcode={barcode}`
- Frontend: `/scan` page (html5-qrcode, loaded via `next/dynamic` with `ssr: false`)
- Services: `product_lookup.py` cascade

---

#### US-004: Manual Product Entry

> As a user, I want to manually enter a product's nutrition data when barcode scanning fails so that I can still log my food.

**Acceptance Criteria:**
- A form is available from the scan page with fields for name, barcode, serving size, calories, protein, carbs, fat
- On submit, the product is saved to the database and immediately available for meal logging
- Duplicate barcodes are rejected with a 409 error and a user-friendly message

**Status:** Implemented

**Touches:**
- Backend: `POST /api/v1/products`
- Frontend: `/scan` page (manual entry form)
- Database: `products` table

---

#### US-005: Meal Logging

> As a user, I want to create meals and add food items so that I can track what I eat throughout the day.

**Acceptance Criteria:**
- User can create a meal for a date with a type (breakfast, lunch, dinner, snack)
- Food items are added to a meal by selecting a product and specifying a serving quantity
- Meals and individual items can be deleted

**Status:** Implemented

**Touches:**
- Backend: `POST /api/v1/meals`, `POST /api/v1/meals/{id}/items`, `DELETE /api/v1/meals/{id}`, `DELETE /api/v1/meals/{id}/items/{id}`
- Frontend: `/meals` page
- Database: `meals`, `meal_items` tables

---

#### US-006: Daily Dashboard

> As a user, I want to see a summary of today's nutrition so that I know how I am tracking against my goals.

**Acceptance Criteria:**
- Dashboard shows total calories, protein, carbs, and fat consumed today
- A pie chart displays the macro breakdown; a progress bar shows calories consumed vs. goal
- The weekly trend chart shows the last 7 days of calorie intake

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/nutrition/daily/{date}`, `GET /api/v1/nutrition/weekly`, `GET /api/v1/nutrition/goals`
- Frontend: `/dashboard` page (Recharts pie chart and bar chart)
- Services: `nutrition_calc.py`

---

#### US-007: Nutrition Goals

> As a user, I want to set daily calorie and macro targets so that the dashboard shows my progress toward specific goals.

**Acceptance Criteria:**
- User can set custom daily targets for calories, protein, carbs, and fat
- Default goals (2000 kcal, 150g protein, 250g carbs, 65g fat) are used until the user overrides them
- Goals can also be set via TDEE-based presets (fat loss, maintenance, lean bulk, muscle gain)

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/nutrition/goals`, `PUT /api/v1/nutrition/goals`, `POST /api/v1/profile/goals`
- Frontend: `/goals` page, `/profile` page (preset selector)
- Database: `nutrition_goals`, `user_profiles` tables

---

### Meal Planning

#### US-008: Weekly Meal Plan Creation

> As a user, I want to create a weekly meal plan and assign foods to specific days and meal slots so that I can prepare my meals in advance.

**Acceptance Criteria:**
- User can create a named plan tied to a week start date
- Items are added to a plan by specifying a product, day of the week (0-6), meal type, and serving count
- Plans are listed in reverse chronological order; individual plans and items can be deleted

**Status:** Implemented

**Touches:**
- Backend: `POST /api/v1/meal-plans`, `GET /api/v1/meal-plans`, `POST /api/v1/meal-plans/{id}/items`, `DELETE /api/v1/meal-plans/{id}/items/{id}`
- Frontend: `/meals/plan` page
- Database: `meal_plans`, `meal_plan_items` tables

---

#### US-009: Shopping List Generation

> As a user, I want to generate a shopping list from my meal plan so that I know exactly what to buy at the store.

**Acceptance Criteria:**
- One click generates a list aggregating all products from the plan, grouped by food category
- Quantities are summed across the week (e.g., 3 servings of rice on Monday + 2 on Thursday = 5 total)
- Individual items can be checked off as purchased

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/meal-plans/{id}/shopping-list`, `PATCH /api/v1/meal-plans/shopping-lists/{id}/items/{id}/check`
- Frontend: `/meals/plan` page (shopping list panel)
- Services: `shopping_list.py`
- Database: `shopping_lists`, `shopping_list_items` tables

---

### Workout Training

#### US-010: Program Browser

> As a user, I want to browse available workout programs so that I can choose one that fits my schedule and goals.

**Acceptance Criteria:**
- Programs are listed with name, description, days per week, and difficulty level
- Both preset programs (seeded, 9 programs) and user-created programs are shown
- Clicking a program opens its detail view with the full day/exercise breakdown

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/workouts/programs`
- Frontend: `/workouts` page
- Database: `workout_programs` table

---

#### US-011: Program Detail View

> As a user, I want to see the full structure of a program so that I know what exercises to do on each training day.

**Acceptance Criteria:**
- Each day shows its exercises with target sets, rep ranges, and rest periods
- Exercise names link to the exercise detail (muscle groups, equipment, instructions)
- A "Start Workout" button initiates a session for the selected day

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/workouts/programs/{id}`
- Frontend: `/workouts/[programId]` page
- Database: `workout_programs`, `workout_program_days`, `workout_program_exercises` tables

---

#### US-012: Workout Session Logging

> As a user, I want to start a workout session and log my sets in real time so that I have an accurate record of my training.

**Acceptance Criteria:**
- Starting a session records the start time and links to the program/day
- The user logs sets one at a time, specifying exercise, weight, and reps
- Completing the session records the end time and calculates duration in minutes

**Status:** Implemented

**Touches:**
- Backend: `POST /api/v1/workouts/sessions`, `PATCH /api/v1/workouts/sessions/{id}/complete`
- Frontend: `/workouts/log/[sessionId]` page
- Database: `workout_sessions` table

---

#### US-013: Set Logging with PR Detection

> As a user, I want each set I log to be automatically checked for personal records so that I am notified when I hit a new PR.

**Acceptance Criteria:**
- After logging a set, the backend calculates estimated 1RM using the average of Brzycki and Epley formulas
- If the estimated 1RM exceeds the stored PR for that exercise, the set is flagged `is_pr=true` and the record is updated
- The frontend shows a PR badge or notification on the logged set

**Status:** Implemented

**Touches:**
- Backend: `POST /api/v1/workouts/sessions/{id}/sets` (calls `check_and_update_pr`)
- Frontend: `/workouts/log/[sessionId]` page (PR badge)
- Services: `workout_service.py`
- Database: `workout_sets`, `personal_records` tables

---

#### US-014: Rest Timer

> As a user, I want a countdown rest timer between sets so that I maintain consistent rest periods without watching a clock.

**Acceptance Criteria:**
- After logging a set, a countdown timer starts automatically based on the exercise's prescribed rest time
- An audible beep (Web Audio API) plays when the timer reaches zero; on devices without vibration support, the beep is the primary alert
- The timer uses timestamp-based calculation and recalculates on `visibilitychange` to handle Chrome background throttling

**Status:** Implemented

**Touches:**
- Frontend: `/workouts/log/[sessionId]` page (RestTimer component)
- No backend endpoint (client-side only)

---

#### US-015: Workout History

> As a user, I want to view my past workouts so that I can review what I have done and track my consistency.

**Acceptance Criteria:**
- History page lists sessions in reverse chronological order with date, program name, day name, total sets, total volume, and duration
- Default range is the last 30 days; start and end dates can be adjusted
- Volume-by-muscle analytics show sets and volume aggregated by primary muscle group for the selected period

**Status:** Implemented

**Touches:**
- Backend: `GET /api/v1/workouts/history`, `GET /api/v1/workouts/volume`, `GET /api/v1/workouts/prs`
- Frontend: `/workouts/history` page
- Database: `workout_sessions`, `workout_sets`, `personal_records` tables

---

## Release 2 -- Nice-to-Have Features

#### US-016: Drag-and-Drop Meal Rearrangement

> As a user, I want to drag and drop meals between days and meal slots in my weekly planner so that I can quickly rearrange my plan.

**Acceptance Criteria:**
- Meal plan items can be dragged from one day/meal-type cell and dropped into another
- The backend updates the item's `day_of_week` and `meal_type` on drop
- The drag interaction works on touch devices (mobile) as well as desktop

**Status:** Not Implemented

**Touches:**
- Frontend: `/meals/plan` page (@dnd-kit integration, `'use client'` directive)
- Backend: New `PATCH /api/v1/meal-plans/{plan_id}/items/{item_id}` endpoint for updating day/meal_type
- Database: `meal_plan_items` table (day_of_week, meal_type columns)

---

#### US-017: Photo Food Recognition

> As a user, I want to take a photo of my food and have the app estimate its nutrition so that I can log meals when I do not have a barcode.

**Acceptance Criteria:**
- User captures or uploads a photo from the scan page
- The photo is sent to Claude Vision API (Sonnet model) which returns food identification and estimated portions
- Results are cross-referenced with Open Food Facts / USDA for precise nutrition data; the user can adjust portions before logging

**Status:** Not Implemented

**Touches:**
- Backend: New `POST /api/v1/products/recognize` endpoint
- Frontend: `/scan` page (PhotoCapture component)
- Services: New `food_recognition.py` service
- External: Claude Vision API (~$0.005-0.015 per image)

---

#### US-018: Spanish Localization

> As a Spanish-speaking user, I want the entire interface in Spanish so that I can use the app in my native language.

**Acceptance Criteria:**
- All user-facing strings (labels, buttons, error messages, placeholders) are displayed in Spanish
- The app uses an i18n framework (e.g., next-intl or react-i18next) with string keys mapped to a Spanish locale file
- Dates, numbers, and units are formatted for Latin American locales (e.g., "1.500 kcal", "lunes 7 de abril")

**Status:** Not Implemented

**Touches:**
- Frontend: All pages and components (global change)
- New: `/locales/es.json` translation file, i18n provider in `layout.tsx`

---

#### US-019: PWA and Offline Support

> As a user, I want to install the app on my phone and have basic functionality offline so that I can log workouts at the gym even without connectivity.

**Acceptance Criteria:**
- The app is installable via the browser's "Add to Home Screen" prompt (valid manifest + service worker)
- Cached pages (dashboard, workout log, exercise list) load offline with stale data
- Offline actions (logging a set, creating a meal) are queued and synced when connectivity returns

**Status:** Not Implemented

**Touches:**
- Frontend: Serwist service worker configuration, `public/manifest.json`, cache strategies
- Note: Do NOT set `apple-mobile-web-app-capable` meta tag (iOS WebKit camera bug #185448)

---

#### US-020: CSV Data Export

> As a user, I want to export my nutrition logs and workout history as CSV files so that I can analyze my data in a spreadsheet or share it with a coach.

**Acceptance Criteria:**
- Export button on the dashboard generates a CSV of daily nutrition summaries for a selected date range
- Export button on the workout history page generates a CSV of sessions with sets, weights, and reps
- Files are named with the date range (e.g., `fittracker-nutrition-2026-03-01-to-2026-03-31.csv`)

**Status:** Not Implemented

**Touches:**
- Backend: New `GET /api/v1/nutrition/export?start_date=&end_date=&format=csv`, `GET /api/v1/workouts/export?start_date=&end_date=&format=csv`
- Frontend: `/dashboard` page (export button), `/workouts/history` page (export button)

---

## Story Map Matrix

The table below maps each story to its activity column and release row.

| | Onboarding | Daily Nutrition Tracking | Meal Planning | Workout Training | Progress Review |
|---|---|---|---|---|---|
| **Walking Skeleton** | Profile setup | Scan + log one item | Create plan + generate list | Browse + start + log one set | View dashboard |
| **Release 1** | US-001, US-002 | US-003, US-004, US-005, US-007 | US-008, US-009 | US-010, US-011, US-012, US-013, US-014 | US-006, US-015 |
| **Release 2** | -- | US-017 | US-016 | -- | US-018, US-019, US-020 |

---

## Endpoint and Page Coverage

A cross-reference of all stories to the backend endpoints and frontend pages they require.

| Story | Backend Endpoints | Frontend Pages |
|---|---|---|
| US-001 | `POST /auth/register`, `POST /auth/login`, `POST /auth/refresh` | `/login`, `/register` |
| US-002 | `POST /profile`, `GET /profile/tdee` | `/profile` |
| US-003 | `GET /products/search` | `/scan` |
| US-004 | `POST /products` | `/scan` |
| US-005 | `POST /meals`, `POST /meals/{id}/items`, `DELETE /meals/{id}`, `DELETE /meals/{id}/items/{id}` | `/meals` |
| US-006 | `GET /nutrition/daily/{date}`, `GET /nutrition/weekly`, `GET /nutrition/goals` | `/dashboard` |
| US-007 | `GET /nutrition/goals`, `PUT /nutrition/goals`, `POST /profile/goals` | `/goals`, `/profile` |
| US-008 | `POST /meal-plans`, `GET /meal-plans`, `POST /meal-plans/{id}/items`, `DELETE /meal-plans/{id}/items/{id}` | `/meals/plan` |
| US-009 | `GET /meal-plans/{id}/shopping-list`, `PATCH /meal-plans/shopping-lists/{id}/items/{id}/check` | `/meals/plan` |
| US-010 | `GET /workouts/programs` | `/workouts` |
| US-011 | `GET /workouts/programs/{id}` | `/workouts/[programId]` |
| US-012 | `POST /workouts/sessions`, `PATCH /workouts/sessions/{id}/complete` | `/workouts/log/[sessionId]` |
| US-013 | `POST /workouts/sessions/{id}/sets` | `/workouts/log/[sessionId]` |
| US-014 | (client-side only) | `/workouts/log/[sessionId]` |
| US-015 | `GET /workouts/history`, `GET /workouts/volume`, `GET /workouts/prs` | `/workouts/history` |
| US-016 | New `PATCH /meal-plans/{id}/items/{id}` | `/meals/plan` |
| US-017 | New `POST /products/recognize` | `/scan` |
| US-018 | (no backend changes) | All pages (i18n) |
| US-019 | (no backend changes) | Service worker, manifest |
| US-020 | New `GET /nutrition/export`, `GET /workouts/export` | `/dashboard`, `/workouts/history` |
