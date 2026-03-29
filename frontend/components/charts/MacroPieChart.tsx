"use client";

import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";

interface MacroPieChartProps {
  protein: number;
  carbs: number;
  fat: number;
}

const COLORS = ["#3b82f6", "#10b981", "#f59e0b"]; // protein, carbs, fat

export default function MacroPieChart({ protein, carbs, fat }: MacroPieChartProps) {
  const data = [
    { name: "Protein", value: protein, unit: "g" },
    { name: "Carbs", value: carbs, unit: "g" },
    { name: "Fat", value: fat, unit: "g" },
  ];

  const total = protein + carbs + fat;
  if (total === 0) {
    return (
      <div className="flex items-center justify-center h-48 text-gray-500 text-sm">
        No macros logged yet
      </div>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={200}>
      <PieChart>
        <Pie
          data={data}
          cx="50%"
          cy="50%"
          innerRadius={50}
          outerRadius={80}
          paddingAngle={3}
          dataKey="value"
          strokeWidth={0}
        >
          {data.map((_, i) => (
            <Cell key={i} fill={COLORS[i]} />
          ))}
        </Pie>
        <Tooltip
          formatter={(value: number, name: string) => [`${value.toFixed(1)}g`, name]}
          contentStyle={{
            backgroundColor: "#1f2937",
            border: "none",
            borderRadius: "8px",
            color: "#e5e7eb",
          }}
        />
      </PieChart>
    </ResponsiveContainer>
  );
}
