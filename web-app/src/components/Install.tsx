import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

const CMD =
  "curl -fsSL https://raw.githubusercontent.com/Taklin1/island/main/scripts/install.sh | sh";

/** The install one-liner, click-to-copy, shrunk to stay on a single line. */
export function Install() {
  const [copied, setCopied] = useState(false);
  const codeRef = useRef<HTMLElement>(null);

  const copy = useCallback(() => {
    navigator.clipboard.writeText(CMD).then(() => setCopied(true));
  }, []);

  useEffect(() => {
    if (!copied) return;
    const t = window.setTimeout(() => setCopied(false), 1600);
    return () => clearTimeout(t);
  }, [copied]);

  // Fit the command on ONE line by shrinking the font to the module width.
  useLayoutEffect(() => {
    const fit = () => {
      const el = codeRef.current;
      if (!el) return;
      el.style.fontSize = "13px";
      const scale = el.clientWidth / el.scrollWidth;
      if (scale < 1) {
        el.style.fontSize = `${Math.max(6, Math.floor(13 * scale * 100 * 0.98) / 100)}px`;
      }
    };
    fit();
    window.addEventListener("resize", fit);
    if (document.fonts?.ready) void document.fonts.ready.then(fit);
    return () => window.removeEventListener("resize", fit);
  }, []);

  return (
    <div className="install">
      <div className="terminal">
        <div className="term-bar">
          <span />
          <span />
          <span />
          <em>{copied ? "copied ✓" : "install · zsh"}</em>
        </div>
        <button
          className="term-body"
          onClick={copy}
          aria-label="Copy the install command"
          title="Click to copy"
        >
          <code ref={codeRef}>
            <span className="p">$ </span>
            {CMD}
          </code>
        </button>
      </div>
      <ul className="install-notes">
        <li>no Gatekeeper dialogs</li>
        <li>no sudo, installs to ~/Applications</li>
        <li>the same script is the updater</li>
      </ul>
    </div>
  );
}
