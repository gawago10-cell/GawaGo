import { useState } from "react";
import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";

import OtpCodeInput from "./OtpCodeInput";

function ControlledOtp({ length, onComplete }) {
  const [value, setValue] = useState("");
  return (
    <OtpCodeInput
      length={length}
      value={value}
      onChange={(event) => setValue(event.target.value)}
      onComplete={onComplete}
      autoFocus={false}
    />
  );
}

function renderOtp(props = {}) {
  const onChange = vi.fn();
  const onComplete = vi.fn();
  render(<OtpCodeInput length={6} value="" onChange={onChange} onComplete={onComplete} autoFocus={false} {...props} />);
  return { onChange, onComplete };
}

describe("OtpCodeInput", () => {
  it("renders one box per digit of the requested length", () => {
    renderOtp();
    expect(screen.getAllByRole("textbox")).toHaveLength(6);
  });

  it("typing a digit advances focus to the next box", () => {
    renderOtp();
    const boxes = screen.getAllByRole("textbox");
    fireEvent.change(boxes[0], { target: { value: "1" } });
    expect(document.activeElement).toBe(boxes[1]);
  });

  it("reports the combined value through the same event shape a plain input gives", () => {
    const { onChange } = renderOtp();
    const boxes = screen.getAllByRole("textbox");
    fireEvent.change(boxes[0], { target: { value: "4" } });
    expect(onChange).toHaveBeenCalledWith({ target: { name: "token", value: "4" } });
  });

  it("calls onComplete only once every box is filled", () => {
    const onComplete = vi.fn();
    render(<ControlledOtp length={3} onComplete={onComplete} />);
    const boxes = () => screen.getAllByRole("textbox");

    fireEvent.change(boxes()[0], { target: { value: "7" } });
    fireEvent.change(boxes()[1], { target: { value: "8" } });
    expect(onComplete).not.toHaveBeenCalled();

    fireEvent.change(boxes()[2], { target: { value: "9" } });
    expect(onComplete).toHaveBeenCalledWith("789");
  });

  it("a pasted full code fills every box and focuses the last one", () => {
    const { onChange } = renderOtp();
    const boxes = screen.getAllByRole("textbox");
    const clipboardData = { getData: () => "654321" };
    fireEvent.paste(boxes[0], { clipboardData });
    expect(onChange).toHaveBeenCalledWith({ target: { name: "token", value: "654321" } });
  });

  it("backspace on an empty box clears and refocuses the previous one", () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <OtpCodeInput length={4} value="12" onChange={onChange} autoFocus={false} />,
    );
    const boxes = screen.getAllByRole("textbox");
    boxes[2].focus();
    fireEvent.keyDown(boxes[2], { key: "Backspace" });
    expect(onChange).toHaveBeenCalledWith({ target: { name: "token", value: "1" } });
    expect(document.activeElement).toBe(boxes[1]);
  });
});
