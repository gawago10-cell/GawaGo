import React, { useEffect, useRef, useState } from "react";
import { getAuthToken } from "../api/apiClient";

// Brand intro played over the landing page on a visitor's first open of the
// site, then dissolved on its own -- the landing page is already rendered
// underneath, so nothing waits on the animation. Households (cream) and
// workers (green) pair up, meet at a door, and the house and wordmark appear.

export const INTRO_SEEN_KEY = "gawago_intro_seen";

// Timeline in ms. The overlay starts fading at T_LEAVE and is gone FADE_MS later.
const T_LINES = 550;
const T_CONV = 1450;
const T_MERGE = 1950;
const T_HOUSE = 1990;
const T_DOOR = 2500;
const T_REVEAL = 2650;
const T_END = 2900;
const T_LEAVE = 3900;
const FADE_MS = 550;

const CREAM = "245,241,230";
const GREEN = "158,191,94";

// Only for someone arriving at the front door: a signed-in user is on their
// way to a dashboard, a deep link (#/worker-job-detail, the /admin portal)
// should open straight away, and once per tab is enough -- a reload must not
// replay it.
export function shouldPlayIntro() {
  if (typeof window === "undefined") return false;
  if (window.location.pathname.replace(/\/+$/, "") === "/admin") return false;
  const hash = window.location.hash.replace(/^#\/?/, "");
  if (hash && hash !== "home") return false;
  if (getAuthToken()) return false;
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return false;
  try {
    if (window.sessionStorage.getItem(INTRO_SEEN_KEY)) return false;
  } catch (error) {
    // Storage blocked (private mode): still play it, it just may replay.
  }
  return true;
}

// Written once the intro is on screen, not while deciding: StrictMode calls
// state initialisers twice, and marking it seen there hid it on the second.
function markIntroSeen() {
  try {
    window.sessionStorage.setItem(INTRO_SEEN_KEY, "1");
  } catch (error) {
    // see above
  }
}

function rng(seed) {
  return () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
}
const clamp = (x) => Math.max(0, Math.min(1, x));
const lerp = (a, b, t) => a + (b - a) * t;
const easeIO = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);

