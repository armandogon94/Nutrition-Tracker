import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  createProfile: vi.fn(),
  getTDEE: vi.fn(),
  setGoalPreset: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

import ProfilePage from "@/app/profile/page";
import { createProfile, getTDEE, setGoalPreset } from "@/lib/api";
import { mockTDEEResult, mockUserProfile } from "../helpers/mockApi";

describe("ProfilePage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Default: no existing profile
    vi.mocked(getTDEE).mockRejectedValue(new Error("No profile"));
  });

  it("renders form fields (weight, height, age, sex, activity)", () => {
    render(<ProfilePage />);

    expect(screen.getByText("Weight (kg)")).toBeInTheDocument();
    expect(screen.getByText("Height (cm)")).toBeInTheDocument();
    expect(screen.getByText("Age")).toBeInTheDocument();
    expect(screen.getByText("Sex")).toBeInTheDocument();
    expect(screen.getByText("Activity Level")).toBeInTheDocument();

    // Activity level buttons
    expect(screen.getByText("Sedentary")).toBeInTheDocument();
    expect(screen.getByText("Lightly Active")).toBeInTheDocument();
    expect(screen.getByText("Moderately Active")).toBeInTheDocument();
    expect(screen.getByText("Very Active")).toBeInTheDocument();
    expect(screen.getByText("Extra Active")).toBeInTheDocument();
  });

  it("calculate TDEE calls createProfile", async () => {
    const profile = mockUserProfile();
    const tdeeResult = mockTDEEResult();

    vi.mocked(createProfile).mockResolvedValue(profile);
    // After creating profile, getTDEE should succeed
    vi.mocked(getTDEE)
      .mockRejectedValueOnce(new Error("No profile"))
      .mockResolvedValue(tdeeResult);

    render(<ProfilePage />);

    fireEvent.click(screen.getByText("Calculate TDEE"));

    await waitFor(() => {
      expect(createProfile).toHaveBeenCalledWith({
        weight_kg: 75,
        height_cm: 175,
        age: 28,
        sex: "male",
        activity_level: "moderate",
      });
    });
  });

  it("displays TDEE results", async () => {
    const tdeeResult = mockTDEEResult({ bmr: 1738, tdee: 2694 });

    vi.mocked(getTDEE).mockResolvedValue(tdeeResult);

    render(<ProfilePage />);

    await waitFor(() => {
      expect(screen.getByText("BMR (kcal/day)")).toBeInTheDocument();
      expect(screen.getByText("TDEE (kcal/day)")).toBeInTheDocument();
    });
  });

  it("submits changed input values to createProfile", async () => {
    const profile = mockUserProfile();
    const tdeeResult = mockTDEEResult();

    vi.mocked(createProfile).mockResolvedValue(profile);
    vi.mocked(getTDEE)
      .mockRejectedValueOnce(new Error("No profile"))
      .mockResolvedValue(tdeeResult);

    render(<ProfilePage />);

    // Change weight from default 75 to 90
    const weightInput = screen.getByDisplayValue("75");
    fireEvent.change(weightInput, { target: { value: "90" } });
    expect(weightInput).toHaveValue(90);

    // Change height from default 175 to 180
    const heightInput = screen.getByDisplayValue("175");
    fireEvent.change(heightInput, { target: { value: "180" } });
    expect(heightInput).toHaveValue(180);

    // Change age from default 28 to 35
    const ageInput = screen.getByDisplayValue("28");
    fireEvent.change(ageInput, { target: { value: "35" } });
    expect(ageInput).toHaveValue(35);

    fireEvent.click(screen.getByText("Calculate TDEE"));

    await waitFor(() => {
      expect(createProfile).toHaveBeenCalledWith({
        weight_kg: 90,
        height_cm: 180,
        age: 35,
        sex: "male",
        activity_level: "moderate",
      });
    });
  });

  it("goal preset buttons", async () => {
    const tdeeResult = mockTDEEResult();
    vi.mocked(getTDEE).mockResolvedValue(tdeeResult);

    const updatedResult = mockTDEEResult({ goal_preset: "fat_loss", daily_calories: 2194 });
    vi.mocked(setGoalPreset).mockResolvedValue(updatedResult);

    render(<ProfilePage />);

    await waitFor(() => {
      expect(screen.getByText("Fat Loss")).toBeInTheDocument();
    });

    expect(screen.getByText("Maintenance")).toBeInTheDocument();
    expect(screen.getByText("Lean Bulk")).toBeInTheDocument();
    expect(screen.getByText("Muscle Gain")).toBeInTheDocument();

    fireEvent.click(screen.getByText("Fat Loss"));

    await waitFor(() => {
      expect(setGoalPreset).toHaveBeenCalledWith("fat_loss");
    });
  });
});
