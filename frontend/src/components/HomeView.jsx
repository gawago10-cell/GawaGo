import React from "react";

export default function HomeView({
  dashboardMetrics,
  initialShowLogin = false,
  isAdminPortal = false,
  loginError = "",
  loginForm,
  onLoginChange,
  onLoginSubmit,
  onOpenForgotPassword,
  onOpenHouseholdRegister,
  onOpenWorkerRegister,
}) {
  const [showLogin, setShowLogin] = React.useState(initialShowLogin);
  const [authMode, setAuthMode] = React.useState("login");
  // Set when opening the panel added a history entry, so Back (ours or the
  // phone's) can return to the landing page instead of leaving the site.
  const pushedAuthEntryRef = React.useRef(false);

  React.useEffect(() => {
    setShowLogin(initialShowLogin);
  }, [initialShowLogin]);

  React.useEffect(() => {
    function handlePopState(event) {
      if (pushedAuthEntryRef.current && !event.state?.ggAuthPanel) {
        pushedAuthEntryRef.current = false;
        setShowLogin(false);
      }
    }
    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, []);

  // On a phone the form stacks under the hero, so opening it used to look
  // like nothing happened -- the form was below the fold. The hero is hidden
  // while it's open (CSS, phones only) and the page returns to the top.
  const openAuthPanel = (mode) => {
    setAuthMode(mode);
    if (!showLogin && !pushedAuthEntryRef.current) {
      window.history.pushState({ ggAuthPanel: true }, "");
      pushedAuthEntryRef.current = true;
    }
    setShowLogin(true);
    window.scrollTo(0, 0);
  };

  const closeAuthPanel = () => {
    if (pushedAuthEntryRef.current) {
      window.history.back();
    } else {
      setShowLogin(false);
    }
    window.scrollTo(0, 0);
  };

  React.useEffect(() => {
    if (isAdminPortal) {
      onLoginChange({
        target: {
          name: "role",
          value: "admin",
        },
      });
    }
  }, [isAdminPortal]);

  if (isAdminPortal) {
    return (
      <main className="admin-portal-page">
        <header className="admin-portal-topbar">
          <span className="admin-portal-brand">Gawa<span>Go</span></span>
          <span className="admin-portal-label">Administrator Portal</span>
        </header>

        <section className="admin-portal-shell" aria-label="Administrator login">
          <div className="admin-portal-copy">
            <span className="admin-portal-kicker">Secure Access</span>
            <h1>Platform management for GawaGo administrators.</h1>
            <p>
              Review worker verification, monitor job activity, manage users, and keep the employment platform reliable
              from one dedicated portal.
            </p>
            <div className="admin-portal-highlights" aria-label="Admin portal responsibilities">
              <span>Verification Review</span>
              <span>Employment Analytics</span>
              <span>User Monitoring</span>
            </div>
          </div>

          <aside className="admin-portal-card">
            <div className="admin-portal-card-head">
              <span>Admin Sign In</span>
              <h2>Welcome back</h2>
              <p>Use an administrator or superadmin account to continue.</p>
            </div>
            <form onSubmit={onLoginSubmit}>
              {loginError && (
                <div className="home-login-error" role="alert">
                  {loginError}
                </div>
              )}
              <div className="mb-3">
                <label className="form-label fw-semibold" htmlFor="admin-login-username">
                  Email or Username
                </label>
                <input
                  className={`form-control${loginError ? " is-invalid" : ""}`}
                  id="admin-login-username"
                  name="username"
                  onChange={onLoginChange}
                  placeholder="Enter admin username"
                  type="text"
                  value={loginForm.username}
                />
              </div>
              <div className="mb-3">
                <label className="form-label fw-semibold" htmlFor="admin-login-password">
                  Password
                </label>
                <input
                  className={`form-control${loginError ? " is-invalid" : ""}`}
                  id="admin-login-password"
                  name="password"
                  onChange={onLoginChange}
                  placeholder="Enter password"
                  type="password"
                  value={loginForm.password}
                />
              </div>
              <div className="admin-portal-form-row">
                <button className="btn btn-link btn-sm text-decoration-none p-0" type="button" onClick={onOpenForgotPassword}>
                  Forgot password?
                </button>
              </div>
              <button className="btn btn-primary w-100 admin-portal-submit" type="submit">
                Login to Admin Dashboard
              </button>
            </form>
          </aside>
        </section>
      </main>
    );
  }

  return (
    <React.Fragment>
      <header className="home-landing-header">
        <span className="home-landing-brand">Gawa<span>Go</span></span>
        <div className="home-landing-actions">
          <button
            className="btn btn-outline-light home-landing-signin"
            type="button"
            onClick={() => openAuthPanel("login")}
          >
            Login
          </button>
          <button
            className="btn btn-outline-light home-landing-signup"
            type="button"
            onClick={() => openAuthPanel("signup")}
          >
            Sign Up
          </button>
        </div>
      </header>
      <section className={`hero-section hero-dark hero-fullscreen${showLogin ? " auth-open" : ""}`}>
        <div className="container py-5 py-lg-6 position-relative hero-inner">
          <div className={`home-landing-grid ${showLogin ? "with-login" : ""}`}>
            <div className="hero-copy">
              <p className="hero-kicker mb-2"><span className="eyebrow-dot"></span> Tayabas City</p>
              <h1 className="display-5 fw-bold mb-3 hero-title">
                Find <span>trusted</span><br />
                helpers and<br />
                skilled workers<br />
                near you.
              </h1>
              <p className="lead hero-subtitle mb-4">
                GawaGo connects households and workers with smart matching, transparent rates, and a fair reputation system.
              </p>
              <div className="home-task-strip" aria-label="Available services">
                <span>Post jobs</span>
                <span>Apply nearby</span>
                <span>Verify profiles</span>
              </div>
              <div className="d-flex gap-2 flex-wrap">
                <button
                  className="btn btn-primary btn-lg hero-primary-btn"
                  type="button"
                  onClick={onOpenHouseholdRegister}
                >
                  Post a Job
                </button>
                <button
                  className="btn btn-outline-light btn-lg hero-secondary-btn"
                  type="button"
                  onClick={onOpenWorkerRegister}
                >
                  Find Work
                </button>
              </div>
            </div>
            {!showLogin && (
              <div className="hero-snapshot-slot">
                <div className="hero-snapshot hero-snapshot-alt">
                  <div className="hero-snapshot-card">
                    <span className="hero-snapshot-badge">Open Jobs Live</span>
                    <p className="hero-snapshot-label mb-1">Open Jobs</p>
                    <p className="hero-snapshot-value mb-2">{dashboardMetrics.openJobs}</p>
                    <p className="hero-snapshot-note mb-0">Jobs waiting for workers to apply</p>
                    <hr className="hero-snapshot-divider" />
                    <div className="hero-snapshot-mini-grid">
                      <div>
                        <strong>{dashboardMetrics.verifiedWorkers}</strong>
                        <span>Verified Workers</span>
                      </div>
                      <div>
                        <strong>{dashboardMetrics.completedJobs}</strong>
                        <span>Completed Services</span>
                      </div>
                      <div>
                        <strong>{dashboardMetrics.totalAccounts}</strong>
                        <span>Registered Accounts</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            )}
            {showLogin && (
              <aside className="home-login-card" aria-label="Authentication panel">
                <button className="home-login-back" type="button" onClick={closeAuthPanel}>
                  <span aria-hidden="true">&larr;</span> Back
                </button>
                {authMode === "signup" && (
                  <div className="home-login-form-head home-signup-head">
                    <div>
                      <h2>Create your account</h2>
                      <p>Choose how you&rsquo;ll use GawaGo.</p>
                    </div>
                  </div>
                )}
                {authMode === "signup" && (
                  <div className="home-role-card-grid home-role-choice-grid">
                    <button
                      className="home-role-card home-role-choice-card"
                      type="button"
                      onClick={onOpenHouseholdRegister}
                    >
                      <span className="home-role-illustration household-illustration" aria-hidden="true">
                        <i></i><b></b><em></em>
                      </span>
                      <strong>Household</strong>
                      <small>Post jobs and hire trusted workers</small>
                      <span className="home-role-action">Create Account</span>
                    </button>
                    <button
                      className="home-role-card home-role-choice-card"
                      type="button"
                      onClick={onOpenWorkerRegister}
                    >
                      <span className="home-role-illustration worker-illustration" aria-hidden="true">
                        <i></i><b></b><em></em>
                      </span>
                      <strong>Worker</strong>
                      <small>Find jobs near your barangay</small>
                      <span className="home-role-action">Create Account</span>
                    </button>
                  </div>
                )}

                {authMode === "login" && (
                  <form onSubmit={onLoginSubmit}>
                    <div className="home-login-form-head">
                      <div>
                        <h2>Login to GawaGo</h2>
                        <p>Enter your credentials. We will open the right dashboard for your account.</p>
                      </div>
                    </div>
                    {loginError && (
                      <div className="home-login-error" role="alert">
                        {loginError}
                      </div>
                    )}
                    <div className="mb-3">
                      <label className="form-label fw-semibold" htmlFor="home-login-username">
                        Email or Username
                      </label>
                      <input
                        className={`form-control${loginError ? " is-invalid" : ""}`}
                        id="home-login-username"
                        name="username"
                        onChange={onLoginChange}
                        placeholder="Enter your email or username"
                        type="text"
                        value={loginForm.username}
                      />
                    </div>
                    <div className="mb-3">
                      <label className="form-label fw-semibold" htmlFor="home-login-password">
                        Password
                      </label>
                      <input
                        className={`form-control${loginError ? " is-invalid" : ""}`}
                        id="home-login-password"
                        name="password"
                        onChange={onLoginChange}
                        placeholder="Enter your password"
                        type="password"
                        value={loginForm.password}
                      />
                    </div>
                    <div className="text-end mb-3">
                      <button className="btn btn-link btn-sm text-decoration-none p-0" type="button" onClick={onOpenForgotPassword}>
                        Forgot your password?
                      </button>
                    </div>
                    <button className="btn btn-primary w-100 home-login-submit" type="submit">
                      Login
                    </button>
                  </form>
                )}

              </aside>
            )}
          </div>
        </div>
      </section>
    </React.Fragment>
  );
}
