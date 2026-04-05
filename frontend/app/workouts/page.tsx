"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getPrograms } from "@/lib/api";
import type { WorkoutProgram } from "@/lib/types";

const DIFFICULTY_COLORS: Record<string, string> = {
  beginner: "text-emerald-400",
  intermediate: "text-amber-400",
  advanced: "text-red-400",
};

export default function WorkoutsPage() {
  const [programs, setPrograms] = useState<WorkoutProgram[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    getPrograms().then(setPrograms).catch(err => setError(err.message));
  }, []);

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-2xl font-bold tracking-tight">Workouts</h1>
        <Link href="/workouts/history" className="text-sm text-cyan-400 hover:text-cyan-300">History</Link>
      </div>

      {error && <div className="p-3 bg-yellow-900/30 border border-yellow-700 rounded-lg text-yellow-300 text-sm">{error}</div>}

      {programs.length === 0 ? (
        <div className="text-center py-12 text-gray-500">
          <p>No workout programs available</p>
          <p className="text-sm mt-1">Seed the database with exercise data to get started</p>
        </div>
      ) : (
        <div className="space-y-3">
          {programs.map(prog => (
            <Link key={prog.id} href={`/workouts/${prog.id}`}
              className="block bg-gray-800/50 border border-gray-700 rounded-xl p-4 hover:border-gray-600 transition-colors">
              <div className="flex justify-between items-start">
                <div>
                  <h3 className="font-semibold text-lg">{prog.name}</h3>
                  {prog.description && <p className="text-sm text-gray-400 mt-1 line-clamp-2">{prog.description}</p>}
                </div>
                <span className={`text-xs font-medium ${DIFFICULTY_COLORS[prog.difficulty || ""] || "text-gray-400"}`}>
                  {prog.difficulty}
                </span>
              </div>
              <div className="flex gap-4 mt-3 text-xs text-gray-500">
                <span>{prog.days_per_week} days/week</span>
                {prog.program_type && <span className="uppercase">{prog.program_type}</span>}
              </div>
            </Link>
          ))}
        </div>
      )}

      <Link href="/exercises"
        className="block text-center py-3 bg-gray-800 border border-gray-700 rounded-xl text-gray-400 hover:text-white hover:border-gray-600 transition-colors">
        Browse Exercise Database
      </Link>
    </div>
  );
}
