import React from "react";
import OtpCodeInput from "./OtpCodeInput";

const OTP_LENGTH = 6;

/**
 * Lives inside the same landing hero shell as HomeView's login/signup panel
 * (same header, same hero background, same .home-login-card form chrome) so
 * password reset looks and feels like a continuation of login, not a
 * separate, differently-themed page.
 */
export default function ForgotPasswordView({
  form,
  step,
  notice,
  error,
  loading,
  onChange,
  onEmailSubmit,
  onVerifyToken,
  onResetPassword,
  onOpenLogin,
  onOpenForgotPassword,
}) {
  return (
    <div className="app-shell">
      <main>
      <header className="home-landing-header">
        <span className="home-landing-brand">Gawa<span>Go</span></span>
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
              <p className="hero-kicker mb-2"><span className="eyebrow-dot"></span> Account Recovery</p>
              <h1 className="display-5 fw-bold mb-3 hero-title">
                Let's get you<br />
                back into<br />
                your account.
              </h1>
              <p className="lead hero-subtitle mb-4">
                {step === "done"
                  ? "Your password has been updated. You can sign back in with it now."
                  : "Enter the email on your account and we'll send a reset code to get you back in."}
              </p>
            </div>
            <aside className="home-login-card" aria-label="Password reset panel">
              {step === "email" && (
                <form onSubmit={onEmailSubmit}>
                  <div className="home-login-form-head">
                    <div>
                      <h2>Reset your password</h2>
                      <p>We will send a reset code to your email address.</p>
                    </div>
                  </div>
                  {error && (
                    <div className="home-login-error" role="alert">
                      {error}
                    </div>
                  )}
                  {notice && !error && (
                    <div className="home-login-notice" role="status">
                      {notice}
                    </div>
                  )}
                  <div className="mb-3">
                    <label className="form-label fw-semibold" htmlFor="reset-email">
                      Email address
                    </label>
                    <input
                      id="reset-email"
                      name="email"
                      type="email"
                      className={`form-control${error ? " is-invalid" : ""}`}
                      value={form.email}
                      onChange={onChange}
                      placeholder="Enter your email address"
                    />
                  </div>
                  <button className="btn btn-primary w-100 home-login-submit" type="submit" disabled={loading}>
                    {loading ? "Sending..." : "Send Code"}
                  </button>
                </form>
              )}

              {step === "verify" && (
                <form onSubmit={onVerifyToken}>
                  <div className="home-login-form-head">
                    <div>
                      <h2>Enter the {OTP_LENGTH}-digit code</h2>
                      <p>We sent it to {form.email || "your email"}.</p>
                    </div>
                  </div>
                  {error && (
                    <div className="home-login-error" role="alert">
                      {error}
                    </div>
                  )}
                  <div className="mb-3">
                    <OtpCodeInput
                      id="reset-token"
                      length={OTP_LENGTH}
                      name="token"
                      value={form.token}
                      onChange={onChange}
                      disabled={loading}
                    />
                  </div>
                  <button
                    className="btn btn-primary w-100 home-login-submit"
                    type="submit"
                    disabled={loading || form.token.length !== OTP_LENGTH}
                  >
                    {loading ? "Verifying..." : "Verify Code"}
                  </button>
                  <div className="text-center mt-3">
                    <button
                      type="button"
                      className="btn btn-link btn-sm text-decoration-none p-0"
                      onClick={onOpenForgotPassword}
                    >
                      Didn't get a code? Send another
                    </button>
                  </div>
                </form>
              )}

              {step === "reset" && (
                <form onSubmit={onResetPassword}>
                  <div className="home-login-form-head">
                    <div>
                      <h2>Set a new password</h2>
                      <p>Choose a password with at least 8 characters.</p>
                    </div>
                  </div>
                  {error && (
                    <div className="home-login-error" role="alert">
                      {error}
                    </div>
                  )}
                  <div className="mb-3">
                    <label className="form-label fw-semibold" htmlFor="new-password">
                      New Password
                    </label>
                    <input
                      id="new-password"
                      name="newPassword"
                      type="password"
                      className="form-control"
                      value={form.newPassword}
                      onChange={onChange}
                      placeholder="At least 8 characters"
                    />
                  </div>
                  <div className="mb-3">
                    <label className="form-label fw-semibold" htmlFor="confirm-password">
                      Confirm Password
                    </label>
                    <input
                      id="confirm-password"
                      name="confirmPassword"
                      type="password"
                      className="form-control"
                      value={form.confirmPassword}
                      onChange={onChange}
                      placeholder="Re-enter your new password"
                    />
                  </div>
                  <button className="btn btn-primary w-100 home-login-submit" type="submit" disabled={loading}>
                    {loading ? "Resetting..." : "Reset Password"}
                  </button>
                </form>
              )}

              {step === "done" && (
                <div className="home-login-form-head text-center">
                  <div>
                    <h2>Password updated</h2>
                    <p>{notice || "You can now log in with your new password."}</p>
                  </div>
                  <div className="d-grid gap-2 mt-4">
                    <button type="button" className="btn btn-primary home-login-submit" onClick={onOpenLogin}>
                      Back to Login
                    </button>
                    <button type="button" className="btn btn-link btn-sm text-decoration-none" onClick={onOpenForgotPassword}>
                      Send another code
                    </button>
                  </div>
                </div>
              )}
            </aside>
          </div>
        </div>
      </section>
      </main>
    </div>
  );
}
