import { describe, expect, it, beforeEach } from "vitest";
import { getToken, setToken, clearToken, getUser, setUser, isTokenExpired, isLoggedIn } from "@/lib/auth";

describe("auth token helpers", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("setToken stores and getToken retrieves a token", () => {
    setToken("abc123");
    expect(getToken()).toBe("abc123");
  });

  it("getToken returns null when nothing is stored", () => {
    expect(getToken()).toBeNull();
  });

  it("clearToken removes token and user from localStorage", () => {
    setToken("abc123");
    setUser({ id: "1", email: "a@b.com", display_name: "A" });

    clearToken();

    expect(getToken()).toBeNull();
    expect(getUser()).toBeNull();
  });
});

describe("auth user helpers", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("setUser / getUser round-trips through localStorage", () => {
    const user = { id: "u1", email: "test@example.com", display_name: "Test" };
    setUser(user);
    expect(getUser()).toEqual(user);
  });

  it("getUser returns null when nothing stored", () => {
    expect(getUser()).toBeNull();
  });

  it("getUser returns null for invalid JSON", () => {
    localStorage.setItem("fittracker_user", "not-json{{{");
    expect(getUser()).toBeNull();
  });
});

describe("isTokenExpired", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("returns true when no token exists", () => {
    expect(isTokenExpired()).toBe(true);
  });

  it("returns false for a token with future exp", () => {
    const futureExp = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now
    const payload = btoa(JSON.stringify({ exp: futureExp }));
    const fakeJwt = `header.${payload}.signature`;
    setToken(fakeJwt);

    expect(isTokenExpired()).toBe(false);
  });

  it("returns true for a token with past exp", () => {
    const pastExp = Math.floor(Date.now() / 1000) - 3600; // 1 hour ago
    const payload = btoa(JSON.stringify({ exp: pastExp }));
    const fakeJwt = `header.${payload}.signature`;
    setToken(fakeJwt);

    expect(isTokenExpired()).toBe(true);
  });

  it("returns true for a malformed token", () => {
    setToken("not-a-jwt");
    expect(isTokenExpired()).toBe(true);
  });
});

describe("isLoggedIn", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("returns false when no token", () => {
    expect(isLoggedIn()).toBe(false);
  });

  it("returns true when valid non-expired token exists", () => {
    const futureExp = Math.floor(Date.now() / 1000) + 3600;
    const payload = btoa(JSON.stringify({ exp: futureExp }));
    setToken(`h.${payload}.s`);

    expect(isLoggedIn()).toBe(true);
  });

  it("returns false when token is expired", () => {
    const pastExp = Math.floor(Date.now() / 1000) - 3600;
    const payload = btoa(JSON.stringify({ exp: pastExp }));
    setToken(`h.${payload}.s`);

    expect(isLoggedIn()).toBe(false);
  });
});
