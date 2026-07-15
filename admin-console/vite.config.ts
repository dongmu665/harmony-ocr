import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

export default defineConfig({
  base: "/admin/",
  plugins: [react()],
  build: {
    outDir: "../server/src/main/resources/static/admin",
    emptyOutDir: true,
    assetsDir: "assets",
    rollupOptions: {
      input: {
        console: resolve(__dirname, "console.html")
      },
      output: {
        entryFileNames: "assets/[name].js",
        chunkFileNames: "assets/[name].js",
        assetFileNames: "assets/[name][extname]"
      }
    }
  }
});
