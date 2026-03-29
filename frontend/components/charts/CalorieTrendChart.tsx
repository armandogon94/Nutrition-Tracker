"use client";

import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { DailyNutrition } from "@/lib/types";

interface CalorieTrendChartProps {
  data: DailyNutrition[];
  calorieGoal: number;
}

export default function CalorieTrendChart({ data, calorieGoal }: CalorieTrendChartProps) {
  const chartData = data.map((d) => ({
    date: new Date(d.nutrition_date).toLocaleDateString("es", { weekday: "short" }),
    calories: Math.round(d.total_calories),
  }));

  return (
    <ResponsiveContainer width="100%" height={250}>
      <LineChart data={chartData} margin={{ top: 5, right: 10, left: -10, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis dataKey="date" stroke="#9ca3af" fontSize={12} />
        <YAxis stroke="#9ca3af" fontSize={12} />
        <Tooltip
          contentStyle={{
            backgroundColor: "#1f2937",
            border: "none",
            borderRadius: "8px",
            color: "#e5e7eb",
          }}
          formatter={(value: number) => [`${value} kcal`, "Calories"]}
        />
        <ReferenceLine
          y={calorieGoal}
          stroke="#22d3ee"
          strokeDasharray="5 5"
          label={{ value: "Goal", fill: "#22d3ee", fontSize: 11 }}
        />
        <Line
          type="monotone"
          dataKey="calories"
          stroke="#f59e0b"
          strokeWidth={2}
          dot={{ fill: "#f59e0b", r: 4 }}
          activeDot={{ r: 6 }}
        />
      </LineChart>
    </ResponsiveContainer>
  );
}
