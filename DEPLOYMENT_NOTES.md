# Humanitarian App Deployment Notes

## Database

Import `humanitarianApp.sql` into the hosting MySQL database. The file now includes the original tables plus proposal-completion tables for beneficiary cases, sponsorships, in-kind donations, marketplace, city directory, marriage profiles, volunteers, partners, media posts, notifications, support tickets, and financial expenses.

The existing `donations` table was extended with:

- `reference_number`
- `donation_kind`
- `is_recurring`
- `recurring_interval`
- `delivery_status`
- `impact_note`

The existing `donations.campaign_id` column was changed to allow `NULL`, so general donations can be saved without being linked to a campaign.

## Hosting Configuration

Set these environment variables on the host, or edit `easy_tech_test/database/connection.php` once after upload:

- `DB_HOST`
- `DB_NAME`
- `DB_USER`
- `DB_PASS`
- `DB_PORT`
- `DB_CHARSET`

For many shared hosts, `DB_PORT` is `3306`. The local fallback remains `8889` for MAMP.

## Mobile API Base URL

Before building the Flutter app for production, update `humanitarian/lib/api/links.dart`:

```dart
const String baseUrl = 'https://your-domain.com/easy_tech_test/api/';
```

Keep the trailing `/api/`.

## New API Endpoints

- `api/community/`
- `api/marketplace/`
- `api/in_kind_donations/`
- `api/volunteers/`
- `api/partners/`
- `api/media/`
- `api/notifications/`
- `api/beneficiary_cases/`
- `api/sponsorships/`
- `api/marriage/`
- `api/support/`
- `api/reports/`

## Admin

The admin dashboard now links to `admin/proposal_modules.php`, which shows an overview of the new proposal-related tables. Each module card links to `admin/proposal_module_manage.php?module=...` for creating records and updating statuses.

## OTP

The mobile OTP flow is still demo/local as requested. It was not converted to a live OTP/SMS API.
