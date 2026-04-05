import "@testing-library/jest-dom/vitest";
import { vi } from "vitest";

// Mock ResizeObserver (required by Recharts ResponsiveContainer)
globalThis.ResizeObserver = vi.fn().mockImplementation(() => ({
  observe: vi.fn(),
  unobserve: vi.fn(),
  disconnect: vi.fn(),
}));

// Mock navigator.mediaDevices.getUserMedia for camera tests
Object.defineProperty(globalThis.navigator, "mediaDevices", {
  value: {
    getUserMedia: vi.fn().mockResolvedValue({
      getTracks: () => [{ stop: vi.fn(), kind: "video" }],
    }),
    enumerateDevices: vi.fn().mockResolvedValue([
      { deviceId: "mock-cam", kind: "videoinput", label: "Mock Camera" },
    ]),
  },
  writable: true,
});

// Mock HTMLMediaElement
HTMLMediaElement.prototype.play = vi.fn().mockResolvedValue(undefined);
HTMLMediaElement.prototype.pause = vi.fn();

// Mock next/navigation
vi.mock("next/navigation", () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    back: vi.fn(),
    refresh: vi.fn(),
  }),
  useParams: () => ({}),
  usePathname: () => "/dashboard",
  useSearchParams: () => new URLSearchParams(),
}));

// Mock next/dynamic to return the component directly
vi.mock("next/dynamic", () => ({
  default: (fn: () => Promise<any>) => {
    const Component = require("react").lazy(fn);
    return Component;
  },
}));

// Mock next/link to render a plain anchor
vi.mock("next/link", () => {
  const React = require("react");
  return {
    default: ({ children, href, ...props }: any) =>
      React.createElement("a", { href, ...props }, children),
  };
});
