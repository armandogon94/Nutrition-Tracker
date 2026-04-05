import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

// We do NOT mock @/lib/api — that's the whole point of these tests.
// Instead we mock global fetch and localStorage-based auth helpers.

function makeResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 401 ? "Unauthorized" : "OK",
    json: () => Promise.resolve(body),
    headers: new Headers(),
    redirected: false,
    type: "basic" as ResponseType,
    url: "",
    clone: () => makeResponse(body, status),
    body: null,
    bodyUsed: false,
    arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)),
    blob: () => Promise.resolve(new Blob()),
    formData: () => Promise.resolve(new FormData()),
    text: () => Promise.resolve(JSON.stringify(body)),
    bytes: () => Promise.resolve(new Uint8Array()),
  } as Response;
}

describe("fetchAPI integration", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;
  const originalLocation = window.location;

  beforeEach(() => {
    localStorage.clear();
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);

    // Mock window.location for redirect tests
    Object.defineProperty(window, "location", {
      writable: true,
      value: { ...originalLocation, href: "http://localhost:3000" },
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    Object.defineProperty(window, "location", {
      writable: true,
      value: originalLocation,
    });
  });

  it("adds Authorization header when token exists", async () => {
    localStorage.setItem("fittracker_token", "my-token");
    fetchSpy.mockResolvedValue(makeResponse({ ok: true }));

    // Dynamic import so the real module runs with our mocked fetch
    const { getDailyNutrition } = await import("@/lib/api");
    await getDailyNutrition("2026-04-01");

    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [, options] = fetchSpy.mock.calls[0];
    expect(options.headers["Authorization"]).toBe("Bearer my-token");
  });

  it("does NOT add Authorization header when no token", async () => {
    fetchSpy.mockResolvedValue(makeResponse({ ok: true }));

    const { getDailyNutrition } = await import("@/lib/api");
    await getDailyNutrition("2026-04-01");

    const [, options] = fetchSpy.mock.calls[0];
    expect(options.headers["Authorization"]).toBeUndefined();
  });

  it("redirects to /login on 401 for non-auth endpoints", async () => {
    localStorage.setItem("fittracker_token", "expired-token");
    fetchSpy.mockResolvedValue(makeResponse({ detail: "Unauthorized" }, 401));

    const { getDailyNutrition } = await import("@/lib/api");

    await expect(getDailyNutrition("2026-04-01")).rejects.toThrow("Session expired");
    expect(window.location.href).toBe("/login");
    // Token should be cleared
    expect(localStorage.getItem("fittracker_token")).toBeNull();
  });

  it("does NOT redirect on 401 for /auth/ endpoints", async () => {
    fetchSpy.mockResolvedValue(makeResponse({ detail: "Bad credentials" }, 401));

    const { loginUser } = await import("@/lib/api");

    await expect(loginUser("bad@test.com", "wrong")).rejects.toThrow("Bad credentials");
    // Should NOT have redirected
    expect(window.location.href).not.toBe("/login");
  });

  it("loginUser sends correct POST body", async () => {
    const mockResponse = {
      access_token: "tok123",
      token_type: "bearer",
      user: { id: "u1", email: "a@b.com", display_name: "A" },
    };
    fetchSpy.mockResolvedValue(makeResponse(mockResponse));

    const { loginUser } = await import("@/lib/api");
    const result = await loginUser("a@b.com", "pass123");

    expect(result).toEqual(mockResponse);
    const [url, options] = fetchSpy.mock.calls[0];
    expect(url).toContain("/api/v1/auth/login");
    expect(options.method).toBe("POST");
    expect(JSON.parse(options.body)).toEqual({ email: "a@b.com", password: "pass123" });
  });

  it("getDailyNutrition calls the correct endpoint", async () => {
    const mockNutrition = {
      nutrition_date: "2026-04-01",
      total_calories: 1850,
      total_protein_g: 142,
      total_carbs_g: 210,
      total_fat_g: 58,
      total_fiber_g: 28,
      meals_count: 3,
    };
    fetchSpy.mockResolvedValue(makeResponse(mockNutrition));

    const { getDailyNutrition } = await import("@/lib/api");
    const result = await getDailyNutrition("2026-04-01");

    expect(result).toEqual(mockNutrition);
    const [url] = fetchSpy.mock.calls[0];
    expect(url).toContain("/api/v1/nutrition/daily/2026-04-01");
  });

  it("getMealsByDate calls the correct endpoint", async () => {
    fetchSpy.mockResolvedValue(makeResponse([]));

    const { getMealsByDate } = await import("@/lib/api");
    await getMealsByDate("2026-04-01");

    const [url] = fetchSpy.mock.calls[0];
    expect(url).toContain("/api/v1/meals/2026-04-01");
  });
});
