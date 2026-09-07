import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Relative base: the built `dist/` drops into any path on any host — the root
// of a domain, or a sub-directory — without a rebuild.
export default defineConfig({
  plugins: [react()],
  base: "./",
  build: { outDir: "dist", assetsDir: "assets", sourcemap: false },
});
