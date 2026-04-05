"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { getProgram, startSession } from "@/lib/api";
import type { WorkoutProgram } from "@/lib/types";

export default function ProgramDetailPage() {
  const params = useParams();
  const router = useRouter();
  const [program, setProgram] = useState<WorkoutProgram | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (params.programId) {
      getProgram(params.programId as string).then(setProgram).catch(err => setError(err.message));
    }
  }, [params.programId]);

  const handleStartDay = async (dayId: string) => {
    if (!program) return;
    try {
      const session = await startSession({
        program_id: program.id,
        program_day_id: dayId,
        started_at: new Date().toISOString(),
      });
      router.push(`/workouts/log/${session.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to start session");
    }
  };

  if (!program) return <div className="text-center py-12 text-gray-500">Loading...</div>;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{program.name}</h1>
        {program.description && <p className="text-sm text-gray-400 mt-2">{program.description}</p>}
        <div className="flex gap-4 mt-2 text-xs text-gray-500">
          <span>{program.days_per_week} days/week</span>
          <span className="capitalize">{program.difficulty}</span>
        </div>
      </div>

      {error && <div className="p-3 bg-red-900/30 border border-red-700 rounded-lg text-red-300 text-sm">{error}</div>}

      <div className="space-y-3">
        {program.days.map(day => (
          <div key={day.id} className="bg-gray-800/50 border border-gray-700 rounded-xl p-4">
            <div className="flex justify-between items-center mb-3">
              <div>
                <h3 className="font-semibold">Day {day.day_number}{day.day_name ? `: ${day.day_name}` : ""}</h3>
                {day.focus && <p className="text-xs text-gray-400">{day.focus}</p>}
              </div>
              <button onClick={() => handleStartDay(day.id)}
                className="px-4 py-2 bg-emerald-600 text-white text-sm rounded-lg hover:bg-emerald-500 transition-colors">
                Start
              </button>
            </div>
            {day.exercises.length > 0 && (
              <ul className="space-y-1">
                {day.exercises.map(ex => (
                  <li key={ex.id} className="text-sm text-gray-300 flex justify-between">
                    <span>{ex.exercise.name}</span>
                    <span className="text-gray-500">{ex.set_count}x{ex.rep_min}{ex.rep_max && ex.rep_max !== ex.rep_min ? `-${ex.rep_max}` : ""}</span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
