import { useState } from "react";
import { Features } from "./components/Features";
import { Footer } from "./components/Footer";
import { Hero } from "./components/Hero";
import { IslandStage } from "./components/IslandStage";
import { Requirements } from "./components/Requirements";
import type { BotState } from "./sprites";

export function App() {
  // One waiting session is pending until the visitor acknowledges it: that
  // single fact drives the edge glow and the menu-bar mascot, exactly like the
  // aggregated state does in the app.
  const [acknowledged, setAcknowledged] = useState(false);
  const menubarState: BotState = acknowledged ? "working" : "question";

  return (
    <>
      <div id="lisere" className={acknowledged ? undefined : "on"} aria-hidden="true" />

      <IslandStage acknowledged={acknowledged} onAcknowledge={() => setAcknowledged(true)} />

      <div className="wrap">
        <Hero />
        <Features menubarState={menubarState} />
        <Requirements />
        <Footer />
      </div>
    </>
  );
}
