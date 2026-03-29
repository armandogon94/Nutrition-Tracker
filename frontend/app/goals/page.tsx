"use client";

import { getGoals, updateGoals } from "@/lib/api";
import type { NutritionGoal } from "@/lib/types";
import { useEffect, useState } from "react";

export default function GoalsPage() {
  const [goals, setGoals] = useState<NutritionGoal>({
    daily_calories: 2000,
    daily_protein_g: 150,
    daily_carbs_g: 250,
    daily_fat_g: 65,
  });
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getGoals()
      .then(setGoals)
      .catch((err) => setError(err.message));
  }, []);

  const handleSave = async () => {
    try {
      const updated = await updateGoals(goals);
      setGoals(updated);
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save goals");
    }
  };

  const fields: { key: keyof NutritionGoal; label: string; unit: string }[] = [
    { key: "daily_calories", label: "Daily Calories", unit: "kcal" },
    { key: "daily_protein_g", label: "Protein", unit: "g" },
    { key: "daily_carbs_g", label: "Carbs", unit: "g" },
    { key: "daily_fat_g", label: "Fat", unit: "g" },
  ];

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Nutrition Goals</h1>

      {error && (
        <div className="p-3 bg-yellow-900/30 border border-yellow-700 rounded-lg text-yellow-300 text-sm">
          {error}
        </div>
      )}

      <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5 space-y-4">
        {fields.map(({ key, label, unit }) => (
          <div key={key}>
            <label className="flex justify-between text-sm mb-1">
              <span className="text-gray-300">{label}</span>
              <span className="text-gray-500">{unit}</span>
            </label>
            <input
              type="number"
              value={goals[key]}
              onChange={(e) =>
                setGoals({ ...goals, [key]: Number(e.target.value) })
              }
              className="w-full px-4 py-2.5 bg-gray-700 border border-gray-600 rounded-lg text-white focus:outline-none focus:border-cyan-500 transition-colors"
            />
          </div>
        ))}

        <button
          onClick={handleSave}
          className="w-full py-3 bg-cyan-600 text-white rounded-xl font-medium hover:bg-cyan-500 transition-colors"
        >
          {saved ? "Saved!" : "Save Goals"}
        </button>
      </div>
    </div>
  );
}
