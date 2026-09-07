// Pixel-art sprite engine, ported from the real sprite sheets (issue #11,
// planche C « Bots »). Everything draws into a 16×16 backing store; CSS
// upscales it with `image-rendering: pixelated`, so the art stays crisp at any
// size without shipping a single image file.

export type BotState = "working" | "sleeping" | "finished" | "question";
export type TileKind = "bot" | "glyph" | "isle";

export type Painter = (x: number, y: number, color: string) => void;

const ORANGE = "#f5a136";
const GREEN = "#4cd964";
const ZGREY = "#8b93a1";

const BOT_PAL = {
  metal: "#aeb6c2",
  shade: "#7d8694",
  screen: "#0d1117",
  code: "#57d47a",
};

const GLYPH: Record<string, string[]> = {
  q: ["##.", "..#", ".#.", "...", ".#."],
  z: ["###", ".#.", "###"],
  check: ["....#", "...#.", "#.#..", ".#..."],
  dots: ["#....", "#.#..", "#.#.#"],
};

function glyph(px: Painter, name: keyof typeof GLYPH, x: number, y: number, color: string): void {
  GLYPH[name].forEach((row, j) => {
    row.split("").forEach((ch, i) => {
      if (ch === "#") px(x + i, y + j, color);
    });
  });
}

/** Draws a glyph at 2× — what the session cards show, without the bot around it. */
function glyph2x(
  px: Painter,
  rowsDef: string[],
  x0: number,
  y0: number,
  color: string,
  maxCols = 99,
): void {
  rowsDef.forEach((row, j) => {
    row.split("").forEach((ch, i) => {
      if (ch !== "#" || i >= maxCols) return;
      px(x0 + 2 * i, y0 + 2 * j, color);
      px(x0 + 2 * i + 1, y0 + 2 * j, color);
      px(x0 + 2 * i, y0 + 2 * j + 1, color);
      px(x0 + 2 * i + 1, y0 + 2 * j + 1, color);
    });
  });
}

type Span = [row: number, from: number, to: number];

function rows(px: Painter, spans: Span[], color: string, ox = 0, oy = 0): void {
  spans.forEach(([row, from, to]) => {
    for (let x = from; x <= to; x++) px(x + ox, row + oy, color);
  });
}

/** The CRT bot: its state lives on its little screen. */
export function drawBot(px: Painter, state: BotState, f: number): void {
  const P = BOT_PAL;
  const oy = state === "finished" && f % 4 === 1 ? -1 : 0;
  const tip = {
    working: f % 2 ? P.code : P.shade,
    sleeping: P.shade,
    finished: GREEN,
    question: ORANGE,
  }[state];

  px(7, 1 + oy, tip);
  px(7, 2 + oy, P.shade);
  rows(px, [[3, 4, 11]], P.metal, 0, oy);
  for (let y = 4; y <= 9; y++) {
    px(3, y + oy, P.metal);
    px(12, y + oy, P.metal);
  }
  rows(px, [[10, 4, 11]], P.shade, 0, oy);
  for (let y = 4; y <= 9; y++) for (let x = 4; x <= 11; x++) px(x, y + oy, P.screen);
  px(2, 6 + oy, P.shade);
  px(13, 6 + oy, P.shade);
  px(5, 11, P.shade);
  px(10, 11, P.shade);
  rows(px, [[12, 4, 6], [12, 9, 11]], P.metal);

  if (state === "working") {
    const lines: Array<[number, number]> = [[4, 6], [8, 10], [5, 9], [4, 7], [6, 11], [5, 8]];
    for (let r = 0; r < 4; r++) {
      const seg = lines[(r + f) % lines.length];
      for (let x = seg[0]; x <= Math.min(seg[1], 11); x++) px(x, 5 + r + oy, P.code);
    }
  } else if (state === "sleeping") {
    px(7, 6, f % 2 ? "#3a4f66" : "#22303f");
    glyph(px, "z", 12, 1, ZGREY);
  } else if (state === "finished") {
    glyph(px, "check", 5, 5 + oy, GREEN);
  } else if (state === "question") {
    if (f % 3 !== 2) glyph(px, "q", 6, 4 + oy, ORANGE);
  }
}

/** The bot-screen glyph on its own, 2× — what a session card shows. */
export function drawGlyph(px: Painter, state: BotState, f: number): void {
  if (state === "finished") {
    const cols = [3, 4, 5, 5][f % 4];
    glyph2x(px, GLYPH.check, 3, 4, GREEN, cols);
    if (f % 4 === 3) px(14, 3, "#c9f4e4");
  } else if (state === "question") {
    glyph2x(px, GLYPH.q, 5, 3, f % 3 === 2 ? "#b87724" : ORANGE);
  } else if (state === "working") {
    glyph2x(px, [GLYPH.dots[Math.min(f % 4, 2)]], 3, 7, "#57d47a");
  } else if (state === "sleeping") {
    glyph2x(px, GLYPH.z, 5, 4 - (f % 2), ZGREY);
  }
}

const ISLE_PAL = {
  sand: "#e8d5a9",
  shade: "#c9a86a",
  trunk: "#a97c50",
  palm: "#57d47a",
  water: "#4aa8d8",
  glint: "#8fd0ef",
};

/** The pixel isle — the same art as the app icon. */
export function drawIsle(px: Painter, f: number): void {
  const P = ISLE_PAL;
  rows(px, [[14, 1, 14]], P.water);
  px(2 + (f % 2) * 2, 14, P.glint);
  px(13 - (f % 2) * 2, 14, P.glint);
  rows(px, [[11, 5, 10], [12, 4, 11]], P.sand);
  rows(px, [[13, 3, 12]], P.shade);
  px(8, 10, P.trunk);
  px(8, 9, P.trunk);
  px(8, 8, P.trunk);
  px(7, 7, P.trunk);
  px(7, 6, P.trunk);
  px(9, 7, P.trunk);
  const s = f % 2;
  px(6, 5, P.palm);
  px(5, 5 - s, P.palm);
  px(4, 6 - s, P.palm);
  px(3, 7 - s, P.palm);
  px(8, 5, P.palm);
  px(9, 5, P.palm);
  px(10, 6 + s, P.palm);
  px(11, 7 + s, P.palm);
  px(7, 4, P.palm);
  px(6, 3 + s, P.palm);
  px(8, 3, P.palm);
}

/** Animation rate per state, in frames per second. */
export const FPS: Record<string, number> = {
  working: 4,
  sleeping: 1.5,
  finished: 3,
  question: 2.5,
  isle: 1.5,
};

export function paint(
  ctx: CanvasRenderingContext2D,
  kind: TileKind,
  state: BotState,
  frame: number,
): void {
  const px: Painter = (x, y, color) => {
    if (x < 0 || x > 15 || y < 0 || y > 15) return;
    ctx.fillStyle = color;
    ctx.fillRect(x, y, 1, 1);
  };
  ctx.clearRect(0, 0, 16, 16);
  if (kind === "bot") drawBot(px, state, frame);
  else if (kind === "glyph") drawGlyph(px, state, frame);
  else drawIsle(px, frame);
}
