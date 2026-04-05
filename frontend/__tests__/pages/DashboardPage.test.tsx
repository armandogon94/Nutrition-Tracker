import { render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  getDailyNutrition: vi.fn(),
  getWeeklyNutrition: vi.fn(),
  getGoals: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

// Mock chart components to avoid Recharts rendering complexity
vi.mock("@/components/charts/MacroPieChart", () => ({
  default: ({ protein, carbs, fat }: { protein: number; carbs: number; fat: number }) => (
    <div data-testid="macro-pie-chart">
      Pie: P={protein} C={carbs} F={fat}
    </div>
  ),
}));

vi.mock("@/components/charts/CalorieTrendChart", () => ({
  default: ({ data, calorieGoal }: { data: any[]; calorieGoal: number }) => (
    <div data-testid="calorie-trend-chart">
      Trend: {data.length} days, goal={calorieGoal}
    </div>
  ),
}));

vi.mock("@/components/charts/NutrientBarChart", () => ({
  default: ({ data }: { data: any[] }) => (
    <div data-testid="nutrient-bar-chart">
      Bars: {data.length} days
    </div>
  ),
}));

import DashboardPage from "@/app/dashboard/page";
import { getDailyNutrition, getWeeklyNutrition, getGoals } from "@/lib/api";
import {
  mockDailyNutrition,
  mockNutritionGoal,
} from "../helpers/mockApi";

describe("DashboardPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders calorie data when loaded", async () => {
    const daily = mockDailyNutrition({ total_calories: 1850 });
    const goal = mockNutritionGoal({ daily_calories: 2200 });
    const weekly = [
      mockDailyNutrition({ nutrition_date: "2026-03-28", total_calories: 1900 }),
      mockDailyNutrition({ nutrition_date: "2026-03-29", total_calories: 2100 }),
    ];

    vi.mocked(getDailyNutrition).mockResolvedValue(daily);
    vi.mocked(getWeeklyNutrition).mockResolvedValue(weekly);
    vi.mocked(getGoals).mockResolvedValue(goal);

    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("1850")).toBeInTheDocument();
    });
    expect(screen.getByText(/\/ 2200 kcal/)).toBeInTheDocument();
  });

  it("shows loading state initially with zero values", () => {
    // Make the promises never resolve so we see the default state
    vi.mocked(getDailyNutrition).mockReturnValue(new Promise(() => {}));
    vi.mocked(getWeeklyNutrition).mockReturnValue(new Promise(() => {}));
    vi.mocked(getGoals).mockReturnValue(new Promise(() => {}));

    render(<DashboardPage />);

    // Before data loads, calories should show 0
    expect(screen.getByText("0")).toBeInTheDocument();
    expect(screen.getByText("Dashboard")).toBeInTheDocument();
  });

  it("shows error state on API failure", async () => {
    vi.mocked(getDailyNutrition).mockRejectedValue(new Error("Network error"));
    vi.mocked(getWeeklyNutrition).mockRejectedValue(new Error("Network error"));
    vi.mocked(getGoals).mockRejectedValue(new Error("Network error"));

    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText(/Could not load data/)).toBeInTheDocument();
      expect(screen.getByText(/Network error/)).toBeInTheDocument();
    });
  });

  it("renders weekly chart section when weekly data is present", async () => {
    const daily = mockDailyNutrition();
    const goal = mockNutritionGoal();
    const weekly = [
      mockDailyNutrition({ nutrition_date: "2026-03-28" }),
      mockDailyNutrition({ nutrition_date: "2026-03-29" }),
      mockDailyNutrition({ nutrition_date: "2026-03-30" }),
    ];

    vi.mocked(getDailyNutrition).mockResolvedValue(daily);
    vi.mocked(getWeeklyNutrition).mockResolvedValue(weekly);
    vi.mocked(getGoals).mockResolvedValue(goal);

    render(<DashboardPage />);

    await waitFor(() => {
      expect(screen.getByText("Weekly Calorie Trend")).toBeInTheDocument();
    });
    expect(screen.getByText("Weekly Macros")).toBeInTheDocument();
    expect(screen.getByTestId("calorie-trend-chart")).toBeInTheDocument();
    expect(screen.getByTestId("nutrient-bar-chart")).toBeInTheDocument();
  });
});
