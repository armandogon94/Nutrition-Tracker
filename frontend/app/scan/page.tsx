"use client";

import dynamic from "next/dynamic";
import { useState } from "react";
import { useRouter } from "next/navigation";
import ManualEntry from "@/components/scanner/ManualEntry";
import { addMealItem, createMeal, searchProduct } from "@/lib/api";
import type { Product } from "@/lib/types";

// Must use dynamic import with ssr: false — html5-qrcode accesses window at import time
const BarcodeScanner = dynamic(
  () => import("@/components/scanner/BarcodeScanner"),
  { ssr: false }
);

const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack"] as const;

export default function ScanPage() {
  const router = useRouter();
  const [product, setProduct] = useState<Product | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [selectedMeal, setSelectedMeal] = useState<string>("lunch");
  const [servings, setServings] = useState(1);
  const [scanKey, setScanKey] = useState(0);

  const handleBarcode = async (barcode: string) => {
    setIsLoading(true);
    setError(null);
    setProduct(null);
    setSuccess(null);

    try {
      console.log("[scan] Looking up barcode:", barcode);
      const found = await searchProduct(barcode);
      console.log("[scan] Product found:", JSON.stringify(found));
      setProduct(found);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error("[scan] Error:", msg, err);
      setError(`Product not found for barcode: ${barcode}. ${msg}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleAddToMeal = async () => {
    if (!product) return;
    setIsLoading(true);
    try {
      const today = new Date().toISOString().split("T")[0];
      console.log("[scan] Creating meal:", selectedMeal, today);
      const meal = await createMeal(selectedMeal, today);
      console.log("[scan] Meal created:", JSON.stringify(meal));
      await addMealItem(meal.id, product.id, servings);
      setSuccess(`Added ${product.name} to ${selectedMeal}!`);
      setProduct(null);
      setServings(1);
    } catch (err) {
      const msg = err instanceof Error ? `${err.message}\n${err.stack}` : String(err);
      console.error("[scan] Add to meal error:", msg);
      setError(err instanceof Error ? err.message : "Failed to add to meal");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Scan Food</h1>

      {/* Camera scanner */}
      <BarcodeScanner key={scanKey} onScan={handleBarcode} />

      {/* Manual entry fallback */}
      <div>
        <p className="text-xs text-gray-500 mb-2 uppercase tracking-wide">
          Or enter barcode manually
        </p>
        <ManualEntry onSubmit={handleBarcode} isLoading={isLoading} />
      </div>

      {/* Status messages */}
      {isLoading && (
        <div className="text-center text-cyan-400 animate-pulse">
          Searching...
        </div>
      )}
      {error && (
        <div className="p-3 bg-red-900/30 border border-red-700 rounded-lg text-red-300 text-sm">
          <p>{error}</p>
          <div className="flex gap-3 mt-3">
            <button
              onClick={() => { setError(null); setScanKey(k => k + 1); }}
              className="px-4 py-2 bg-cyan-600 text-white rounded-lg text-sm font-medium hover:bg-cyan-500 transition-colors"
            >
              Try Again
            </button>
            <button
              onClick={() => router.push("/dashboard")}
              className="px-4 py-2 bg-gray-700 text-gray-300 rounded-lg text-sm font-medium hover:bg-gray-600 transition-colors"
            >
              Go to Dashboard
            </button>
          </div>
        </div>
      )}
      {success && (
        <div className="p-3 bg-emerald-900/30 border border-emerald-700 rounded-lg text-emerald-300 text-sm">
          <p>{success}</p>
          <div className="flex gap-3 mt-3">
            <button
              onClick={() => { setSuccess(null); setScanKey(k => k + 1); }}
              className="px-4 py-2 bg-cyan-600 text-white rounded-lg text-sm font-medium hover:bg-cyan-500 transition-colors"
            >
              Scan Another
            </button>
            <button
              onClick={() => router.push("/dashboard")}
              className="px-4 py-2 bg-gray-700 text-gray-300 rounded-lg text-sm font-medium hover:bg-gray-600 transition-colors"
            >
              Go to Dashboard
            </button>
          </div>
        </div>
      )}

      {/* Product result */}
      {product && (
        <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-5 space-y-4">
          <div className="flex gap-4">
            {product.image_url && (
              <img
                src={product.image_url}
                alt={product.name}
                className="w-20 h-20 object-cover rounded-lg"
              />
            )}
            <div>
              <h2 className="font-semibold text-lg">{product.name}</h2>
              {product.brand && (
                <p className="text-sm text-gray-400">{product.brand}</p>
              )}
              <p className="text-xs text-gray-500 mt-1">
                Source: {product.source} | {product.serving_size_g}g serving
              </p>
            </div>
          </div>

          {/* Nutrition info */}
          <div className="grid grid-cols-4 gap-2 text-center text-sm">
            <div className="bg-gray-700/50 rounded-lg p-2">
              <div className="text-amber-400 font-bold">
                {Math.round(product.calories ?? 0)}
              </div>
              <div className="text-xs text-gray-500">kcal</div>
            </div>
            <div className="bg-gray-700/50 rounded-lg p-2">
              <div className="text-blue-400 font-bold">
                {(product.protein_g ?? 0).toFixed(1)}g
              </div>
              <div className="text-xs text-gray-500">Protein</div>
            </div>
            <div className="bg-gray-700/50 rounded-lg p-2">
              <div className="text-emerald-400 font-bold">
                {(product.carbs_g ?? 0).toFixed(1)}g
              </div>
              <div className="text-xs text-gray-500">Carbs</div>
            </div>
            <div className="bg-gray-700/50 rounded-lg p-2">
              <div className="text-amber-400 font-bold">
                {(product.fat_g ?? 0).toFixed(1)}g
              </div>
              <div className="text-xs text-gray-500">Fat</div>
            </div>
          </div>

          {/* Add to meal */}
          <div className="flex gap-2 items-end">
            <div className="flex-1">
              <label className="text-xs text-gray-500 block mb-1">Meal</label>
              <select
                value={selectedMeal}
                onChange={(e) => setSelectedMeal(e.target.value)}
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
              >
                {MEAL_TYPES.map((t) => (
                  <option key={t} value={t}>
                    {t.charAt(0).toUpperCase() + t.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            <div className="w-20">
              <label className="text-xs text-gray-500 block mb-1">
                Servings
              </label>
              <input
                type="number"
                min="0.25"
                step="0.25"
                value={servings}
                onChange={(e) => setServings(Number(e.target.value))}
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm text-center"
              />
            </div>
            <button
              onClick={handleAddToMeal}
              disabled={isLoading}
              className="px-5 py-2 bg-emerald-600 text-white rounded-lg font-medium hover:bg-emerald-500 disabled:opacity-40 transition-colors"
            >
              Add
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
