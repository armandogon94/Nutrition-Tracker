import type { DailyNutrition, Meal, NutritionGoal, Product } from "./types";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8001";

// Temporary hardcoded user ID until auth is implemented
const USER_ID = "00000000-0000-0000-0000-000000000001";

async function fetchAPI<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json", ...options?.headers },
    ...options,
  });
  if (!res.ok) {
    const error = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(error.detail || `API error: ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return res.json();
}

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
    body: JSON.stringify({ user_id: USER_ID, meal_type: mealType, meal_date: mealDate }),
  });

export const getMealsByDate = (date: string) =>
  fetchAPI<Meal[]>(`/api/v1/meals/${date}?user_id=${USER_ID}`);

export const addMealItem = (mealId: string, productId: string, servings: number = 1) =>
  fetchAPI<unknown>(`/api/v1/meals/${mealId}/items`, {
    method: "POST",
    body: JSON.stringify({ product_id: productId, quantity_servings: servings }),
  });

export const removeMealItem = (mealId: string, itemId: string) =>
  fetchAPI<void>(`/api/v1/meals/${mealId}/items/${itemId}`, { method: "DELETE" });

// Nutrition
export const getDailyNutrition = (date: string) =>
  fetchAPI<DailyNutrition>(`/api/v1/nutrition/daily/${date}?user_id=${USER_ID}`);

export const getWeeklyNutrition = (startDate: string, endDate: string) =>
  fetchAPI<DailyNutrition[]>(
    `/api/v1/nutrition/weekly?user_id=${USER_ID}&start_date=${startDate}&end_date=${endDate}`
  );

// Goals
export const getGoals = () =>
  fetchAPI<NutritionGoal>(`/api/v1/nutrition/goals?user_id=${USER_ID}`);

export const updateGoals = (goals: NutritionGoal) =>
  fetchAPI<NutritionGoal>(`/api/v1/nutrition/goals?user_id=${USER_ID}`, {
    method: "PUT",
    body: JSON.stringify(goals),
  });
