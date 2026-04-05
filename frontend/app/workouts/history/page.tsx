"use client";

import { useEffect, useState } from "react";
import { getWorkoutHistory, getVolume } from "@/lib/api";
import type { WorkoutHistoryEntry, VolumeByMuscle } from "@/lib/types";

export default function WorkoutHistoryPage() {
  const [history, setHistory] = useState<WorkoutHistoryEntry[]>([]);
  const [volume, setVolume] = useState<VolumeByMuscle[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([getWorkoutHistory(), getVolume("week")])
      .then(([h, v]) => { setHistory(h); setVolume(v); })
      .catch(err => setError(err.message));
  }, []);

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Workout History</h1>
      {error && <div className="p-3 bg-yellow-900/30 border border-yellow-700 rounded-lg text-yellow-300 text-sm">{error}</div>}

      {volume.length > 0 && (
        <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5">
          <h2 className="text-sm font-medium text-gray-400 uppercase tracking-wide mb-3">Weekly Volume by Muscle</h2>
          <div className="space-y-2">
            {volume.map(v => {
              const maxVol = Math.max(...volume.map(x => x.total_volume));
              const pct = maxVol > 0 ? (v.total_volume / maxVol) * 100 : 0;
              return (
                <div key={v.muscle_group}>
                  <div className="flex justify-between text-sm mb-1">
                    <span className="text-gray-300 capitalize">{v.muscle_group}</span>
                    <span className="text-gray-500">{Math.round(v.total_volume)} kg | {v.total_sets} sets</span>
                  </div>
                  <div className="w-full h-2 bg-gray-700 rounded-full overflow-hidden">
                    <div className="h-full bg-cyan-500 rounded-full transition-all" style={{ width: `${pct}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {history.length === 0 ? (
        <div className="text-center py-12 text-gray-500">No workouts logged yet</div>
      ) : (
        <div className="space-y-3">
          {history.map(h => (
            <div key={h.id} className="bg-gray-800/50 border border-gray-700 rounded-xl p-4">
              <div className="flex justify-between items-start">
                <div>
                  <div className="font-medium">{h.program_name || "Free Workout"}</div>
                  {h.day_name && <div className="text-sm text-gray-400">{h.day_name}</div>}
                </div>
                <div className="text-right text-sm text-gray-400">
                  {new Date(h.started_at).toLocaleDateString("es")}
                </div>
              </div>
              <div className="flex gap-4 mt-2 text-xs text-gray-500">
                <span>{h.total_sets} sets</span>
                <span>{Math.round(h.total_volume)} kg volume</span>
                {h.duration_minutes && <span>{h.duration_minutes} min</span>}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
