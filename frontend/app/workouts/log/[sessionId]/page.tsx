"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { completeSession, getSession, logSet } from "@/lib/api";
import type { WorkoutSession, WorkoutSet as SetType } from "@/lib/types";

export default function WorkoutLogPage() {
  const params = useParams();
  const router = useRouter();
  const [session, setSession] = useState<WorkoutSession | null>(null);
  const [weight, setWeight] = useState("");
  const [reps, setReps] = useState("");
  const [currentExercise, setCurrentExercise] = useState("");
  const [setNumber, setSetNumber] = useState(1);
  const [restTime, setRestTime] = useState(0);
  const [restDuration, setRestDuration] = useState(90);
  const [isResting, setIsResting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const startTimeRef = useRef<number>(0);

  useEffect(() => {
    if (params.sessionId) {
      getSession(params.sessionId as string).then(s => {
        setSession(s);
        if (s.sets.length > 0) {
          const lastSet = s.sets[s.sets.length - 1];
          setCurrentExercise(lastSet.exercise_id);
          setWeight(String(lastSet.weight_kg || ""));
          setSetNumber(lastSet.set_number + 1);
        }
      }).catch(err => setError(err.message));
    }
  }, [params.sessionId]);

  const startRestTimer = useCallback(() => {
    setIsResting(true);
    startTimeRef.current = Date.now();
    setRestTime(restDuration);
    timerRef.current = setInterval(() => {
      const elapsed = Math.floor((Date.now() - startTimeRef.current) / 1000);
      const remaining = Math.max(0, restDuration - elapsed);
      setRestTime(remaining);
      if (remaining <= 0) {
        setIsResting(false);
        if (timerRef.current) clearInterval(timerRef.current);
        try { navigator.vibrate?.([200, 100, 200]); } catch {}
      }
    }, 250);
  }, [restDuration]);

  useEffect(() => {
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, []);

  const handleLogSet = async () => {
    if (!session || !currentExercise || !reps) return;
    try {
      const newSet = await logSet(session.id, {
        exercise_id: currentExercise,
        set_number: setNumber,
        reps: parseInt(reps),
        weight_kg: weight ? parseFloat(weight) : undefined,
      });
      setSession(prev => prev ? { ...prev, sets: [...prev.sets, newSet] } : null);
      setSetNumber(setNumber + 1);
      startRestTimer();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to log set");
    }
  };

  const handleComplete = async () => {
    if (!session) return;
    try {
      await completeSession(session.id);
      router.push("/workouts/history");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to complete session");
    }
  };

  if (!session) return <div className="text-center py-12 text-gray-500">Loading session...</div>;

  const uniqueExercises = Array.from(new Map(session.sets.map(s => [s.exercise_id, s.exercise])).values());

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h1 className="text-xl font-bold tracking-tight">Workout Log</h1>
        <button onClick={handleComplete} className="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-500">
          End Workout
        </button>
      </div>

      {error && <div className="p-3 bg-red-900/30 border border-red-700 rounded-lg text-red-300 text-sm">{error}</div>}

      {isResting && (
        <div className="bg-cyan-900/30 border border-cyan-700 rounded-xl p-5 text-center">
          <div className="text-4xl font-bold text-cyan-400 font-mono">{restTime}s</div>
          <div className="text-sm text-gray-400 mt-1">Rest Timer</div>
          <button onClick={() => { setIsResting(false); if (timerRef.current) clearInterval(timerRef.current); }}
            className="mt-3 px-4 py-1 text-sm bg-gray-700 rounded-lg text-gray-300 hover:bg-gray-600">Skip</button>
        </div>
      )}

      <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-4 space-y-3">
        <div>
          <label className="text-xs text-gray-400 block mb-1">Exercise</label>
          <select value={currentExercise} onChange={e => { setCurrentExercise(e.target.value); setSetNumber(1); }}
            className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm">
            <option value="">Select exercise...</option>
            {uniqueExercises.map(ex => (
              <option key={ex.id} value={ex.id}>{ex.name}</option>
            ))}
          </select>
        </div>

        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="text-xs text-gray-400 block mb-1">Set #</label>
            <input type="number" value={setNumber} onChange={e => setSetNumber(Number(e.target.value))}
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-center" />
          </div>
          <div>
            <label className="text-xs text-gray-400 block mb-1">Weight (kg)</label>
            <div className="flex gap-1">
              <button onClick={() => setWeight(String(Math.max(0, (parseFloat(weight) || 0) - 2.5)))} className="px-2 bg-gray-600 rounded text-white">-</button>
              <input type="number" value={weight} onChange={e => setWeight(e.target.value)} placeholder="0"
                className="w-full px-2 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-center" />
              <button onClick={() => setWeight(String((parseFloat(weight) || 0) + 2.5))} className="px-2 bg-gray-600 rounded text-white">+</button>
            </div>
          </div>
          <div>
            <label className="text-xs text-gray-400 block mb-1">Reps</label>
            <input type="number" value={reps} onChange={e => setReps(e.target.value)} placeholder="0"
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-center" />
          </div>
        </div>

        <div className="flex gap-2">
          <div className="flex-1">
            <label className="text-xs text-gray-400 block mb-1">Rest (sec)</label>
            <select value={restDuration} onChange={e => setRestDuration(Number(e.target.value))}
              className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm">
              <option value={60}>60s</option>
              <option value={90}>90s</option>
              <option value={120}>2 min</option>
              <option value={180}>3 min</option>
            </select>
          </div>
          <button onClick={handleLogSet} disabled={!currentExercise || !reps}
            className="flex-1 py-2 bg-emerald-600 text-white rounded-lg font-medium hover:bg-emerald-500 disabled:opacity-40 transition-colors self-end">
            Log Set
          </button>
        </div>
      </div>

      {session.sets.length > 0 && (
        <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-4">
          <h3 className="text-sm font-medium text-gray-400 mb-2">Logged Sets ({session.sets.length})</h3>
          <div className="space-y-1 max-h-60 overflow-y-auto">
            {[...session.sets].reverse().map(s => (
              <div key={s.id} className="flex justify-between text-sm py-1 border-b border-gray-700/50 last:border-0">
                <span className="text-gray-300">{s.exercise.name}</span>
                <span className="text-gray-400">
                  {s.weight_kg ? `${s.weight_kg}kg x ` : ""}{s.reps} reps
                  {s.is_pr && <span className="text-amber-400 ml-1 font-bold">PR!</span>}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
