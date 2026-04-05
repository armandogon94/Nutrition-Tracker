import { render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  getPrograms: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

import WorkoutsPage from "@/app/workouts/page";
import { getPrograms } from "@/lib/api";
import { mockWorkoutProgram } from "../helpers/mockApi";

describe("WorkoutsPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders program cards", async () => {
    const programs = [
      mockWorkoutProgram({
        id: "wp-1",
        name: "Push Pull Legs",
        description: "Classic 6-day PPL split",
        days_per_week: 6,
        difficulty: "intermediate",
        program_type: "hypertrophy",
      }),
      mockWorkoutProgram({
        id: "wp-2",
        name: "Starting Strength",
        description: "Beginner barbell program",
        days_per_week: 3,
        difficulty: "beginner",
        program_type: "strength",
      }),
    ];

    vi.mocked(getPrograms).mockResolvedValue(programs);

    render(<WorkoutsPage />);

    await waitFor(() => {
      expect(screen.getByText("Push Pull Legs")).toBeInTheDocument();
    });
    expect(screen.getByText("Starting Strength")).toBeInTheDocument();
    expect(screen.getByText("Classic 6-day PPL split")).toBeInTheDocument();
    expect(screen.getByText("Beginner barbell program")).toBeInTheDocument();
    expect(screen.getByText("6 days/week")).toBeInTheDocument();
    expect(screen.getByText("3 days/week")).toBeInTheDocument();
  });

  it("empty state when no programs", async () => {
    vi.mocked(getPrograms).mockResolvedValue([]);

    render(<WorkoutsPage />);

    await waitFor(() => {
      expect(screen.getByText("No workout programs available")).toBeInTheDocument();
    });
    expect(
      screen.getByText("Seed the database with exercise data to get started")
    ).toBeInTheDocument();
  });

  it("shows error state on API failure", async () => {
    vi.mocked(getPrograms).mockRejectedValue(new Error("Server error"));

    render(<WorkoutsPage />);

    await waitFor(() => {
      expect(screen.getByText(/Server error/)).toBeInTheDocument();
    });
  });
});
