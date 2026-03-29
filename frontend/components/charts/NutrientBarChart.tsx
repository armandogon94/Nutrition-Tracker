"use client";

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { DailyNutrition } from "@/lib/types";

interface NutrientBarChartProps {
  data: DailyNutrition[];
}

export default function NutrientBarChart({ data }: NutrientBarChartProps) {
  const chartData = data.map((d) => ({
    date: new Date(d.nutrition_date).toLocaleDateString("es", { weekday: "short" }),
    Protein: Math.round(d.total_protein_g),
    Carbs: Math.round(d.total_carbs_g),
    Fat: Math.round(d.total_fat_g),
  }));

  return (
    <ResponsiveContainer width="100%" height={250}>
      <BarChart data={chartData} margin={{ top: 5, right: 10, left: -10, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
        <XAxis dataKey="date" stroke="#9ca3af" fontSize={12} />
        <YAxis stroke="#9ca3af" fontSize={12} unit="g" />
        <Tooltip
          contentStyle={{
            backgroundColor: "#1f2937",
            border: "none",
            borderRadius: "8px",
            color: "#e5e7eb",
          }}
          formatter={(value: number) => [`${value}g`]}
        />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        <Bar dataKey="Protein" fill="#3b82f6" radius={[4, 4, 0, 0]} />
        <Bar dataKey="Carbs" fill="#10b981" radius={[4, 4, 0, 0]} />
        <Bar dataKey="Fat" fill="#f59e0b" radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}
