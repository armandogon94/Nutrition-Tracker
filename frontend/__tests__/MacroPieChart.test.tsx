import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import MacroPieChart from "@/components/charts/MacroPieChart";

describe("MacroPieChart", () => {
  it("shows empty state when all values are zero", () => {
    render(<MacroPieChart protein={0} carbs={0} fat={0} />);
    expect(screen.getByText(/no macros logged/i)).toBeInTheDocument();
  });

  it("renders chart when values are provided", () => {
    const { container } = render(
      <MacroPieChart protein={30} carbs={50} fat={20} />
    );
    // Recharts renders SVG elements
    expect(container.querySelector(".recharts-responsive-container")).toBeInTheDocument();
  });
});
