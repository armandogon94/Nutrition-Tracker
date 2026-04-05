import { getToken, clearToken } from "./auth";
import type {
  AuthResponse,
  DailyNutrition,
  Exercise,
  Meal,
  MealPlanItem,
  MealPlanType,
  NutritionGoal,
  Product,
  ShoppingListType,
  TDEEResult,
  UserProfile,
  VolumeByMuscle,
  WorkoutHistoryEntry,
  WorkoutProgram,
  WorkoutSession,
  WorkoutSet,
} from "./types";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8001";

async function fetchAPI<T>(path: string, options?: RequestInit): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options?.headers as Record<string, string>),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });
  if (!res.ok) {
    if (res.status === 401 && typeof window !== 'undefined' && !path.startsWith('/api/v1/auth/')) {
      clearToken();
      window.location.href = '/login';
      throw new Error('Session expired');
    }
    const error = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(error.detail || `API error: ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return res.json();
}

// Auth
export const loginUser = (email: string, password: string) =>
  fetchAPI<AuthResponse>("/api/v1/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password }),
  });

export const registerUser = (email: string, password: string, display_name: string) =>
  fetchAPI<AuthResponse>("/api/v1/auth/register", {
    method: "POST",
    body: JSON.stringify({ email, password, display_name }),
  });

export const getCurrentUser = () =>
  fetchAPI<{ id: string; email: string; display_name: string }>("/api/v1/auth/me");

// Products
export const searchProduct = (barcode: string) =>
  fetchAPI<Product>(`/api/v1/products/search?barcode=${barcode}`);

export const createProduct = (data: Omit<Product, "id" | "created_at">) =>
  fetchAPI<Product>("/api/v1/products", {
    method: "POST",
    body: JSON.stringify(data),
  });

// Meals
export const createMeal = (mealType: string, mealDate: string) =>
  fetchAPI<Meal>("/api/v1/meals", {
    method: "POST",
    body: JSON.stringify({ meal_type: mealType, meal_date: mealDate }),
  });

export const getMealsByDate = (date: string) =>
  fetchAPI<Meal[]>(`/api/v1/meals/${date}`);

export const addMealItem = (mealId: string, productId: string, servings: number = 1) =>
  fetchAPI<unknown>(`/api/v1/meals/${mealId}/items`, {
    method: "POST",
    body: JSON.stringify({ product_id: productId, quantity_servings: servings }),
  });

export const removeMealItem = (mealId: string, itemId: string) =>
  fetchAPI<void>(`/api/v1/meals/${mealId}/items/${itemId}`, { method: "DELETE" });

// Nutrition
export const getDailyNutrition = (date: string) =>
  fetchAPI<DailyNutrition>(`/api/v1/nutrition/daily/${date}`);

export const getWeeklyNutrition = (startDate: string, endDate: string) =>
  fetchAPI<DailyNutrition[]>(
    `/api/v1/nutrition/weekly?start_date=${startDate}&end_date=${endDate}`
  );

// Goals
export const getGoals = () =>
  fetchAPI<NutritionGoal>("/api/v1/nutrition/goals");

export const updateGoals = (goals: NutritionGoal) =>
  fetchAPI<NutritionGoal>("/api/v1/nutrition/goals", {
    method: "PUT",
    body: JSON.stringify(goals),
  });

// Profile & TDEE
export const createProfile = (data: { weight_kg: number; height_cm: number; age: number; sex: string; activity_level: string }) =>
  fetchAPI<UserProfile>("/api/v1/profile", { method: "POST", body: JSON.stringify(data) });

export const getTDEE = () =>
  fetchAPI<TDEEResult>("/api/v1/profile/tdee");

export const setGoalPreset = (goal_preset: string) =>
  fetchAPI<TDEEResult>("/api/v1/profile/goals", {
    method: "POST",
    body: JSON.stringify({ goal_preset }),
  });

// Meal Plans
export const createMealPlan = (data: { name: string; week_start_date: string; notes?: string }) =>
  fetchAPI<MealPlanType>("/api/v1/meal-plans", { method: "POST", body: JSON.stringify(data) });

export const getMealPlans = () =>
  fetchAPI<MealPlanType[]>("/api/v1/meal-plans");

export const getMealPlan = (planId: string) =>
  fetchAPI<MealPlanType>(`/api/v1/meal-plans/${planId}`);

export const addMealPlanItem = (planId: string, data: { product_id: string; day_of_week: number; meal_type: string; quantity_servings?: number }) =>
  fetchAPI<MealPlanItem>(`/api/v1/meal-plans/${planId}/items`, { method: "POST", body: JSON.stringify(data) });

export const removeMealPlanItem = (planId: string, itemId: string) =>
  fetchAPI<void>(`/api/v1/meal-plans/${planId}/items/${itemId}`, { method: "DELETE" });

export const generateShoppingList = (planId: string) =>
  fetchAPI<ShoppingListType>(`/api/v1/meal-plans/${planId}/shopping-list`);

export const toggleShoppingItem = (listId: string, itemId: string, is_checked: boolean) =>
  fetchAPI<{ id: string; is_checked: boolean }>(`/api/v1/meal-plans/shopping-lists/${listId}/items/${itemId}/check`, {
    method: "PATCH",
    body: JSON.stringify({ is_checked }),
  });

// Exercises
export const getExercises = (params?: { muscle?: string; equipment?: string; difficulty?: string; q?: string; limit?: number; offset?: number }) => {
  const searchParams = new URLSearchParams();
  if (params?.muscle) searchParams.set("muscle", params.muscle);
  if (params?.equipment) searchParams.set("equipment", params.equipment);
  if (params?.difficulty) searchParams.set("difficulty", params.difficulty);
  if (params?.q) searchParams.set("q", params.q);
  if (params?.limit) searchParams.set("limit", String(params.limit));
  if (params?.offset) searchParams.set("offset", String(params.offset));
  return fetchAPI<{ exercises: Exercise[]; total: number }>(`/api/v1/exercises?${searchParams}`);
};

export const getExercise = (id: string) =>
  fetchAPI<Exercise>(`/api/v1/exercises/${id}`);

// Workouts
export const getPrograms = () =>
  fetchAPI<WorkoutProgram[]>("/api/v1/workouts/programs");

export const getProgram = (id: string) =>
  fetchAPI<WorkoutProgram>(`/api/v1/workouts/programs/${id}`);

export const startSession = (data: { program_id?: string; program_day_id?: string; started_at: string }) =>
  fetchAPI<WorkoutSession>("/api/v1/workouts/sessions", { method: "POST", body: JSON.stringify(data) });

export const getSession = (id: string) =>
  fetchAPI<WorkoutSession>(`/api/v1/workouts/sessions/${id}`);

export const logSet = (sessionId: string, data: { exercise_id: string; set_number: number; reps: number; weight_kg?: number; rpe?: number }) =>
  fetchAPI<WorkoutSet>(`/api/v1/workouts/sessions/${sessionId}/sets`, { method: "POST", body: JSON.stringify(data) });

export const completeSession = (sessionId: string, notes?: string) =>
  fetchAPI<WorkoutSession>(`/api/v1/workouts/sessions/${sessionId}/complete`, {
    method: "PATCH",
    body: JSON.stringify({ notes }),
  });

export const getWorkoutHistory = (startDate?: string, endDate?: string) => {
  const params = new URLSearchParams();
  if (startDate) params.set("start_date", startDate);
  if (endDate) params.set("end_date", endDate);
  return fetchAPI<WorkoutHistoryEntry[]>(`/api/v1/workouts/history?${params}`);
};

export const getVolume = (period: "week" | "month" = "week") =>
  fetchAPI<VolumeByMuscle[]>(`/api/v1/workouts/volume?period=${period}`);

export interface PersonalRecord {
  id: string;
  exercise_id: string;
  max_weight_kg: number;
  max_reps_at_weight: number | null;
  estimated_1rm: number;
  achieved_at: string;
}

export const getPersonalRecords = () =>
  fetchAPI<PersonalRecord[]>("/api/v1/workouts/prs");
