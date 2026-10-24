import React from "react";
import { createRoot } from "react-dom/client";
import "bootstrap/dist/css/bootstrap.min.css";
import "./styles/main.css";
import App from "./App";
import IntroSplash from "./components/IntroSplash";

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  render() {
    if (this.state.error) {
      if (this.props.fallback !== undefined) {
        return this.props.fallback;
      }
      return (
        <main className="container py-5">
          <div className="alert alert-danger">
            <h1 className="h4">GawaGo encountered an error</h1>
            <p className="mb-0">{this.state.error.message || "Please refresh the page and try again."}</p>
          </div>
        </main>
      );
    }

    return this.props.children;
  }
}

createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
      {/* Decoration only: if it ever throws, drop it rather than the app. */}
      <ErrorBoundary fallback={null}>
        <IntroSplash />
      </ErrorBoundary>
    </ErrorBoundary>
  </React.StrictMode>
);
