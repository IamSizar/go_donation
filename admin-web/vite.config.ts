import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Dev server proxies /api to the Go backend on :8080 so the SPA can call
// the API at the same origin during development (no CORS plumbing needed).
export default defineConfig({
  plugins: [react()],
  server: {
    // host: true binds to 0.0.0.0 so the dev server is reachable from
    // other devices on the LAN (real phones running the Flutter app,
    // a teammate's laptop, etc.). Localhost-only is the Vite default;
    // we override it so the admin SPA works the same way the Go API does.
    host: true,
    // Honor the PORT assigned by the tooling/preview harness when present;
    // fall back to Vite's conventional 5173 for plain `npm run dev`.
    port: process.env.PORT ? Number(process.env.PORT) : 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/images': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
})
