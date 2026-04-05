import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/api", () => ({
  loginUser: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  getToken: () => "mock-token",
  setToken: vi.fn(),
  setUser: vi.fn(),
  getUser: () => ({ id: "1", email: "test@test.dev", display_name: "Test" }),
  isLoggedIn: () => true,
}));

import LoginPage from "@/app/login/page";
import { loginUser } from "@/lib/api";
import { mockAuthResponse } from "../helpers/mockApi";

const mockPush = vi.fn();
vi.mock("next/navigation", async () => ({
  useRouter: () => ({ push: mockPush, replace: vi.fn(), back: vi.fn(), refresh: vi.fn() }),
  useParams: () => ({}),
  usePathname: () => "/login",
  useSearchParams: () => new URLSearchParams(),
}));

describe("LoginPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders email and password inputs", () => {
    render(<LoginPage />);

    expect(screen.getByLabelText("Email")).toBeInTheDocument();
    expect(screen.getByLabelText("Password")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Sign In" })).toBeInTheDocument();
  });

  it("shows error on failed login", async () => {
    vi.mocked(loginUser).mockRejectedValue(new Error("Invalid credentials"));

    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText("Email"), {
      target: { value: "bad@test.dev" },
    });
    fireEvent.change(screen.getByLabelText("Password"), {
      target: { value: "wrongpass" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Sign In" }));

    await waitFor(() => {
      expect(screen.getByText("Invalid credentials")).toBeInTheDocument();
    });
  });

  it("redirects on successful login", async () => {
    const authResponse = mockAuthResponse();
    vi.mocked(loginUser).mockResolvedValue(authResponse);

    // Login page uses window.location.href for hard navigation
    const locationSpy = vi.spyOn(window, "location", "get").mockReturnValue({
      ...window.location,
      href: "",
    });
    const hrefSetter = vi.fn();
    Object.defineProperty(window.location, "href", {
      set: hrefSetter,
      configurable: true,
    });

    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText("Email"), {
      target: { value: "test1@fittracker.dev" },
    });
    fireEvent.change(screen.getByLabelText("Password"), {
      target: { value: "test1234" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Sign In" }));

    await waitFor(() => {
      expect(hrefSetter).toHaveBeenCalledWith("/dashboard");
    });

    locationSpy.mockRestore();
  });

  it("quick login buttons are present", () => {
    render(<LoginPage />);

    expect(screen.getByText("Test 1")).toBeInTheDocument();
    expect(screen.getByText("Test 2")).toBeInTheDocument();
    expect(screen.getByText("Test 3")).toBeInTheDocument();
  });
});
