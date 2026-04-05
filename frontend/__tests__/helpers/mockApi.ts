import type {
  Product,
  Meal,
  MealItem,
  DailyNutrition,
  NutritionGoal,
  UserProfile,
  TDEEResult,
  Exercise,
  WorkoutProgram,
  WorkoutProgramDay,
  WorkoutProgramExercise,
  WorkoutSession,
  WorkoutSet,
  MealPlanType,
  ShoppingListType,
  AuthResponse,
} from "@/lib/types";

export function mockProduct(overrides?: Partial<Product>): Product {
  return {
    id: "prod-1",
    barcode: "7501000315000",
    name: "Avena Quaker",
    brand: "Quaker",
    serving_size_g: 40,
    calories: 150,
    protein_g: 5.0,
    carbs_g: 27.0,
    fat_g: 3.0,
    fiber_g: 4.0,
    source: "open_food_facts",
    image_url: "https://images.openfoodfacts.org/products/750/100/031/5000/front.jpg",
    created_at: "2026-04-01T10:00:00Z",
    ...overrides,
  };
}

export function mockMealItem(overrides?: Partial<MealItem>): MealItem {
  return {
    id: "mi-1",
    product_id: "prod-1",
    quantity_servings: 1,
    quantity_grams: null,
    product: mockProduct(),
    created_at: "2026-04-01T08:30:00Z",
    ...overrides,
  };
}

export function mockMeal(overrides?: Partial<Meal>): Meal {
  return {
    id: "meal-1",
    user_id: "user-1",
    meal_type: "breakfast",
    meal_date: "2026-04-01",
    items: [mockMealItem()],
    created_at: "2026-04-01T08:30:00Z",
    ...overrides,
  };
}

export function mockDailyNutrition(overrides?: Partial<DailyNutrition>): DailyNutrition {
  return {
    nutrition_date: "2026-04-01",
    total_calories: 1850,
    total_protein_g: 142,
    total_carbs_g: 210,
    total_fat_g: 58,
    total_fiber_g: 28,
    meals_count: 3,
    ...overrides,
  };
}

export function mockNutritionGoal(overrides?: Partial<NutritionGoal>): NutritionGoal {
  return {
    daily_calories: 2200,
    daily_protein_g: 160,
    daily_carbs_g: 250,
    daily_fat_g: 70,
    ...overrides,
  };
}

export function mockUserProfile(overrides?: Partial<UserProfile>): UserProfile {
  return {
    weight_kg: 78,
    height_cm: 175,
    age: 28,
    sex: "male",
    activity_level: "moderate",
    bmr: 1738,
    tdee: 2694,
    goal_preset: "maintenance",
    daily_calories: 2694,
    daily_protein_g: 156,
    daily_carbs_g: 304,
    daily_fat_g: 75,
    ...overrides,
  };
}

export function mockTDEEResult(overrides?: Partial<TDEEResult>): TDEEResult {
  return {
    bmr: 1738,
    tdee: 2694,
    activity_level: "moderate",
    goal_preset: "maintenance",
    daily_calories: 2694,
    daily_protein_g: 156,
    daily_carbs_g: 304,
    daily_fat_g: 75,
    ...overrides,
  };
}

export function mockExercise(overrides?: Partial<Exercise>): Exercise {
  return {
    id: "ex-1",
    name: "Barbell Bench Press",
    primary_muscle: "chest",
    secondary_muscles: "triceps, shoulders",
    equipment: "barbell",
    difficulty: "intermediate",
    instructions: "Lie on a flat bench, grip the barbell slightly wider than shoulder width. Lower to chest, press back up.",
    video_url: null,
    category: "strength",
    ...overrides,
  };
}

export function mockWorkoutProgramExercise(overrides?: Partial<WorkoutProgramExercise>): WorkoutProgramExercise {
  return {
    id: "wpe-1",
    exercise: mockExercise(),
    set_count: 4,
    rep_min: 6,
    rep_max: 8,
    rest_seconds: 120,
    exercise_order: 1,
    notes: null,
    ...overrides,
  };
}

export function mockWorkoutProgramDay(overrides?: Partial<WorkoutProgramDay>): WorkoutProgramDay {
  return {
    id: "wpd-1",
    day_number: 1,
    day_name: "Push Day",
    focus: "chest, shoulders, triceps",
    description: "Compound pushing movements",
    exercises: [mockWorkoutProgramExercise()],
    ...overrides,
  };
}

export function mockWorkoutProgram(overrides?: Partial<WorkoutProgram>): WorkoutProgram {
  return {
    id: "wp-1",
    name: "Push Pull Legs",
    description: "Classic 6-day PPL split for intermediate lifters. Focus on progressive overload with compound movements.",
    program_type: "hypertrophy",
    days_per_week: 6,
    difficulty: "intermediate",
    is_preset: true,
    days: [mockWorkoutProgramDay()],
    ...overrides,
  };
}

export function mockWorkoutSet(overrides?: Partial<WorkoutSet>): WorkoutSet {
  return {
    id: "ws-1",
    exercise_id: "ex-1",
    exercise: mockExercise(),
    set_number: 1,
    reps: 8,
    weight_kg: 80,
    rpe: 8,
    is_pr: false,
    completed_at: "2026-04-01T17:30:00Z",
    ...overrides,
  };
}

export function mockWorkoutSession(overrides?: Partial<WorkoutSession>): WorkoutSession {
  return {
    id: "session-1",
    user_id: "user-1",
    program_id: "wp-1",
    program_day_id: "wpd-1",
    started_at: "2026-04-01T17:00:00Z",
    completed_at: "2026-04-01T18:15:00Z",
    duration_minutes: 75,
    notes: "Good session, hit PRs on bench",
    sets: [mockWorkoutSet()],
    ...overrides,
  };
}

export function mockMealPlan(overrides?: Partial<MealPlanType>): MealPlanType {
  return {
    id: "mp-1",
    user_id: "user-1",
    name: "Week of Apr 1",
    week_start_date: "2026-03-30",
    notes: null,
    is_template: false,
    items: [],
    created_at: "2026-03-30T10:00:00Z",
    ...overrides,
  };
}

export function mockShoppingList(overrides?: Partial<ShoppingListType>): ShoppingListType {
  return {
    id: "sl-1",
    name: "Week of Apr 1 Shopping List",
    meal_plan_id: "mp-1",
    items: [
      { id: "sli-1", ingredient_name: "Chicken Breast", quantity: 1.5, unit: "kg", category: "Protein", is_checked: false },
      { id: "sli-2", ingredient_name: "Brown Rice", quantity: 2, unit: "kg", category: "Grains", is_checked: false },
      { id: "sli-3", ingredient_name: "Broccoli", quantity: 500, unit: "g", category: "Vegetables", is_checked: true },
    ],
    generated_at: "2026-03-30T10:00:00Z",
    ...overrides,
  };
}

export function mockAuthResponse(overrides?: Partial<AuthResponse>): AuthResponse {
  return {
    access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.mock-token-payload",
    token_type: "bearer",
    user: {
      id: "user-1",
      email: "test1@fittracker.dev",
      display_name: "Test User",
    },
    ...overrides,
  };
}
