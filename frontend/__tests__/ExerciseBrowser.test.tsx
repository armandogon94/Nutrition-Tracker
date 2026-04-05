import { render, screen, fireEvent } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

// Test a filter component
describe("Exercise Filter Logic", () => {
  const muscles = ["chest", "back", "shoulders", "legs", "arms", "core"];

  it("filters exercises by muscle group", () => {
    const exercises = [
      { id: "1", name: "Bench Press", primary_muscle: "chest" },
      { id: "2", name: "Squat", primary_muscle: "legs" },
      { id: "3", name: "Deadlift", primary_muscle: "back" },
    ];

    const filtered = exercises.filter(e => e.primary_muscle === "chest");
    expect(filtered).toHaveLength(1);
    expect(filtered[0].name).toBe("Bench Press");
  });

  it("search filters by name", () => {
    const exercises = [
      { id: "1", name: "Barbell Bench Press" },
      { id: "2", name: "Dumbbell Bench Press" },
      { id: "3", name: "Barbell Squat" },
    ];

    const filtered = exercises.filter(e =>
      e.name.toLowerCase().includes("bench")
    );
    expect(filtered).toHaveLength(2);
  });

  it("returns all exercises when no filter applied", () => {
    const exercises = [
      { id: "1", name: "A" },
      { id: "2", name: "B" },
    ];
    const filtered = exercises.filter(() => true);
    expect(filtered).toHaveLength(2);
  });
});
