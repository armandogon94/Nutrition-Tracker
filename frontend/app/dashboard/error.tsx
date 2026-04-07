'use client';

export default function DashboardError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[50vh] gap-4 px-4">
      <h2 className="text-xl font-bold text-red-400">Dashboard Error</h2>
      <p className="text-gray-400 text-center">{error.message || 'Unknown error'}</p>
      <pre className="text-xs text-gray-500 max-w-full overflow-x-auto bg-gray-800 p-3 rounded-lg whitespace-pre-wrap break-all">
        {error.stack || 'No stack trace'}
      </pre>
      <button onClick={reset} className="px-4 py-2 bg-cyan-600 text-white rounded hover:bg-cyan-700">
        Try Again
      </button>
    </div>
  );
}
