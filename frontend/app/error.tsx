'use client';

export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[50vh] gap-4 px-4">
      <h2 className="text-xl font-bold text-red-400">Something went wrong</h2>
      <p className="text-gray-400 text-center">{error.message}</p>
      <button onClick={reset} className="px-4 py-2 bg-cyan-600 text-white rounded hover:bg-cyan-700">
        Try Again
      </button>
    </div>
  );
}
