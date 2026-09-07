import { useCallback, useEffect, useRef, useState } from "react";
import { PixelCanvas } from "../PixelCanvas";
import { useReducedMotion } from "../useReducedMotion";

type Mode = "hidden" | "peek" | "open";

interface Props {
  /** Menu-bar mascot state, lifted so acknowledging here updates it there. */
  onAcknowledge: () => void;
  acknowledged: boolean;
}

/**
 * A live mock of the real panel: hidden at rest, a Peek shortly after load,
 * and a Reveal when the cursor pushes against the top edge of the stage —
 * the same three surfaces the macOS app has (ADR-0007). A ghost cursor
 * demonstrates the gesture until a real pointer takes over.
 */
export function IslandStage({ onAcknowledge, acknowledged }: Props) {
  const [mode, setMode] = useState<Mode>("hidden");
  const [tookOver, setTookOver] = useState(false);
  const reduced = useReducedMotion();

  const graceTimer = useRef<number | undefined>(undefined);
  const ghostRef = useRef<SVGSVGElement>(null);
  const demoTimers = useRef<number[]>([]);
  const tookOverRef = useRef(false);

  const clearDemo = useCallback(() => {
    demoTimers.current.forEach(clearTimeout);
    demoTimers.current = [];
    const ghost = ghostRef.current;
    if (ghost?.getAnimations) ghost.getAnimations().forEach((a) => a.cancel());
    if (ghost) ghost.style.opacity = "0";
  }, []);

  const takeover = useCallback(() => {
    if (tookOverRef.current) return;
    tookOverRef.current = true;
    setTookOver(true);
    clearDemo();
  }, [clearDemo]);

  // A Peek shortly after load, exactly as the app does on a marking event.
  useEffect(() => {
    if (reduced) return;
    const show = window.setTimeout(() => {
      setMode((m) => (m === "open" ? m : "peek"));
      const hide = window.setTimeout(() => setMode((m) => (m === "peek" ? "hidden" : m)), 2500);
      demoTimers.current.push(hide);
    }, 900);
    return () => clearTimeout(show);
  }, [reduced]);

  // The ghost cursor demonstrates the top-edge Reveal until a real one arrives.
  useEffect(() => {
    if (reduced || tookOver) return;

    const runDemo = () => {
      const ghost = ghostRef.current;
      if (!ghost?.animate || tookOverRef.current || document.hidden) return;
      setMode((m) => {
        if (m !== "hidden") return m;
        ghost.animate(
          [
            { transform: "translate(96px, 200px)", opacity: 0 },
            { transform: "translate(96px, 200px)", opacity: 1, offset: 0.14 },
            { transform: "translate(20px, 30px)", opacity: 1, offset: 0.55 },
            { transform: "translate(16px, 16px)", opacity: 1, offset: 0.68 },
            { transform: "translate(16px, 14px)", opacity: 1, offset: 0.9 },
            { transform: "translate(16px, 14px)", opacity: 0 },
          ],
          { duration: 3600, easing: "ease-in-out" },
        );
        demoTimers.current.push(
          window.setTimeout(() => !tookOverRef.current && setMode("open"), 2100),
          window.setTimeout(() => !tookOverRef.current && setMode("hidden"), 4900),
        );
        return m;
      });
    };

    const first = window.setTimeout(runDemo, 4400);
    const repeat = window.setInterval(runDemo, 11000);
    return () => {
      clearTimeout(first);
      clearInterval(repeat);
    };
  }, [reduced, tookOver]);

  useEffect(() => () => clearDemo(), [clearDemo]);

  const open = () => {
    takeover();
    clearTimeout(graceTimer.current);
    setMode("open");
  };

  // A short grace delay on leave, like the real panel's recede hysteresis.
  const armCollapse = () => {
    clearTimeout(graceTimer.current);
    graceTimer.current = window.setTimeout(() => setMode("hidden"), 350);
  };

  const acknowledge = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (acknowledged) return;
    onAcknowledge();
  };

  const revealed = mode !== "hidden";

  return (
    <div className={revealed ? "island-stage revealed" : "island-stage"}>
      <div
        className="reveal-zone"
        aria-hidden="true"
        onMouseEnter={open}
        onMouseLeave={armCollapse}
        onTouchStart={takeover}
      />

      <svg className="ghost-cursor" ref={ghostRef} viewBox="0 0 24 24" aria-hidden="true">
        <path
          d="M5 2 L5 19 L9.6 15.2 L12.2 21 L15 19.8 L12.4 14 L18 14 Z"
          fill="#1c1c1e"
          stroke="#fff"
          strokeWidth="1.4"
          strokeLinejoin="round"
        />
      </svg>

      <div
        id="island"
        className={mode === "hidden" ? undefined : mode}
        role="button"
        tabIndex={0}
        aria-label="Live mock of the island panel. Activate to expand."
        aria-expanded={mode === "open"}
        onMouseEnter={open}
        onMouseLeave={armCollapse}
        onTouchStart={takeover}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            setMode(mode === "open" ? "hidden" : "open");
          }
          if (e.key === "Escape") setMode("hidden");
        }}
      >
        <div className="peek-line">
          <PixelCanvas kind="bot" state="question" />
          <span>api-gateway · waiting: "Retry with backoff, or pin the clock?"</span>
        </div>

        <div className="panel-body">
          <div className="quotas" aria-label="Claude usage quotas">
            <div className="quota-row">
              <span className="lbl">5 h</span>
              <span className="bar"><i style={{ width: "63%", background: "var(--sys-yellow)" }} /></span>
              <span className="pct">63%</span>
              <span className="reset">↺ 18:43</span>
            </div>
            <div className="quota-row">
              <span className="lbl">7 d</span>
              <span className="bar"><i style={{ width: "28%", background: "var(--sys-green)" }} /></span>
              <span className="pct">28%</span>
            </div>
          </div>

          <div className="cards">
            <button className="card" onClick={acknowledge}>
              <span className="card-head">
                <PixelCanvas kind="glyph" state="question" className="glyph" />
                <span className="title">Fix flaky auth test</span>
                <span className="state">waiting</span>
              </span>
              <span className="path">~/code/api-gateway</span>
              <span className="prompt">"Fix the flaky auth test in CI"</span>
              <span className="ctx">context 71%</span>
              <span className="ask-prompt">Retry with backoff, or pin the clock?</span>
              <span className="options">
                <span className="option"><span className="num">1</span><span className="lbl">Retry with backoff</span></span>
                <span className="option"><span className="num">2</span><span className="lbl">Pin the test clock</span></span>
              </span>
            </button>

            <button className="card">
              <span className="card-head">
                <PixelCanvas kind="glyph" state="finished" className="glyph" />
                <span className="title">Refactor peek pipeline</span>
                <span className="state">done</span>
              </span>
              <span className="path">~/code/island</span>
              <span className="prompt">"Refactor the peek pipeline"</span>
              <span className="summary">
                Coalesced peek bursts into one continuous surface; cross-fade race fixed.
              </span>
              <span className="facts">todos 3/3 · 2 files · 3:20</span>
              <span className="ctx">context 28%</span>
            </button>

            <button className="card">
              <span className="card-head">
                <PixelCanvas kind="glyph" state="working" className="glyph" />
                <span className="title">Migrate docs build</span>
                <span className="state">working</span>
                <span className="dur">12:04</span>
              </span>
              <span className="path">~/code/docs-site</span>
              <span className="prompt">"Migrate the docs build"</span>
              <span className="tool">tool: Bash</span>
            </button>
          </div>
        </div>
      </div>

      <p className="island-hint">
        {acknowledged ? (
          <span className="toast">
            acknowledged. In the real app this focuses the session's terminal window.
          </span>
        ) : (
          <>
            <span className="arrow">↑</span>{" "}
            <span className="gesture">Push your cursor against the top edge</span> and the island
            reveals, just like the real app.
            <small>
              At rest it shows nothing at all. Orange edges mean a session is waiting; click its
              card to acknowledge.
            </small>
          </>
        )}
      </p>
    </div>
  );
}