export default function IntroSplash() {
  const [active] = useState(shouldPlayIntro);
  const [phase, setPhase] = useState([]);
  const [leaving, setLeaving] = useState(false);
  const [gone, setGone] = useState(false);
  const canvasRef = useRef(null);
  const doorRef = useRef(null);
  const dismissRef = useRef(() => {});

  useEffect(() => {
    if (!active) return undefined;
    markIntroSeen();
    // Keep the landing page underneath from scrolling while it is covered.
    const root = document.documentElement;
    const previousOverflow = root.style.overflow;
    root.style.overflow = "hidden";
    const unlockScroll = () => {
      root.style.overflow = previousOverflow;
    };
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext?.("2d");
    const timers = [];
    let raf = null;
    let W = 0;
    let H = 0;
    let TX = 0;
    let TY = 0;
    let pts = [];
    let start = 0;

    const later = (fn, ms) => timers.push(window.setTimeout(fn, ms));
    const add = (name) => setPhase((current) => (current.includes(name) ? current : [...current, name]));

    function measureDoor() {
      const rect = doorRef.current?.getBoundingClientRect();
      if (!rect) return;
      TX = rect.left + rect.width / 2;
      TY = rect.top + rect.height * 0.6;
    }

    function build() {
      const r = rng(11);
      const n = W < 600 ? 10 : 16;
      const R = Math.min(W, H) * 0.44;
      const m = 30;
      pts = [];
      for (let i = 0; i < n; i += 1) {
        const a = (i / n) * Math.PI * 2 + r() * 0.5;
        const d = R * (0.5 + 0.5 * r());
        const hx = W / 2 + Math.cos(a) * d * (W > H ? 1.45 : 1);
        const hy = H / 2 + Math.sin(a) * d * (W > H ? 0.85 : 1.2);
        const oa = r() * Math.PI * 2;
        const od = 45 + r() * 70;
        const wx = hx + Math.cos(oa) * od;
        const wy = hy + Math.sin(oa) * od;
        pts.push({
          hx: Math.max(m, Math.min(W - m, hx)),
          hy: Math.max(m, Math.min(H - m, hy)),
          wx: Math.max(m, Math.min(W - m, wx)),
          wy: Math.max(m, Math.min(H - m, wy)),
          ph: r() * 6.28,
          delay: r(),
        });
      }
    }

    function resize() {
      if (!ctx) return;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      W = window.innerWidth;
      H = window.innerHeight;
      canvas.width = W * dpr;
      canvas.height = H * dpr;
      canvas.style.width = `${W}px`;
      canvas.style.height = `${H}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      build();
      measureDoor();
    }

    function dot(x, y, rad, rgb, alpha, glow) {
      if (rad <= 0 || alpha <= 0) return;
      if (glow) {
        ctx.beginPath();
        ctx.arc(x, y, rad * 2.6, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(${rgb},${0.16 * alpha})`;
        ctx.fill();
      }
      ctx.beginPath();
      ctx.arc(x, y, rad, 0, Math.PI * 2);
      ctx.fillStyle = `rgba(${rgb},${alpha})`;
      ctx.fill();
    }

    function draw(t) {
      ctx.clearRect(0, 0, W, H);
      const conv = easeIO(clamp((t - T_CONV) / (T_MERGE - T_CONV)));
      const merge = easeIO(clamp((t - T_MERGE) / 250));

      pts.forEach((p) => {
        const appear = clamp((t - p.delay * 450) / 300);
        const dx = Math.sin(t / 900 + p.ph) * 5;
        const dy = Math.cos(t / 1100 + p.ph) * 5;
        const hx = lerp(p.hx + dx, TX - 8 * (1 - merge), conv);
        const hy = lerp(p.hy + dy, TY, conv);
        const wx = lerp(p.wx - dx, TX + 8 * (1 - merge), conv);
        const wy = lerp(p.wy - dy, TY, conv);

        // matching line between each household and worker, with a pulse
        const ls = T_LINES + p.delay * 400;
        const lp = easeIO(clamp((t - ls) / 450));
        if (lp > 0) {
          const fade = 1 - conv;
          ctx.strokeStyle = `rgba(${GREEN},${0.5 * fade})`;
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.moveTo(hx, hy);
          ctx.lineTo(lerp(hx, wx, lp), lerp(hy, wy, lp));
          ctx.stroke();
          if (lp >= 1 && fade > 0) {
            const k = ((t - ls - 450) % 900) / 900;
            const pk = k < 0.5 ? k * 2 : 2 - k * 2;
            dot(lerp(hx, wx, pk), lerp(hy, wy, pk), 2.2, GREEN, 0.9 * fade, true);
          } else if (lp < 1) {
            dot(lerp(hx, wx, lp), lerp(hy, wy, lp), 2.6, GREEN, 1, true);
          }
        }

        const size = 4.5 * (1 - merge * 0.6);
        const alpha = appear * (1 - clamp((t - T_MERGE - 120) / 180));
        dot(hx, hy, size * appear, CREAM, alpha, false);
        dot(wx, wy, size * appear, GREEN, alpha, true);
      });

      // the merged pair waits at the door, then becomes the door light
      if (t >= T_MERGE) {
        const fadeOut = 1 - clamp((t - T_DOOR) / 250);
        const breathe = 1 + Math.sin((t - T_MERGE) / 140) * 0.08;
        dot(TX, TY, (5 + merge * 4) * breathe * fadeOut, GREEN, fadeOut, true);
        const f = clamp((t - T_MERGE) / 600);
        ctx.lineWidth = 2;
        ctx.strokeStyle = `rgba(${GREEN},${0.8 * (1 - f)})`;
        ctx.beginPath();
        ctx.arc(TX, TY, 10 + f * Math.min(W, H) * 0.35, 0, Math.PI * 2);
        ctx.stroke();
        const f2 = clamp((t - T_MERGE - 150) / 600);
        if (f2 > 0) {
          ctx.strokeStyle = `rgba(${GREEN},${0.5 * (1 - f2)})`;
          ctx.beginPath();
          ctx.arc(TX, TY, 10 + f2 * Math.min(W, H) * 0.25, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
    }

    function loop(ts) {
      const t = ts - start;
      draw(t);
      if (t < T_END) raf = window.requestAnimationFrame(loop);
      else ctx.clearRect(0, 0, W, H);
    }

    function leave() {
      timers.forEach(window.clearTimeout);
      timers.length = 0;
      if (raf) window.cancelAnimationFrame(raf);
      setLeaving(true);
      unlockScroll();
      window.setTimeout(() => setGone(true), FADE_MS);
    }
    dismissRef.current = leave;

    const onKey = () => leave();
    window.addEventListener("resize", resize);
    window.addEventListener("keydown", onKey);
    resize();
    document.fonts?.ready?.then(measureDoor);
    if (ctx) {
      start = performance.now();
      raf = window.requestAnimationFrame(loop);
    }
    later(() => add("show-legend"), 350);
    later(() => add("house-on"), T_HOUSE);
    later(() => add("door-on"), T_DOOR);
    later(() => add("reveal"), T_REVEAL);
    later(leave, T_LEAVE);

    return () => {
      unlockScroll();
      timers.forEach(window.clearTimeout);
      if (raf) window.cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      window.removeEventListener("keydown", onKey);
    };
  }, [active]);

  if (!active || gone) return null;

  const className = ["gg-intro", ...phase, leaving ? "leave" : ""].filter(Boolean).join(" ");
  const letters = [
    ["G", 2],
    ["a", 1],
    ["w", 0],
    ["a", 0],
    ["G", 1, true],
    ["o", 2, true],
  ];

  return (
    <div className={className} onClick={() => dismissRef.current()} role="presentation">
      <canvas ref={canvasRef} aria-hidden="true" />
      <div className="gg-intro-legend" aria-hidden="true">
        <span>
          <i style={{ background: "#F5F1E6" }} />
          Households
        </span>
        <span>
          <i style={{ background: "#9EBF5E" }} />
          Workers
        </span>
      </div>
      <div className="gg-intro-center">
        <div className="gg-intro-house">
          <svg viewBox="0 0 200 200" aria-hidden="true">
            <ellipse className="glow" cx="100" cy="120" rx="62" ry="54" />
            <path className="draw ground" pathLength="1" d="M20 170 H180" />
            <path className="draw house roof" pathLength="1" d="M34 96 L100 38 L166 96" />
            <path className="draw house body" pathLength="1" d="M52 82 V170 H148 V82" />
            <rect className="window" x="66" y="104" width="18" height="18" rx="3" />
            <rect className="window" x="116" y="104" width="18" height="18" rx="3" />
            <rect className="door-fill" x="86" y="126" width="28" height="44" rx="3" />
            <path ref={doorRef} className="draw house doorf" pathLength="1" d="M86 170 V128 H114 V170" />
          </svg>
        </div>
        <div className="gg-intro-wordmark" aria-label="GawaGo">
          {letters.map(([ch, d, go], index) => (
            <span key={index} className={go ? "ch go" : "ch"} style={{ "--d": d }} aria-hidden="true">
              {ch}
            </span>
          ))}
        </div>
        <div className="gg-intro-tagline">
          Bawat gawa, <b>may kapares.</b>
        </div>
      </div>
      <div className="gg-intro-skip">Tap anywhere to skip</div>
    </div>
  );
}
