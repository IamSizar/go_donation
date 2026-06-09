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

## Admin credentials

Do not commit local admin credentials. Use [percentage/admin/config/auth.local.example.php](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/percentage/admin/config/auth.local.example.php) as the template for a local `auth.local.php` file.

## Flutter app setup

1. Open `humanitarian/` with Flutter.
2. Run `flutter pub get`.
3. Set the production API base URL in [humanitarian/lib/api/links.dart](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/humanitarian/lib/api/links.dart).
4. Build the app for your target platform.

## Deployment notes

See [DEPLOYMENT_NOTES.md](/Volumes/Sizar/easy_tech/test/run/r2/perccentage/DEPLOYMENT_NOTES.md) for the current hosting and API notes.
