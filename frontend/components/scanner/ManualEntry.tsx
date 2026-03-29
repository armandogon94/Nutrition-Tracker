"use client";

import { useState } from "react";

interface ManualEntryProps {
  onSubmit: (barcode: string) => void;
  isLoading?: boolean;
}

export default function ManualEntry({ onSubmit, isLoading }: ManualEntryProps) {
  const [barcode, setBarcode] = useState("");

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = barcode.trim();
    if (trimmed) {
      onSubmit(trimmed);
      setBarcode("");
    }
  };

  return (
    <form onSubmit={handleSubmit} className="flex gap-2">
      <input
        type="text"
        inputMode="numeric"
        pattern="[0-9]*"
        placeholder="Enter barcode number..."
        value={barcode}
        onChange={(e) => setBarcode(e.target.value)}
        className="flex-1 px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl text-white placeholder-gray-500 focus:outline-none focus:border-cyan-500 transition-colors"
        disabled={isLoading}
      />
      <button
        type="submit"
        disabled={!barcode.trim() || isLoading}
        className="px-6 py-3 bg-cyan-600 text-white rounded-xl font-medium hover:bg-cyan-500 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
      >
        {isLoading ? "..." : "Search"}
      </button>
    </form>
  );
}
