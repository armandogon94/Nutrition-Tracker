import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import ManualEntry from "@/components/scanner/ManualEntry";

describe("ManualEntry", () => {
  it("renders input and submit button", () => {
    render(<ManualEntry onSubmit={vi.fn()} />);
    expect(screen.getByPlaceholderText(/enter barcode/i)).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /search/i })).toBeInTheDocument();
  });

  it("calls onSubmit with barcode value", () => {
    const onSubmit = vi.fn();
    render(<ManualEntry onSubmit={onSubmit} />);

    const input = screen.getByPlaceholderText(/enter barcode/i);
    fireEvent.change(input, { target: { value: "3017624010701" } });
    fireEvent.submit(input.closest("form")!);

    expect(onSubmit).toHaveBeenCalledWith("3017624010701");
  });

  it("does not submit empty barcode", () => {
    const onSubmit = vi.fn();
    render(<ManualEntry onSubmit={onSubmit} />);

    fireEvent.submit(screen.getByPlaceholderText(/enter barcode/i).closest("form")!);
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("disables input and button when loading", () => {
    render(<ManualEntry onSubmit={vi.fn()} isLoading />);
    expect(screen.getByPlaceholderText(/enter barcode/i)).toBeDisabled();
  });

  it("clears input after submit", () => {
    const onSubmit = vi.fn();
    render(<ManualEntry onSubmit={onSubmit} />);

    const input = screen.getByPlaceholderText(/enter barcode/i) as HTMLInputElement;
    fireEvent.change(input, { target: { value: "123456" } });
    fireEvent.submit(input.closest("form")!);

    expect(input.value).toBe("");
  });
});
