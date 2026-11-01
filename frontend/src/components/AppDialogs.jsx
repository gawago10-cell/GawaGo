import React, { useEffect, useRef, useState } from "react";

/**
 * Styled stand-ins for window.confirm and window.prompt (fourth scan,
 * 2026-11-01). The browser's own boxes read "gawago... says", couldn't be
 * styled, and a prompt accepted a blank or pre-filled reason with one click.
 *
 *   if (await confirmDialog({ title: "Cancel this job?", confirmLabel: "Cancel job", tone: "danger" })) ...
 *   const reason = await askReason({ title: "Why are you cancelling?", label: "Reason" });  // null when dismissed
 *
 * App mounts one <AppDialogHost />. A component rendered without it (a unit
 * test, say) falls back to the browser's own dialog.
 */

let showDialog = null;
let nextId = 1;

function request(kind, options) {
  return new Promise((resolve) => {
    if (!showDialog) {
      const text = [options.title, options.message].filter(Boolean).join("\n\n");
      if (kind === "confirm") {
        resolve(Boolean(window.confirm(text)));
      } else {
        const answer = window.prompt(text, options.initialValue || "");
        resolve(answer == null ? null : String(answer));
      }
      return;
    }
    showDialog({ id: nextId++, kind, options, resolve });
  });
}

export function confirmDialog(options) {
  return request("confirm", options || {});
}

export function askReason(options) {
  return request("reason", options || {});
}

function ConfirmPanel({ options, onClose }) {
  const confirmRef = useRef(null);
  useEffect(() => {
    confirmRef.current?.focus();
  }, []);
  const tone = options.tone === "danger" ? "btn btn-danger" : "btn btn-success";
  return (
    <div className="gg-modal-backdrop app-dialog-backdrop" role="presentation" onClick={() => onClose(false)}>
      <div
        className="gg-modal-panel app-dialog-panel"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="app-dialog-title"
        aria-describedby={options.message ? "app-dialog-message" : undefined}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="gg-modal-head">
          <h2 id="app-dialog-title">{options.title || "Are you sure?"}</h2>
        </div>
        {options.message && (
          <div className="gg-modal-body">
            <p id="app-dialog-message" className="mb-0">
              {options.message}
            </p>
          </div>
        )}
        <div className="gg-modal-foot">
          <button type="button" className="gg-modal-foot-btn" onClick={() => onClose(false)}>
            {options.cancelLabel || "Go back"}
          </button>
          <button type="button" className={tone} ref={confirmRef} onClick={() => onClose(true)}>
            {options.confirmLabel || "Confirm"}
          </button>
        </div>
      </div>
    </div>
  );
}

function ReasonPanel({ options, onClose }) {
  const [value, setValue] = useState(options.initialValue || "");
  const [error, setError] = useState("");
  const maxLength = options.maxLength || 300;
  const required = options.required !== false;

  const submit = (event) => {
    event.preventDefault();
    const trimmed = value.replace(/\s+/g, " ").trim();
    if (required && !trimmed) {
      setError(options.requiredMessage || "Give a reason first.");
      return;
    }
    onClose(trimmed);
  };

  const tone = options.tone === "danger" ? "btn btn-danger" : "btn btn-success";
  return (
    <div className="gg-modal-backdrop app-dialog-backdrop" role="presentation" onClick={() => onClose(null)}>
      <form
        className="gg-modal-panel app-dialog-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="app-dialog-title"
        onClick={(event) => event.stopPropagation()}
        onSubmit={submit}
        noValidate
      >
        <div className="gg-modal-head">
          <h2 id="app-dialog-title">{options.title || "Give a reason"}</h2>
        </div>
        <div className="gg-modal-body">
          {options.message && <p className="small text-muted">{options.message}</p>}
          <label className="form-label fw-semibold" htmlFor="app-dialog-reason">
            {options.label || "Reason"}
          </label>
          <textarea
            id="app-dialog-reason"
            className={`form-control${error ? " is-invalid" : ""}`}
            rows="3"
            maxLength={maxLength}
            autoFocus
            value={value}
            placeholder={options.placeholder || ""}
            aria-invalid={error ? "true" : "false"}
            aria-describedby={error ? "app-dialog-reason-error" : undefined}
            onChange={(event) => {
              setValue(event.target.value);
              setError("");
            }}
          />
          {error && (
            <div id="app-dialog-reason-error" className="invalid-feedback d-block" role="alert">
              {error}
            </div>
          )}
        </div>
        <div className="gg-modal-foot">
          <button type="button" className="gg-modal-foot-btn" onClick={() => onClose(null)}>
            {options.cancelLabel || "Go back"}
          </button>
          <button type="submit" className={tone}>
            {options.confirmLabel || "Send"}
          </button>
        </div>
      </form>
    </div>
  );
}

export function AppDialogHost() {
  const [queue, setQueue] = useState([]);

  useEffect(() => {
    showDialog = (entry) => setQueue((previous) => [...previous, entry]);
    return () => {
      showDialog = null;
    };
  }, []);

  const current = queue[0];

  useEffect(() => {
    if (!current) return undefined;
    const onKeyDown = (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        current.resolve(current.kind === "confirm" ? false : null);
        setQueue((previous) => previous.slice(1));
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [current]);

  if (!current) return null;
  const close = (value) => {
    current.resolve(value);
    setQueue((previous) => previous.slice(1));
  };
  return current.kind === "confirm" ? (
    <ConfirmPanel key={current.id} options={current.options} onClose={close} />
  ) : (
    <ReasonPanel key={current.id} options={current.options} onClose={close} />
  );
}
