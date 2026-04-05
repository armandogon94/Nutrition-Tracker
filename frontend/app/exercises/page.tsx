"use client";

import { useEffect, useState, useRef } from "react";
import { getExercises } from "@/lib/api";
import type { Exercise } from "@/lib/types";

const MUSCLES = ["chest", "back", "shoulders", "legs", "arms", "core"];
const DIFFICULTIES = ["beginner", "intermediate", "advanced"];

export default function ExercisesPage() {
  const [exercises, setExercises] = useState<Exercise[]>([]);
  const [total, setTotal] = useState(0);
  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [muscle, setMuscle] = useState("");
  const [difficulty, setDifficulty] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(debounceRef.current);
  }, [search]);

  useEffect(() => {
    setLoading(true);
    setError("");
    getExercises({ q: debouncedSearch || undefined, muscle: muscle || undefined, difficulty: difficulty || undefined, limit: 50 })
      .then(data => { setExercises(data.exercises); setTotal(data.total); })
      .catch(err => setError(err.message))
      .finally(() => setLoading(false));
  }, [debouncedSearch, muscle, difficulty]);

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold tracking-tight">Exercises ({total})</h1>

      <input type="text" placeholder="Search exercises..." value={search} onChange={e => setSearch(e.target.value)}
        className="w-full px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl text-white placeholder-gray-500 focus:outline-none focus:border-cyan-500" />

      <div className="flex gap-2 overflow-x-auto pb-1">
        <button onClick={() => setMuscle("")}
          className={`px-3 py-1 rounded-full text-xs whitespace-nowrap ${!muscle ? "bg-cyan-600 text-white" : "bg-gray-700 text-gray-400"}`}>All</button>
        {MUSCLES.map(m => (
          <button key={m} onClick={() => setMuscle(m === muscle ? "" : m)}
            className={`px-3 py-1 rounded-full text-xs capitalize whitespace-nowrap ${muscle === m ? "bg-cyan-600 text-white" : "bg-gray-700 text-gray-400"}`}>{m}</button>
        ))}
      </div>

      <div className="flex gap-2 overflow-x-auto pb-1">
        {DIFFICULTIES.map(d => (
          <button key={d} onClick={() => setDifficulty(d === difficulty ? "" : d)}
            className={`px-3 py-1 rounded-full text-xs capitalize whitespace-nowrap ${difficulty === d ? "bg-amber-600 text-white" : "bg-gray-700 text-gray-400"}`}>{d}</button>
        ))}
      </div>

      {error && <p className="text-red-400 text-sm">{error}</p>}
      {loading && <p className="text-gray-400 text-sm">Loading exercises...</p>}
      {!loading && !error && exercises.length === 0 && (
        <p className="text-gray-400 text-center py-8">No exercises found. Try a different search or filter.</p>
      )}
      <div className="space-y-2">
        {exercises.map(ex => (
          <div key={ex.id} className="bg-gray-800/50 border border-gray-700 rounded-xl overflow-hidden">
            <button onClick={() => setExpanded(expanded === ex.id ? null : ex.id)}
              className="w-full text-left p-4 flex justify-between items-center">
              <div>
                <div className="font-medium">{ex.name}</div>
                <div className="text-xs text-gray-400 capitalize">{ex.primary_muscle} | {ex.equipment || "Bodyweight"} | {ex.difficulty}</div>
              </div>
              <span className="text-gray-500">{expanded === ex.id ? "\u2212" : "+"}</span>
            </button>
            {expanded === ex.id && (
              <div className="px-4 pb-4 pt-0 border-t border-gray-700/50">
                {ex.secondary_muscles && <p className="text-xs text-gray-400 mb-2">Secondary: {ex.secondary_muscles}</p>}
                {ex.instructions && <p className="text-sm text-gray-300">{ex.instructions}</p>}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
