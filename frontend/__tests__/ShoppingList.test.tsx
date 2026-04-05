import { describe, expect, it } from "vitest";

describe("Shopping List Aggregation", () => {
  it("groups items by category", () => {
    const items = [
      { ingredient_name: "Chicken", category: "Carnes y Aves", quantity: 500, unit: "g" },
      { ingredient_name: "Rice", category: "Granos y Cereales", quantity: 300, unit: "g" },
      { ingredient_name: "Beef", category: "Carnes y Aves", quantity: 400, unit: "g" },
    ];

    const grouped = items.reduce((acc, item) => {
      const cat = item.category || "Otros";
      if (!acc[cat]) acc[cat] = [];
      acc[cat].push(item);
      return acc;
    }, {} as Record<string, typeof items>);

    expect(Object.keys(grouped)).toHaveLength(2);
    expect(grouped["Carnes y Aves"]).toHaveLength(2);
    expect(grouped["Granos y Cereales"]).toHaveLength(1);
  });

  it("calculates total per category", () => {
    const items = [
      { ingredient_name: "Chicken", category: "Meat", quantity: 500 },
      { ingredient_name: "Beef", category: "Meat", quantity: 300 },
    ];

    const total = items.reduce((sum, item) => sum + item.quantity, 0);
    expect(total).toBe(800);
  });
});
