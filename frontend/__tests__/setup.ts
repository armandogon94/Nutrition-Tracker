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
