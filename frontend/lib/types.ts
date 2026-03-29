export interface Product {
  id: string;
  barcode: string;
  name: string;
  brand: string | null;
  serving_size_g: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number;
  source: string;
  image_url: string | null;
  created_at: string;
}

export interface MealItem {
  id: string;
  product_id: string;
  quantity_servings: number;
  quantity_grams: number | null;
  product: Product;
  created_at: string;
}

export interface Meal {
  id: string;
  user_id: string;
  meal_type: "breakfast" | "lunch" | "dinner" | "snack";
  meal_date: string;
  items: MealItem[];
  created_at: string;
}

export interface DailyNutrition {
  nutrition_date: string;
  total_calories: number;
  total_protein_g: number;
  total_carbs_g: number;
  total_fat_g: number;
  total_fiber_g: number;
  meals_count: number;
}

export interface NutritionGoal {
  daily_calories: number;
  daily_protein_g: number;
  daily_carbs_g: number;
  daily_fat_g: number;
}
