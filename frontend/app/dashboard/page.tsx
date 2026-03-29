"use client";

import CalorieTrendChart from "@/components/charts/CalorieTrendChart";
import MacroPieChart from "@/components/charts/MacroPieChart";
import NutrientBarChart from "@/components/charts/NutrientBarChart";
import { getDailyNutrition, getGoals, getWeeklyNutrition } from "@/lib/api";
import type { DailyNutrition, NutritionGoal } from "@/lib/types";
import { useEffect, useState } from "react";

export default function DashboardPage() {
  const [daily, setDaily] = useState<DailyNutrition | null>(null);
  const [weekly, setWeekly] = useState<DailyNutrition[]>([]);
  const [goals, setGoals] = useState<NutritionGoal>({
    daily_calories: 2000,
    daily_protein_g: 150,
    daily_carbs_g: 250,
    daily_fat_g: 65,
  });
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const today = new Date().toISOString().split("T")[0];
    const weekAgo = new Date(Date.now() - 6 * 86400000).toISOString().split("T")[0];

    Promise.all([
      getDailyNutrition(today),
      getWeeklyNutrition(weekAgo, today),
      getGoals(),
    ])
      .then(([d, w, g]) => {
        setDaily(d);
        setWeekly(w);
        setGoals(g);
      })
      .catch((err) => setError(err.message));
  }, []);

  const caloriePercent = daily
    ? Math.min(100, Math.round((daily.total_calories / goals.daily_calories) * 100))
    : 0;

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Dashboard</h1>

      {error && (
        <div className="p-3 bg-yellow-900/30 border border-yellow-700 rounded-lg text-yellow-300 text-sm">
          Could not load data: {error}
        </div>
      )}

      {/* Calorie progress */}
      <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
        <div className="flex justify-between items-baseline mb-2">
          <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide">
            Today&apos;s Calories
          </h2>
          <span className="text-2xl font-bold text-amber-400">
            {daily ? Math.round(daily.total_calories) : 0}
            <span className="text-sm text-gray-500 font-normal ml-1">
              / {goals.daily_calories} kcal
            </span>
          </span>
        </div>
        <div className="w-full h-3 bg-gray-700 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-amber-500 to-amber-400 rounded-full transition-all duration-500"
            style={{ width: `${caloriePercent}%` }}
          />
        </div>
      </div>

      {/* Macro donut */}
      <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
        <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide mb-2">
          Macro Breakdown
        </h2>
        <MacroPieChart
          protein={daily?.total_protein_g ?? 0}
          carbs={daily?.total_carbs_g ?? 0}
          fat={daily?.total_fat_g ?? 0}
        />
        <div className="flex justify-around text-xs text-gray-400 mt-2">
          <span>
            <span className="inline-block w-2 h-2 rounded-full bg-blue-500 mr-1" />
            P: {daily ? Math.round(daily.total_protein_g) : 0}g
          </span>
          <span>
            <span className="inline-block w-2 h-2 rounded-full bg-emerald-500 mr-1" />
            C: {daily ? Math.round(daily.total_carbs_g) : 0}g
          </span>
          <span>
            <span className="inline-block w-2 h-2 rounded-full bg-amber-500 mr-1" />
            F: {daily ? Math.round(daily.total_fat_g) : 0}g
          </span>
        </div>
      </div>

      {/* Weekly calorie trend */}
      {weekly.length > 0 && (
        <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
          <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide mb-3">
            Weekly Calorie Trend
          </h2>
          <CalorieTrendChart data={weekly} calorieGoal={goals.daily_calories} />
        </div>
      )}

      {/* Weekly nutrient bars */}
      {weekly.length > 0 && (
        <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
          <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide mb-3">
            Weekly Macros
          </h2>
          <NutrientBarChart data={weekly} />
        </div>
      )}
    </div>
  );
}
