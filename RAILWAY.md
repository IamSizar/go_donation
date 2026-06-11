# Deploying `go_donation` on Railway

This repo is a monorepo with three parts:

| Folder          | What it is                  | Deploys on Railway?            |
| --------------- | --------------------------- | ------------------------------ |
| `backend/`      | Go API + PostgreSQL         | ✅ yes (a "service")           |
| `admin-web/`    | React admin dashboard (Vite)| ✅ yes (a "service")           |
| `humanitarian/` | Flutter mobile app          | ❌ no (built into an app, not hosted) |

The key idea: **each Railway service has a "Root Directory" setting**. Point each
service at the right folder and it builds only that part.

---

## 1. Postgres

In your Railway project: **New → Database → PostgreSQL**. Railway creates a
`DATABASE_URL` variable you'll reference from the backend.

## 2. Backend service (Go API)

Create a service from this GitHub repo, then in its **Settings**:

- **Root Directory:** `backend`
  (or leave it at the repo root — the root `Dockerfile` builds the same backend.
  Use one or the other, not both, for the API.)
- Railway detects the `Dockerfile` and builds it automatically.

**Variables** (Settings → Variables):

```
DATABASE_URL          = ${{Postgres.DATABASE_URL}}   # reference the Postgres service
RUN_MIGRATIONS        = 1                              # first deploy only-ish; safe to leave on
CORS_ALLOWED_ORIGINS  = https://<your-dashboard-domain>   # or *
ANTHROPIC_API_KEY     =                                # optional, enables the AI assistant
```

- `PORT` is injected by Railway; the server binds to it automatically.
- `RUN_MIGRATIONS=1` auto-creates the whole schema on a fresh DB and is a no-op
  afterwards (each migration is recorded in `schema_migrations` and runs once).

After it deploys, note the backend's public URL, e.g.
`https://backend-production-xxxx.up.railway.app`.

## 3. Dashboard service (admin-web)

Add another service from the **same** repo. In **Settings**:

- **Root Directory:** `admin-web`
- Railway reads `admin-web/railway.json` → builds with `npm run build`, serves
  the static `dist/` with `serve` on `$PORT`.

**Variables** (must be set **before** the build — Vite bakes them in):

```
VITE_API_BASE_URL = https://backend-production-xxxx.up.railway.app
```

(no trailing slash — the app appends `/api/...` itself). Make sure the backend's
`CORS_ALLOWED_ORIGINS` includes this dashboard's URL.

## 4. (Optional) repo-root service

If you connect a service at the **repository root** (no Root Directory set), the
root `Dockerfile` builds the **backend**. Give it the same variables as the
backend service. This is just an alternative to the `backend`-rooted service —
run one or the other.

---

## Mobile app (Flutter)

The Flutter app is not hosted on Railway. Before building it for release, point
it at your deployed backend in `humanitarian/lib/api/links.dart`:

```dart
const String baseUrl = 'https://backend-production-xxxx.up.railway.app/api/';
```

Keep the trailing `/api/`.

---

## Summary of services

| Railway service | Root Directory | Builder        | Key vars                                   |
| --------------- | -------------- | -------------- | ------------------------------------------ |
| Postgres        | —              | Railway plugin | —                                          |
| Backend (API)   | `backend`      | Dockerfile     | `DATABASE_URL`, `RUN_MIGRATIONS=1`, `CORS_ALLOWED_ORIGINS` |
| Dashboard       | `admin-web`    | Nixpacks       | `VITE_API_BASE_URL`                        |
| (root, optional)| `.` (root)     | Dockerfile     | same as Backend                            |
