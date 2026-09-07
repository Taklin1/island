import { PixelCanvas } from "../PixelCanvas";
import type { BotState } from "../sprites";

interface Props {
  /** Mirrors the most pressing state across sessions, like the real menu bar. */
  menubarState: BotState;
}

export function Features({ menubarState }: Props) {
  return (
    <section>
      <h2>What it does</h2>

      <div className="grid">
        <div className="feat">
          <div className="state-line">
            <span className="chip w">waiting</span>
            <span className="chip d">done</span>
            <span className="chip">working</span>
            <span className="chip">idle</span>
          </div>
          <h3>States, ranked by urgency</h3>
          <p>
            Every session is ranked <b>waiting &gt; done &gt; working &gt; idle</b>. The same
            priority drives the menu-bar sprite, the edge glow and the card order, so the most
            pressing thing always surfaces first.
          </p>
        </div>

        <div className="feat">
          <h3>Summaries</h3>
          <p>
            What a finished turn actually produced: last assistant message, todos, files touched.{" "}
            <b>Extracted locally from the transcript</b>, never an extra LLM call.
          </p>
        </div>

        <div className="feat">
          <h3>Quotas</h3>
          <p>
            Your Claude usage as gauges at the top of the panel: the <b>5-hour</b> and{" "}
            <b>7-day</b> windows, plus per-session context. No more guessing when the window resets.
          </p>
        </div>

        <div className="feat">
          <h3>Click-to-focus</h3>
          <p>
            Click a card and land on that session's <b>exact terminal window</b>. Focusing the
            terminal is also how you acknowledge: the edge glow goes out one session at a time.
          </p>
        </div>

        <div className="feat">
          <h3>Reply from the island</h3>
          <p>
            When an agent asks a question, its options show up as buttons. Pick one and the
            keystroke is injected into <b>that session's terminal</b>, and only when the target
            window is identified with certainty, never anywhere else.
          </p>
        </div>

        <div className="feat">
          <h3>Notifications that don't nag</h3>
          <p>
            A brief <b>Peek</b> when something happens, a colored <b>edge glow</b> that persists
            until you act (orange for waiting, green for done), and one macOS notification per
            event. Looking never counts as handling.
          </p>
        </div>
      </div>

      <div className="quiet">
        <div>
          <h3>Quiet by default</h3>
          <p>
            The island shows <b>nothing</b> while agents are simply working. It comes out on a
            Peek, or when you push the cursor against the top edge of the screen, full-screen apps
            included. A pixel-art bot per session encodes its state on its little CRT screen:
            scrolling code, a green check, an orange question mark.
          </p>
          <span className="menubar-demo">
            <PixelCanvas kind="bot" state={menubarState} size={18} />
            <span>14:32</span>
          </span>
          <span className="menubar-cap">
            the same bot lives in your menu bar, showing the most pressing state
          </span>
        </div>

        <div>
          <h3>Local, terminal-native</h3>
          <p>
            A small HTTP server on <b>127.0.0.1</b> receives Claude Code hook events; nothing
            leaves your machine. Distribution is terminal-native too: a curl one-liner installs the
            latest signed release. <b>No .dmg, no App Store, no notarization detour.</b>
          </p>
        </div>
      </div>
    </section>
  );
}
