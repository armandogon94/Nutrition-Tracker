"use client";

import MealCard from "@/components/meals/MealCard";
import { getMealsByDate, removeMealItem } from "@/lib/api";
import type { Meal } from "@/lib/types";
import { useEffect, useState } from "react";

export default function MealsPage() {
  const [meals, setMeals] = useState<Meal[]>([]);
  const [date, setDate] = useState(new Date().toISOString().split("T")[0]);
  const [error, setError] = useState<string | null>(null);

  const fetchMeals = async () => {
    try {
      const data = await getMealsByDate(date);
      setMeals(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load meals");
    }
  };

  useEffect(() => {
    fetchMeals();
  }, [date]);

  const handleRemoveItem = async (mealId: string, itemId: string) => {
    try {
      await removeMealItem(mealId, itemId);
      await fetchMeals();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to remove item");
    }
  };

  const totalCalories = meals.reduce(
    (sum, meal) =>
      sum +
      meal.items.reduce(
        (s, item) => s + item.product.calories * item.quantity_servings,
        0
      ),
    0
  );

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold tracking-tight">Meals</h1>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="px-3 py-1.5 bg-gray-800 border border-gray-700 rounded-lg text-white text-sm"
        />
      </div>

      {error && (
        <div className="p-3 bg-yellow-900/30 border border-yellow-700 rounded-lg text-yellow-300 text-sm">
          {error}
        </div>
      )}

      <div className="text-right text-sm text-gray-400">
        Total: <span className="text-amber-400 font-medium">{Math.round(totalCalories)} kcal</span>
      </div>

      {meals.length === 0 ? (
        <div className="text-center py-12 text-gray-500">
          <p>No meals logged for this date</p>
          <p className="text-sm mt-1">Scan a barcode to get started</p>
        </div>
      ) : (
        <div className="space-y-4">
          {meals.map((meal) => (
            <MealCard key={meal.id} meal={meal} onRemoveItem={handleRemoveItem} />
          ))}
        </div>
      )}
    </div>
  );
}
