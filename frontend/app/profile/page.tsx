"use client";

import { useEffect, useState } from "react";
import { createProfile, getTDEE, setGoalPreset } from "@/lib/api";
import type { TDEEResult } from "@/lib/types";

const ACTIVITY_LEVELS = [
  { value: "sedentary", label: "Sedentary", desc: "Desk job, no exercise" },
  { value: "light", label: "Lightly Active", desc: "1-3 days/week" },
  { value: "moderate", label: "Moderately Active", desc: "3-5 days/week" },
  { value: "active", label: "Very Active", desc: "6-7 days/week" },
  { value: "very_active", label: "Extra Active", desc: "2x daily training" },
];

const GOALS = [
  { value: "fat_loss", label: "Fat Loss", desc: "-500 kcal/day", color: "text-red-400" },
  { value: "maintenance", label: "Maintenance", desc: "TDEE", color: "text-cyan-400" },
  { value: "lean_bulk", label: "Lean Bulk", desc: "+250 kcal/day", color: "text-emerald-400" },
  { value: "muscle_gain", label: "Muscle Gain", desc: "+500 kcal/day", color: "text-amber-400" },
];

export default function ProfilePage() {
  const [weight, setWeight] = useState(75);
  const [height, setHeight] = useState(175);
  const [age, setAge] = useState(28);
  const [sex, setSex] = useState("male");
  const [activity, setActivity] = useState("moderate");
  const [tdee, setTdee] = useState<TDEEResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    getTDEE().then(setTdee).catch(() => {});
  }, []);

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    try {
      await createProfile({ weight_kg: weight, height_cm: height, age, sex, activity_level: activity });
      const result = await getTDEE();
      setTdee(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save profile");
    } finally {
      setSaving(false);
    }
  };

  const handleGoal = async (goal: string) => {
    try {
      const result = await setGoalPreset(goal);
      setTdee(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to set goal");
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Profile & TDEE</h1>
      {error && <div className="p-3 bg-red-900/30 border border-red-700 rounded-lg text-red-300 text-sm">{error}</div>}

      <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5 space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="text-xs text-gray-400 block mb-1">Weight (kg)</label>
            <input type="number" value={weight} onChange={e => setWeight(Number(e.target.value))}
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white" />
          </div>
          <div>
            <label className="text-xs text-gray-400 block mb-1">Height (cm)</label>
            <input type="number" value={height} onChange={e => setHeight(Number(e.target.value))}
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white" />
          </div>
          <div>
            <label className="text-xs text-gray-400 block mb-1">Age</label>
            <input type="number" value={age} onChange={e => setAge(Number(e.target.value))}
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white" />
          </div>
          <div>
            <label className="text-xs text-gray-400 block mb-1">Sex</label>
            <select value={sex} onChange={e => setSex(e.target.value)}
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white">
              <option value="male">Male</option>
              <option value="female">Female</option>
            </select>
          </div>
        </div>

        <div>
          <label className="text-xs text-gray-400 block mb-2">Activity Level</label>
          <div className="space-y-2">
            {ACTIVITY_LEVELS.map(al => (
              <button key={al.value} onClick={() => setActivity(al.value)}
                className={`w-full text-left px-4 py-2 rounded-lg border transition-colors ${activity === al.value ? "border-cyan-500 bg-cyan-500/10" : "border-gray-600 bg-gray-700/50 hover:border-gray-500"}`}>
                <span className="text-white text-sm font-medium">{al.label}</span>
                <span className="text-gray-400 text-xs ml-2">{al.desc}</span>
              </button>
            ))}
          </div>
        </div>

        <button onClick={handleSave} disabled={saving}
          className="w-full py-3 bg-cyan-600 text-white rounded-xl font-medium hover:bg-cyan-500 disabled:opacity-40 transition-colors">
          {saving ? "Saving..." : "Calculate TDEE"}
        </button>
      </div>

      {tdee && (
        <>
          <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
            <div className="grid grid-cols-2 gap-4 text-center">
              <div>
                <div className="text-2xl font-bold text-cyan-400">{Math.round(tdee.bmr)}</div>
                <div className="text-xs text-gray-400">BMR (kcal/day)</div>
              </div>
              <div>
                <div className="text-2xl font-bold text-amber-400">{Math.round(tdee.tdee)}</div>
                <div className="text-xs text-gray-400">TDEE (kcal/day)</div>
              </div>
            </div>
          </div>

          <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5 space-y-3">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide">Goal</h2>
            <div className="grid grid-cols-2 gap-2">
              {GOALS.map(g => (
                <button key={g.value} onClick={() => handleGoal(g.value)}
                  className={`px-3 py-3 rounded-lg border text-left transition-colors ${tdee.goal_preset === g.value ? "border-cyan-500 bg-cyan-500/10" : "border-gray-600 bg-gray-700/50 hover:border-gray-500"}`}>
                  <div className={`text-sm font-medium ${g.color}`}>{g.label}</div>
                  <div className="text-xs text-gray-500">{g.desc}</div>
                </button>
              ))}
            </div>
          </div>

          <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
            <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide mb-3">Daily Targets</h2>
            <div className="grid grid-cols-4 gap-2 text-center">
              <div className="bg-gray-700/50 rounded-lg p-3">
                <div className="text-lg font-bold text-amber-400">{tdee.daily_calories}</div>
                <div className="text-xs text-gray-500">kcal</div>
              </div>
              <div className="bg-gray-700/50 rounded-lg p-3">
                <div className="text-lg font-bold text-blue-400">{tdee.daily_protein_g}g</div>
                <div className="text-xs text-gray-500">Protein</div>
              </div>
              <div className="bg-gray-700/50 rounded-lg p-3">
                <div className="text-lg font-bold text-emerald-400">{tdee.daily_carbs_g}g</div>
                <div className="text-xs text-gray-500">Carbs</div>
              </div>
              <div className="bg-gray-700/50 rounded-lg p-3">
                <div className="text-lg font-bold text-amber-400">{tdee.daily_fat_g}g</div>
                <div className="text-xs text-gray-500">Fat</div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
