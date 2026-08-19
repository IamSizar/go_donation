# BalanceNex — donations & community platform

Three deployables in one repository:

| Path | What it is |
|---|---|
| `backend/` | Go API (Gin) on PostgreSQL. Deployed to Railway. |
| `admin-web/` | Staff dashboard — React + TypeScript + Vite. |
| `humanitarian/` | The Flutter mobile app (iOS + Android). |

Supporting docs: [RAILWAY.md](RAILWAY.md) for deploy, [HANDOFF.md](HANDOFF.md)
for working agreements, [TERMINOLOGY.md](TERMINOLOGY.md) for naming,
[DEPLOYMENT_NOTES.md](DEPLOYMENT_NOTES.md).

## Run the backend

```bash
cd backend
cp .env.example .env      # then set DATABASE_URL
go run ./cmd/server
```

`DATABASE_URL` is the only variable required to boot — everything else degrades
to a documented default. It listens on `PORT` (8080 by default).

Apply migrations by setting `RUN_MIGRATIONS=1` on first boot; they are tracked
in `schema_migrations`, so later boots are no-ops.

### Configuration that changes behaviour

| Variable | Effect when unset |
|---|---|
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_PUBLIC_BASE_URL` | Uploads go to local disk under `UPLOAD_DIR` instead of Cloudflare R2. **A container filesystem is ephemeral — every deploy destroys local uploads.** Setting these five is what makes uploads survive. Partial configuration is a boot failure, deliberately, so a typo cannot look like success. |
| `OTPIQ_API_KEY` | No real SMS. Sign-in OTP falls back to `OTP_DEMO_CODE` when `OTP_DEMO_ENABLED=1`. |
| `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` | No email. Main-admin change confirmation refuses (503, fails closed); the permission-change second factor degrades to returning its code in-band. |
| `SUPPORT_USER_ID` | Support chat returns 503 — the in-app «التواصل مع الدعم» cannot open. An `app_settings` row `support_user_id` takes priority and needs no redeploy. |
| `ANTHROPIC_API_KEY` | The in-app assistant has no model to call. |
| `CORS_ALLOWED_ORIGINS` | The dashboard's origin must be listed here to call the API. |
| `RUN_SCHEDULER` | Background jobs do not run. |

## Run the dashboard

```bash
cd admin-web
npm install
npm run dev          # Vite; proxies /api to the target in .env
npm run build        # tsc -b && vite build — the real typecheck
npm run check:labels # every controlled value has a human label
```

`tsc --noEmit` is **vacuous** in this repo: the root tsconfig has `"files": []`
with project references, so it type-checks nothing. Use `npm run build`, or
`tsc -b`.

## Run the mobile app

```bash
cd humanitarian
flutter pub get
flutter run
flutter analyze && flutter test
```

The backend it talks to is `baseUrl` in
[lib/api/links.dart](humanitarian/lib/api/links.dart) — one constant, changed in
one place, which is how you point the app at a local server.

## Testing the Go backend

```bash
cd backend
go test ./...              # 111 tests — unit only
./scripts/test-with-db.sh  # 282 tests — everything
```

**The difference matters.** 171 of the 282 backend tests skip themselves unless
`TEST_DATABASE_URL` points at a Postgres they can migrate and write to. A bare
`go test ./...` therefore reports success having run 39% of the suite, and says
nothing about the 171 it stepped over — which are the delete guards, permission
gates, privacy rules and account-status checks, i.e. the behaviour where a
silent regression costs most.

`scripts/test-with-db.sh` starts a throwaway Postgres in Docker, runs the whole
suite against it, and removes the container afterwards. It passes any arguments
through to `go test`:

```bash
./scripts/test-with-db.sh ./internal/handlers/ -run SignupDelete
```

Hand the tests an EMPTY database — each package applies the migrations itself,
so pre-migrating makes the run fail with "relation already exists".

## Secrets

No secrets in the repository, ever — including history, comments and test
files. `backend/.env.example` lists the keys with no values; real values live in
the Railway service variables.

## Deployment

Railway builds from `main`. Both services deploy from this repository — see
[RAILWAY.md](RAILWAY.md), and [DEPLOYMENT_NOTES.md](DEPLOYMENT_NOTES.md) for the
current hosting notes.

Migrations run in the pipeline via `RUN_MIGRATIONS=1` and are expected to stay
backward-compatible for one release, so a rollback does not strand the schema.
