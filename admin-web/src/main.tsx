import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { registerServiceWorker } from './lib/pwa'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

// PWA. Registered outside React because the worker's lifetime is the origin's,
// not any component's — it must survive route changes, sign-out and re-mounts.
// No-op in development; see src/lib/pwa.ts.
registerServiceWorker()
