import { PixelCanvas } from "../PixelCanvas";
import { Install } from "./Install";

export function Hero() {
  return (
    <header className="hero">
      <p className="eyebrow">macOS · for Claude Code</p>
      <PixelCanvas kind="isle" state="working" className="hero-logo" size={56} />
      <h1>
        island<span className="tld">.</span>
      </h1>
      <p className="tagline">Your Claude Code sessions, Dynamic Island-style.</p>
      <p className="sub">
        A floating panel that stays hidden while your agents work, and catches your attention the
        moment one finishes, or stops to ask you a question.
      </p>
      <Install />
    </header>
  );
}
