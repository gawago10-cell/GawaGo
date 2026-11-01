import React, { useState } from "react";
import OtpCodeInput from "./OtpCodeInput";
import { resendSignupCode, verifySignupCode } from "../services/backendDataService";

const CODE_LENGTH = 6;

/**
 * The step after sign-up when the backend holds a new account until its
 * emailed code is entered (REQUIRE_SIGNUP_EMAIL_CODE). Same landing shell as
 * Forgot password, so it reads as part of signing up.
 */
export default function ConfirmEmailView({ email, onConfirmed, onOpenLogin }) {
  // A refresh drops the address the sign-up kept in memory; ask for it then.
  const [address, setAddress] = useState(email || "");
  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event) {
    event.preventDefault();
    setLoading(true);
    setError("");
    try {
      await verifySignupCode(address.trim(), code);
      onConfirmed?.();
    } catch (verifyError) {
      setError(verifyError.message || "That code didn't work. Check it or ask for a new one.");
    } finally {
      setLoading(false);
    }
  }

  async function handleResend() {
    setError("");
    try {
      await resendSignupCode(address.trim());
      setNotice(`A new code is on its way to ${address.trim()}.`);
    } catch (resendError) {
      setError(resendError.message || "Unable to send another code right now.");
    }
  }

  return (
    <div className="app-shell">
      <main>
        <header className="home-landing-header">
          <span className="home-landing-brand">
            Gawa<span>Go</span>
          </span>
          <div className="home-landing-actions">
            <button className="btn btn-outline-light home-landing-signin" type="button" onClick={onOpenLogin}>
              Back to Login
            </button>
          </div>
        </header>
        <section className="hero-section hero-dark hero-fullscreen">
          <div className="container py-5 py-lg-6 position-relative hero-inner">
            <div className="home-landing-grid with-login">
              <div className="hero-copy">
                <p className="hero-kicker mb-2">
                  <span className="eyebrow-dot"></span> Almost done
                </p>
                <h1 className="display-5 fw-bold mb-3 hero-title">
                  Confirm your
                  <br />
                  email.
                </h1>
                <p className="lead hero-subtitle mb-4">
                  This keeps your notices and password resets going to an address you own.
                </p>
              </div>
              <aside className="home-login-card" aria-label="Confirm email panel">
                <form onSubmit={handleSubmit}>
                  <div className="home-login-form-head">
                    <div>
                      <h2>Enter the 6-digit code</h2>
                      <p>{email ? `We sent it to ${email}.` : "Enter the email you signed up with and its code."}</p>
                    </div>
                  </div>
                  {error && (
                    <div className="home-login-error" role="alert">
                      {error}
                    </div>
                  )}
                  {notice && (
                    <div className="home-login-notice" role="status">
                      {notice}
                    </div>
                  )}
                  {!email && (
                    <div className="mb-3">
                      <label className="form-label" htmlFor="signup-code-email">
                        Email address
                      </label>
                      <input
                        id="signup-code-email"
                        type="email"
                        className="form-control"
                        value={address}
                        onChange={(event) => setAddress(event.target.value)}
                        required
                      />
                    </div>
                  )}
                  <div className="mb-3">
                    <OtpCodeInput
                      id="signup-code"
                      length={CODE_LENGTH}
                      name="code"
                      value={code}
                      onChange={(event) => setCode(event.target.value)}
                      disabled={loading}
                    />
                  </div>
                  <button
                    className="btn btn-primary w-100 home-login-submit"
                    type="submit"
                    disabled={loading || code.length !== CODE_LENGTH || !address.trim()}
                  >
                    {loading ? "Checking..." : "Confirm Email"}
                  </button>
                  <div className="text-center mt-3">
                    <button
                      type="button"
                      className="btn btn-link btn-sm text-decoration-none p-0"
                      onClick={handleResend}
                      disabled={!address.trim()}
                    >
                      Didn't get a code? Send another
                    </button>
                  </div>
                </form>
              </aside>
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
