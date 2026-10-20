import React, { useEffect, useRef } from "react";

/**
 * A segmented one-box-per-digit code input (the GCash/OTP style), sized to
 * `length` automatically -- a 6-digit code gets 6 boxes. Reports its value
 * through the same `{ target: { name, value } }` shape a plain <input>'s
 * onChange gives, so it drops into existing form-state handlers unchanged.
 */
export default function OtpCodeInput({
  length = 6,
  name = "token",
  value = "",
  onChange,
  onComplete,
  disabled = false,
  autoFocus = true,
  id = "otp",
}) {
  const inputRefs = useRef([]);
  const digits = Array.from({ length }, (_, i) => value[i] || "");

  useEffect(() => {
    if (autoFocus && !disabled) {
      inputRefs.current[0]?.focus();
    }
    // Only on mount -- refocusing on every value change would steal focus
    // back from wherever the user tabbed to.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function emit(nextValue) {
    onChange?.({ target: { name, value: nextValue } });
    // A string made by joining one char per box is only `length` long when
    // every box actually has a digit (a missing one joins to nothing, not
    // to a literal empty substring -- every string "includes" "", so that
    // check would never have been false).
    if (nextValue.length === length) {
      onComplete?.(nextValue);
    }
  }

  function setDigitAt(index, char) {
    const next = digits.slice();
    next[index] = char;
    emit(next.join(""));
  }

  function handleChange(index, event) {
    const raw = event.target.value.replace(/\D/g, "");
    if (!raw) {
      setDigitAt(index, "");
      return;
    }
    // Typing (or an autofill landing in one box) can deliver more than one
    // digit at once -- spread the rest across the following boxes instead
    // of dropping them.
    const chars = raw.split("");
    const next = digits.slice();
    let cursor = index;
    for (const char of chars) {
      if (cursor >= length) break;
      next[cursor] = char;
      cursor += 1;
    }
    emit(next.join(""));
    const focusIndex = Math.min(cursor, length - 1);
    inputRefs.current[focusIndex]?.focus();
    inputRefs.current[focusIndex]?.select();
  }

  function handleKeyDown(index, event) {
    if (event.key === "Backspace" && !digits[index] && index > 0) {
      inputRefs.current[index - 1]?.focus();
      setDigitAt(index - 1, "");
    } else if (event.key === "ArrowLeft" && index > 0) {
      inputRefs.current[index - 1]?.focus();
    } else if (event.key === "ArrowRight" && index < length - 1) {
      inputRefs.current[index + 1]?.focus();
    }
  }

  function handlePaste(event) {
    const pasted = event.clipboardData.getData("text").replace(/\D/g, "").slice(0, length);
    if (!pasted) return;
    event.preventDefault();
    const next = pasted.split("");
    while (next.length < length) next.push("");
    emit(next.join(""));
    const focusIndex = Math.min(pasted.length, length - 1);
    inputRefs.current[focusIndex]?.focus();
  }

  return (
    <div className="otp-code-input" role="group" aria-label="Verification code">
      {digits.map((digit, index) => (
        <input
          key={index}
          id={index === 0 ? id : undefined}
          ref={(el) => (inputRefs.current[index] = el)}
          type="text"
          inputMode="numeric"
          autoComplete={index === 0 ? "one-time-code" : "off"}
          pattern="[0-9]*"
          maxLength={length}
          className="otp-code-box"
          value={digit}
          disabled={disabled}
          onChange={(event) => handleChange(index, event)}
          onKeyDown={(event) => handleKeyDown(index, event)}
          onPaste={handlePaste}
          onFocus={(event) => event.target.select()}
          aria-label={`Digit ${index + 1} of ${length}`}
        />
      ))}
    </div>
  );
}
