import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  getExercises: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

import ExercisesPage from "@/app/exercises/page";
import { getExercises } from "@/lib/api";
import { mockExercise } from "../helpers/mockApi";

describe("ExercisesPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders exercise list", async () => {
    const exercises = [
      mockExercise({ id: "ex-1", name: "Barbell Bench Press", primary_muscle: "chest" }),
      mockExercise({ id: "ex-2", name: "Barbell Squat", primary_muscle: "legs", equipment: "barbell", difficulty: "intermediate" }),
      mockExercise({ id: "ex-3", name: "Lat Pulldown", primary_muscle: "back", equipment: "cable", difficulty: "beginner" }),
    ];

    vi.mocked(getExercises).mockResolvedValue({ exercises, total: 3 });

    render(<ExercisesPage />);

    await waitFor(() => {
      expect(screen.getByText("Barbell Bench Press")).toBeInTheDocument();
    });
    expect(screen.getByText("Barbell Squat")).toBeInTheDocument();
    expect(screen.getByText("Lat Pulldown")).toBeInTheDocument();
    expect(screen.getByText("Exercises (3)")).toBeInTheDocument();
  });

  it("search filters exercises", async () => {
    const allExercises = [
      mockExercise({ id: "ex-1", name: "Barbell Bench Press", primary_muscle: "chest" }),
      mockExercise({ id: "ex-2", name: "Barbell Squat", primary_muscle: "legs" }),
    ];
    const filteredExercises = [
      mockExercise({ id: "ex-1", name: "Barbell Bench Press", primary_muscle: "chest" }),
    ];

    vi.mocked(getExercises)
      .mockResolvedValueOnce({ exercises: allExercises, total: 2 })
      .mockResolvedValueOnce({ exercises: filteredExercises, total: 1 });

    render(<ExercisesPage />);

    await waitFor(() => {
      expect(screen.getByText("Barbell Bench Press")).toBeInTheDocument();
    });

    const searchInput = screen.getByPlaceholderText("Search exercises...");
    fireEvent.change(searchInput, { target: { value: "bench" } });

    await waitFor(() => {
      expect(getExercises).toHaveBeenCalledWith(
        expect.objectContaining({ q: "bench" })
      );
    });
  });

  it("muscle filter buttons", async () => {
    vi.mocked(getExercises).mockResolvedValue({ exercises: [], total: 0 });

    render(<ExercisesPage />);

    // All muscle group buttons should be present
    expect(screen.getByText("All")).toBeInTheDocument();
    expect(screen.getByText("chest")).toBeInTheDocument();
    expect(screen.getByText("back")).toBeInTheDocument();
    expect(screen.getByText("shoulders")).toBeInTheDocument();
    expect(screen.getByText("legs")).toBeInTheDocument();
    expect(screen.getByText("arms")).toBeInTheDocument();
    expect(screen.getByText("core")).toBeInTheDocument();

    // Click a muscle group filter
    fireEvent.click(screen.getByText("chest"));

    await waitFor(() => {
      expect(getExercises).toHaveBeenCalledWith(
        expect.objectContaining({ muscle: "chest" })
      );
    });
  });
});
