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

export interface UserProfile {
  weight_kg: number;
  height_cm: number;
  age: number;
  sex: string;
  activity_level: string;
  bmr: number | null;
  tdee: number | null;
  goal_preset: string | null;
  daily_calories: number | null;
  daily_protein_g: number | null;
  daily_carbs_g: number | null;
  daily_fat_g: number | null;
}

export interface TDEEResult {
  bmr: number;
  tdee: number;
  activity_level: string;
  goal_preset: string | null;
  daily_calories: number;
  daily_protein_g: number;
  daily_carbs_g: number;
  daily_fat_g: number;
}

export interface MealPlanItem {
  id: string;
  product_id: string;
  day_of_week: number;
  meal_type: string;
  quantity_servings: number;
  quantity_grams: number | null;
  product: Product;
  created_at: string;
}

export interface MealPlanType {
  id: string;
  user_id: string;
  name: string;
  week_start_date: string;
  notes: string | null;
  is_template: boolean;
  items: MealPlanItem[];
  created_at: string;
}

export interface ShoppingListItemType {
  id: string;
  ingredient_name: string;
  quantity: number;
  unit: string | null;
  category: string | null;
  is_checked: boolean;
}

export interface ShoppingListType {
  id: string;
  name: string | null;
  meal_plan_id: string | null;
  items: ShoppingListItemType[];
  generated_at: string;
}

export interface Exercise {
  id: string;
  name: string;
  primary_muscle: string;
  secondary_muscles: string | null;
  equipment: string | null;
  difficulty: string | null;
  instructions: string | null;
  video_url: string | null;
  category: string | null;
}

export interface WorkoutProgramExercise {
  id: string;
  exercise: Exercise;
  set_count: number;
  rep_min: number | null;
  rep_max: number | null;
  rest_seconds: number | null;
  exercise_order: number;
  notes: string | null;
}

export interface WorkoutProgramDay {
  id: string;
  day_number: number;
  day_name: string | null;
  focus: string | null;
  description: string | null;
  exercises: WorkoutProgramExercise[];
}

export interface WorkoutProgram {
  id: string;
  name: string;
  description: string | null;
  program_type: string | null;
  days_per_week: number;
  difficulty: string | null;
  is_preset: boolean;
  days: WorkoutProgramDay[];
}

export interface WorkoutSet {
  id: string;
  exercise_id: string;
  exercise: Exercise;
  set_number: number;
  reps: number;
  weight_kg: number | null;
  rpe: number | null;
  is_pr: boolean;
  completed_at: string;
}

export interface WorkoutSession {
  id: string;
  user_id: string;
  program_id: string | null;
  program_day_id: string | null;
  started_at: string;
  completed_at: string | null;
  duration_minutes: number | null;
  notes: string | null;
  sets: WorkoutSet[];
}

export interface WorkoutHistoryEntry {
  id: string;
  started_at: string;
  completed_at: string | null;
  duration_minutes: number | null;
  program_name: string | null;
  day_name: string | null;
  total_sets: number;
  total_volume: number;
}

export interface VolumeByMuscle {
  muscle_group: string;
  total_volume: number;
  total_sets: number;
}

export interface AuthUser {
  id: string;
  email: string;
  display_name: string;
}

export interface AuthResponse {
  access_token: string;
  token_type: string;
  user: AuthUser;
}
