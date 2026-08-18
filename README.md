# Donations App Sizar

This repository contains the source for the donations platform in three parts:

- `percentage/`: PHP web app, admin panel, and API endpoints
- `humanitarian/`: Flutter mobile application
- `humanitarianApp.sql`: MySQL database dump for the platform

## Project layout

```text
.
|-- percentage/
|-- humanitarian/
|-- humanitarianApp.sql
|-- DEPLOYMENT_NOTES.md
`-- humanitarian/sql/
```

## Backend setup

1. Upload the `percentage/` folder to your PHP hosting environment.
2. Import `humanitarianApp.sql` into MySQL.
3. Configure database credentials with environment variables:
   - `DB_HOST`
   - `DB_NAME`
   - `DB_USER`
   - `DB_PASS`
   - `DB_PORT`
   - `DB_CHARSET`

The backend connection file is [percentage/database/connection.php](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/percentage/database/connection.php).

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

## Admin credentials

Do not commit local admin credentials. Use [percentage/admin/config/auth.local.example.php](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/percentage/admin/config/auth.local.example.php) as the template for a local `auth.local.php` file.

## Flutter app setup

1. Open `humanitarian/` with Flutter.
2. Run `flutter pub get`.
3. Set the production API base URL in [humanitarian/lib/api/links.dart](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/humanitarian/lib/api/links.dart).
4. Build the app for your target platform.

## Deployment notes

See [DEPLOYMENT_NOTES.md](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/DEPLOYMENT_NOTES.md) for the current hosting and API notes.
