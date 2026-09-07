import { useEffect, useRef } from "react";
import { FPS, paint, type BotState, type TileKind } from "./sprites";
import { useReducedMotion } from "./useReducedMotion";

interface Props {
  kind: TileKind;
  state: BotState;
  className?: string;
  /** CSS size in px; the backing store is always 16×16. */
  size?: number;
}

/**
 * One animated 16×16 pixel-art tile. Every tile drives its own rAF loop and
 * redraws only when its frame index changes, so a page full of them still
 * costs almost nothing. With reduced motion, it paints frame 0 and stops.
 */
export function PixelCanvas({ kind, state, className, size = 16 }: Props) {
  const ref = useRef<HTMLCanvasElement>(null);
  const reduced = useReducedMotion();

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    if (reduced) {
      paint(ctx, kind, state, 0);
      return;
    }

    let raf = 0;
    let last = -1;
    const fps = FPS[state] ?? 2;

    const loop = (t: number) => {
      const frame = Math.floor((t / 1000) * fps);
      if (frame !== last) {
        last = frame;
        paint(ctx, kind, state, frame);
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [kind, state, reduced]);

  return (
    <canvas
      ref={ref}
      className={className ? `px ${className}` : "px"}
      width={16}
      height={16}
      style={{ width: size, height: size }}
      aria-hidden="true"
    />
  );
}
