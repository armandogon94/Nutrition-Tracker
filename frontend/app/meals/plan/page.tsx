"use client";

import { useEffect, useState } from "react";
import { createMealPlan, getMealPlans, getMealPlan, addMealPlanItem, removeMealPlanItem, searchProduct, generateShoppingList } from "@/lib/api";
import type { MealPlanType, ShoppingListType } from "@/lib/types";

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack"];

export default function MealPlanPage() {
  const [plans, setPlans] = useState<MealPlanType[]>([]);
  const [activePlan, setActivePlan] = useState<MealPlanType | null>(null);
  const [newPlanName, setNewPlanName] = useState("");
  const [barcode, setBarcode] = useState("");
  const [selectedDay, setSelectedDay] = useState(0);
  const [selectedMeal, setSelectedMeal] = useState("lunch");
  const [shoppingList, setShoppingList] = useState<ShoppingListType | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => { getMealPlans().then(setPlans).catch(() => {}); }, []);

  const handleCreatePlan = async () => {
    if (!newPlanName) return;
    try {
      const monday = new Date();
      monday.setDate(monday.getDate() - monday.getDay() + 1);
      const plan = await createMealPlan({ name: newPlanName, week_start_date: monday.toISOString().split("T")[0] });
      setPlans([plan, ...plans]);
      setActivePlan(plan);
      setNewPlanName("");
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
  };

  const handleAddItem = async () => {
    if (!activePlan || !barcode) return;
    try {
      const product = await searchProduct(barcode);
      await addMealPlanItem(activePlan.id, { product_id: product.id, day_of_week: selectedDay, meal_type: selectedMeal });
      const updated = await getMealPlan(activePlan.id);
      setActivePlan(updated);
      setBarcode("");
    } catch (err) { setError(err instanceof Error ? err.message : "Product not found"); }
  };

  const handleRemoveItem = async (itemId: string) => {
    if (!activePlan) return;
    try {
      await removeMealPlanItem(activePlan.id, itemId);
      const updated = await getMealPlan(activePlan.id);
      setActivePlan(updated);
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
  };

  const handleGenerateList = async () => {
    if (!activePlan) return;
    try {
      const list = await generateShoppingList(activePlan.id);
      setShoppingList(list);
    } catch (err) { setError(err instanceof Error ? err.message : "Failed"); }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold tracking-tight">Meal Planner</h1>
      {error && <div className="p-3 bg-red-900/30 border border-red-700 rounded-lg text-red-300 text-sm">{error}</div>}

      {!activePlan ? (
        <div className="space-y-4">
          <div className="flex gap-2">
            <input type="text" placeholder="New plan name..." value={newPlanName} onChange={e => setNewPlanName(e.target.value)}
              className="flex-1 px-4 py-3 bg-gray-800 border border-gray-700 rounded-xl text-white placeholder-gray-500" />
            <button onClick={handleCreatePlan} disabled={!newPlanName}
              className="px-5 py-3 bg-cyan-600 text-white rounded-xl font-medium hover:bg-cyan-500 disabled:opacity-40">Create</button>
          </div>
          {plans.map(p => (
            <button key={p.id} onClick={() => getMealPlan(p.id).then(setActivePlan)}
              className="w-full text-left bg-gray-800/50 border border-gray-700 rounded-xl p-4 hover:border-gray-600">
              <div className="font-medium">{p.name}</div>
              <div className="text-xs text-gray-400">{p.week_start_date} | {p.items.length} items</div>
            </button>
          ))}
        </div>
      ) : (
        <>
          <div className="flex justify-between items-center">
            <h2 className="font-semibold">{activePlan.name}</h2>
            <button onClick={() => setActivePlan(null)} className="text-sm text-gray-400 hover:text-white">Back</button>
          </div>

          <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-4 space-y-3">
            <div className="flex gap-2">
              <input type="text" placeholder="Barcode to add..." value={barcode} onChange={e => setBarcode(e.target.value)}
                className="flex-1 px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm" />
              <button onClick={handleAddItem} disabled={!barcode} className="px-4 py-2 bg-emerald-600 text-white text-sm rounded-lg disabled:opacity-40">Add</button>
            </div>
            <div className="flex gap-2">
              <select value={selectedDay} onChange={e => setSelectedDay(Number(e.target.value))}
                className="flex-1 px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm">
                {DAYS.map((d, i) => <option key={i} value={i}>{d}</option>)}
              </select>
              <select value={selectedMeal} onChange={e => setSelectedMeal(e.target.value)}
                className="flex-1 px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm capitalize">
                {MEAL_TYPES.map(m => <option key={m} value={m}>{m}</option>)}
              </select>
            </div>
          </div>

          <div className="flex overflow-x-auto gap-2 pb-1">
            {DAYS.map((d, i) => (
              <button key={i} onClick={() => setSelectedDay(i)}
                className={`px-3 py-1 rounded-full text-xs whitespace-nowrap ${selectedDay === i ? "bg-cyan-600 text-white" : "bg-gray-700 text-gray-400"}`}>{d}</button>
            ))}
          </div>

          {MEAL_TYPES.map(mt => {
            const items = activePlan.items.filter(it => it.day_of_week === selectedDay && it.meal_type === mt);
            if (items.length === 0) return null;
            return (
              <div key={mt} className="bg-gray-800/50 border border-gray-700 rounded-xl p-3">
                <h3 className="text-sm font-medium text-gray-400 capitalize mb-2">{mt}</h3>
                {items.map(item => (
                  <div key={item.id} className="flex justify-between items-center text-sm py-1">
                    <span className="text-gray-200">{item.product.name}</span>
                    <div className="flex items-center gap-2">
                      <span className="text-gray-500">{Math.round(item.product.calories)} kcal</span>
                      <button onClick={() => handleRemoveItem(item.id)} className="text-red-400 text-xs">x</button>
                    </div>
                  </div>
                ))}
              </div>
            );
          })}

          <button onClick={handleGenerateList} className="w-full py-3 bg-amber-600 text-white rounded-xl font-medium hover:bg-amber-500">
            Generate Shopping List
          </button>

          {shoppingList && (
            <div className="bg-gray-800/50 border border-gray-700 rounded-xl p-4 space-y-3">
              <h3 className="font-semibold">Shopping List</h3>
              {Object.entries(
                shoppingList.items.reduce((acc, item) => {
                  const cat = item.category || "Otros";
                  if (!acc[cat]) acc[cat] = [];
                  acc[cat].push(item);
                  return acc;
                }, {} as Record<string, typeof shoppingList.items>)
              ).map(([category, items]) => (
                <div key={category}>
                  <h4 className="text-xs text-cyan-400 font-medium uppercase mb-1">{category}</h4>
                  {items.map(item => (
                    <div key={item.id} className="flex justify-between text-sm py-0.5 text-gray-300">
                      <span>{item.ingredient_name}</span>
                      <span className="text-gray-500">{item.quantity}{item.unit}</span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
}
