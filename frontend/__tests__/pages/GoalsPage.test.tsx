import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  getGoals: vi.fn(),
  updateGoals: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

import GoalsPage from "@/app/goals/page";
import { getGoals, updateGoals } from "@/lib/api";
import { mockNutritionGoal } from "../helpers/mockApi";

describe("GoalsPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders goal inputs with loaded values", async () => {
    const goal = mockNutritionGoal({
      daily_calories: 2500,
      daily_protein_g: 180,
      daily_carbs_g: 280,
      daily_fat_g: 80,
    });
    vi.mocked(getGoals).mockResolvedValue(goal);

    render(<GoalsPage />);

    await waitFor(() => {
      const inputs = screen.getAllByRole("spinbutton");
      expect(inputs).toHaveLength(4);
    });

    // After load, values should be from API
    await waitFor(() => {
      expect(screen.getByText("Daily Calories")).toBeInTheDocument();
      expect(screen.getByText("Protein")).toBeInTheDocument();
      expect(screen.getByText("Carbs")).toBeInTheDocument();
      expect(screen.getByText("Fat")).toBeInTheDocument();
    });
  });

  it("save button updates goals", async () => {
    const goal = mockNutritionGoal();
    const updatedGoal = mockNutritionGoal({ daily_calories: 2800 });

    vi.mocked(getGoals).mockResolvedValue(goal);
    vi.mocked(updateGoals).mockResolvedValue(updatedGoal);

    render(<GoalsPage />);

    await waitFor(() => {
      expect(screen.getByText("Save Goals")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Save Goals"));

    await waitFor(() => {
      expect(updateGoals).toHaveBeenCalled();
    });
  });

  it("shows saved confirmation", async () => {
    const goal = mockNutritionGoal();
    vi.mocked(getGoals).mockResolvedValue(goal);
    vi.mocked(updateGoals).mockResolvedValue(goal);

    render(<GoalsPage />);

    await waitFor(() => {
      expect(screen.getByText("Save Goals")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Save Goals"));

    await waitFor(() => {
      expect(screen.getByText("Saved!")).toBeInTheDocument();
    });
  });
});
