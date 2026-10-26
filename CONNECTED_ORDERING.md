# After Work connected ordering platform

Customer: https://afterwork-livid.vercel.app
Staff: https://afterwork-admin.vercel.app
Staff Flutter source: `../AfterWorkAdmin/admin` relative to this repository's parent folder (actual sibling layout: `DemoQR/WebQR` and `DemoQR/AfterWorkAdmin/admin`).

## Current deployment prerequisite

The Node/PostgreSQL backend and both Flutter interfaces are implemented. Neon `afterwork-orders` has been provisioned on the explicit free_v3 plan in Singapore and connected to the Vercel `starling-gg/afterwork` project for Production and Development. The staff frontend is a separate deployed application. The initial owner must choose their own credentials using the private setup link after deployment.

The integration command selects the free plan explicitly:

```powershell
npx vercel integration add neon --name afterwork-orders --plan free_v3 --metadata region=sin1 --metadata auth=false --no-env-pull --environment production --environment development --scope starling-gg
```

The provider terms must be completed by the account owner. If a database was created manually, connect its secret PostgreSQL URL as `DATABASE_URL` to **afterwork**, not the separate static staff project. Never prefix this variable with a frontend-public prefix or commit it. The free plan must not be upgraded without the owner's approval. Storage/compute limits apply; monitor provider usage and backups.

## Architecture

- Flutter customer app preserves existing images, blue branding and supplied logo.
- Separate Flutter staff app resides in the user's `AfterWorkAdmin/admin` folder. It has protected login, live order cards, kitchen view, history/search/table/status/date filters, menu price/availability editing, table management/QR downloads, staff role management and venue settings.
- Vercel Node function `api/index.mjs` dispatches `/api/*` requests using `backend/http.mjs` and `backend/platform.mjs`.
- Durable PostgreSQL schema and safe additive initialization live in `backend/schema.mjs`. Five table records and the existing six menu products are seeded on first initialization, without overwriting existing menu/table edits.
- The existing Python/SQLite server remains a local legacy application. It does not power the new public ordering workflow.

## Ordering and privacy

A QR identifies T01–T05. The backend validates that the table and every dish remain active, calculates integer-cent totals/tax, and validates prices again within the insert transaction. The order saves the table name and item names/prices as snapshots. Notes are saved on both item and order records.

Customers review the server quote before submitting. Their browser creates a secure access token and retry key before the request; only the token hash is stored on the server. The retry key is transaction-locked, so retried/concurrent submissions cannot duplicate an order. Browser storage holds a cart, a pending retry pointer and the customer's own order reference/access token; it is not the operational database. Staff data is never available through a public list endpoint.

Workflow: `new → accepted → preparing → ready → served → completed`, with rejection/cancellation reasons required. Changes are validated, transactional and retained in status history/audit logs. Every submitted order stays **unpaid**, with pay-at-counter instructions. There is no online payment verification provider, and status changes cannot mark an order paid.

## Staff authentication and initial owner

Passwords are salted/scrypt-hashed. Staff login returns a random session token; only its hash is stored in PostgreSQL, with a 12-hour expiry. Staff sessions are held in the browser tab's session storage to survive refresh; no credentials are embedded in the application. Disabling/editing staff access revokes that account's sessions. Owner-only account administration prevents staff escalation. Managers can manage tables/menu/settings; kitchen staff can operate permitted order states.

The first owner is created via a secret, expiring bootstrap link. Do not create an unprotected first-user registration endpoint. After connecting the database, run from `WebQR`:

```powershell
node tool/prepare_owner_setup.mjs https://afterwork-admin.vercel.app
```

This configures only the secret hash/expiry and allowed staff origin in Vercel. The private URL is saved in ignored `.env.owner-setup.local`. Redeploy the API, then the owner opens that private link and enters their own email/password. It works only once, expires after eight hours, and refuses setup if a staff account already exists. Do not share or commit the bootstrap file. Remove the bootstrap hash/expiry environment variables after the owner account exists.

## Live delivery and recovery

The dashboard opens authenticated `GET /api/staff/stream` via fetch streaming with an Authorization header. The server sends revisioned full snapshots over SSE, checks the session repeatedly, and rotates the connection after 45 seconds. PostgreSQL retains all orders across reconnects. The dashboard replaces its canonical snapshot instead of appending cards, avoiding duplicate displays. If streaming fails, it visibly reconnects and polls every five seconds. Customer order screens poll their token-protected status every five seconds, and recover the most recent order on refresh. No sound is played automatically.

Public ordering is rate-limited in PostgreSQL, not only process memory. CORS permits the configured customer/staff origins and local development origins only outside production. Table QR links do not prove physical presence; keep staff acceptance enabled and disable ordering or a table when needed. Operational logs omit request bodies, access tokens, session secrets and database connection strings.

## Builds and deployment

Run cloud source deployments from `WebQR` so Vercel includes the Node API. `vercel.json` builds Flutter and routes `/api/*` to the function. Do **not** use the old static-only packager for the combined project; it intentionally refuses now that an API exists. The public database schema is created on a successful first connection, under an initialization lock.

```powershell
npm ci
npm run test:api
flutter analyze
flutter test
npx vercel deploy --scope starling-gg
```

Validate the preview before promotion. The staff project is a separate static Flutter build; its `AFTERWORK_API` defaults to the public customer site's `/api`. `STAFF_ORIGIN` is configured on the backend as `https://afterwork-admin.vercel.app`. The owner can configure customer/staff URLs in Settings; use HTTPS production origins. QR codes keep their table IDs when table names change.

## Backups

Neon provides database tooling and plan-dependent recovery features; verify retention for the chosen plan rather than assuming paid backup guarantees on the free tier. `node tool/backup_database.mjs` creates a private, consistent PostgreSQL export with operational data and staff password hashes, excludes live sessions, and writes only a Git-ignored `*.backup.json` file. Store encrypted/offline backups securely, schedule provider backups as appropriate, and verify restoration before relying on this operationally. No backup is publicly hosted.

## Verification completed locally

- 12 real PostgreSQL-engine tests (PGlite for isolated tests) exercise schema constraints, table validation, quantities/notes, atomic idempotency, access restrictions, unpaid status, full status workflow/reasons, immutable historical snapshots, staff authorization, closing ordering, authenticated SSE snapshots, and persistence after database reopening.
- Customer Flutter tests verify Table 03 review, one submission, secure access token, payment instructions, status updates, cart arithmetic, search, and mobile navigation.
- Staff Flutter tests verify protected login, mobile layout, a Table 03 order with quantity/notes, and accepting it into preparation.

These tests do not substitute for the final hosted acceptance run. Cloud acceptance checklist: connected hosted database, owner setup, customer QR scan/order, authenticated staff receipt, status propagation, reconnection testing, and a phone check outside the restaurant Wi-Fi. No fake successful deployment/booking/payment is substituted when a provider is unavailable.

## Hosted acceptance result

The public end-to-end check passed against the hosted Neon database: a Table 03 guest order with two dishes arrived in the authenticated SSE staff feed, duplicate concurrent submissions returned one saved order, staff changed its status through accepted/preparing/ready/served/completed, the customer endpoint reflected those changes, reconnecting recovered the saved order, payment stayed unpaid, and unauthorized access was rejected. The temporary test order/account were removed afterward; the operational database remained at zero orders, zero staff accounts, and five tables before handoff.

All five public table endpoints were verified over HTTPS. Source/database/environment paths remained 404. The initial private owner setup token was validated without creating an account by deliberately submitting an invalid form; the owner must choose their own credentials. Physical phone-camera scanning outside the restaurant Wi-Fi has not been directly observed.
