"use client";

import type { Meal } from "@/lib/types";

const MEAL_LABELS: Record<string, string> = {
  breakfast: "Desayuno",
  lunch: "Almuerzo",
  dinner: "Cena",
  snack: "Snack",
};

interface MealCardProps {
  meal: Meal;
  onRemoveItem?: (mealId: string, itemId: string) => void;
}

export default function MealCard({ meal, onRemoveItem }: MealCardProps) {
  const totalCalories = meal.items.reduce(
    (sum, item) => sum + item.product.calories * item.quantity_servings,
    0
  );

  return (
    <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-4">
      <div className="flex justify-between items-center mb-3">
        <h3 className="font-semibold text-lg">
          {MEAL_LABELS[meal.meal_type] || meal.meal_type}
        </h3>
        <span className="text-amber-400 font-medium">
          {Math.round(totalCalories)} kcal
        </span>
      </div>

      {meal.items.length === 0 ? (
        <p className="text-sm text-gray-500">No items yet</p>
      ) : (
        <ul className="space-y-2">
          {meal.items.map((item) => (
            <li
              key={item.id}
              className="flex justify-between items-center text-sm"
            >
              <div>
                <span className="text-gray-200">{item.product.name}</span>
                {item.quantity_servings !== 1 && (
                  <span className="text-gray-500 ml-1">
                    x{item.quantity_servings}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-3">
                <span className="text-gray-400">
                  {Math.round(item.product.calories * item.quantity_servings)} kcal
                </span>
                {onRemoveItem && (
                  <button
                    onClick={() => onRemoveItem(meal.id, item.id)}
                    className="text-red-400 hover:text-red-300 text-xs"
                  >
                    Remove
                  </button>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
