import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  getMealsByDate: vi.fn(),
  removeMealItem: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

import MealsPage from "@/app/meals/page";
import { getMealsByDate } from "@/lib/api";
import { mockMeal, mockMealItem, mockProduct } from "../helpers/mockApi";

describe("MealsPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders meals for current date", async () => {
    const meals = [
      mockMeal({
        id: "meal-1",
        meal_type: "breakfast",
        items: [
          mockMealItem({
            id: "mi-1",
            product: mockProduct({ name: "Avena Quaker", calories: 150 }),
            quantity_servings: 1,
          }),
        ],
      }),
      mockMeal({
        id: "meal-2",
        meal_type: "lunch",
        items: [
          mockMealItem({
            id: "mi-2",
            product: mockProduct({ id: "prod-2", name: "Pechuga de Pollo", calories: 250 }),
            quantity_servings: 1,
          }),
        ],
      }),
    ];

    vi.mocked(getMealsByDate).mockResolvedValue(meals);

    render(<MealsPage />);

    await waitFor(() => {
      expect(screen.getByText("Avena Quaker")).toBeInTheDocument();
    });
    expect(screen.getByText("Pechuga de Pollo")).toBeInTheDocument();
    // Total should be 150 + 250 = 400
    expect(screen.getByText("400 kcal")).toBeInTheDocument();
  });

  it("shows empty state", async () => {
    vi.mocked(getMealsByDate).mockResolvedValue([]);

    render(<MealsPage />);

    await waitFor(() => {
      expect(screen.getByText("No meals logged for this date")).toBeInTheDocument();
    });
    expect(screen.getByText("Scan a barcode to get started")).toBeInTheDocument();
  });

  it("date navigation triggers re-fetch", async () => {
    vi.mocked(getMealsByDate).mockResolvedValue([]);

    render(<MealsPage />);

    // Wait for the initial load
    await waitFor(() => {
      expect(getMealsByDate).toHaveBeenCalledTimes(1);
    });

    // Change the date
    const dateInput = screen.getByDisplayValue(
      new Date().toISOString().split("T")[0]
    );
    fireEvent.change(dateInput, { target: { value: "2026-03-15" } });

    await waitFor(() => {
      expect(getMealsByDate).toHaveBeenCalledWith("2026-03-15");
    });
  });
});
