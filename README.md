# After Work

A Flutter hospitality web application built in the existing DemoQR project. The product detail layout follows the supplied reference: warm ivory, forest green, terracotta, large photography and generous spacing. Manrope and Cormorant Garamond are bundled for offline rendering.

## Run locally

From this directory, open two terminals:

```powershell
python server/app.py
```

```powershell
flutter pub get
flutter run -d chrome --web-port 8080
```

The API binds to `127.0.0.1:8787`. The frontend can use a different API with `--dart-define=SOCIAL_API=https://your-host/api`. This implementation is a **local development system, not a production deployment**. The development API deliberately accepts browser requests only from localhost and 127.0.0.1.

To serve a release build:

```powershell
flutter build web
python -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open http://127.0.0.1:8080. The initial product screen reflects the supplied image; Home is linked from the brand and navigation. Pages use hash URLs with browser back/forward support.

## Administrator setup

No shared/default admin password exists. Provision an administrator interactively:

```powershell
python server/app.py --create-admin manager@example.com
```

Use Account in the footer/mobile menu to sign in, then Admin. The CLI prompts for a password without echoing it. Menu editing uses a validated JSON editor; prices are integer USD cents and images select bundled assets. Archive items by setting `available` to false. Events start as drafts until published. Settings control contact details, opening hours, booking duration, tax basis points and ordering availability.

## Working local functionality

- Product details, shared menu collection, search, experience/category/price/vegetarian filters, allergen information, favorites and cart quantity controls.
- Local browser persistence for guest bags/favorites; authenticated favorites stored in SQLite. Sign in again after a browser refresh; session secrets are held in memory rather than browser local storage.
- Server-backed menu management; edits update the public menu on refresh/navigation reload.
- Actual availability calculated from configured table sizes, hours, blocked dates and overlapping bookings. Ninety minute demo duration; slots use Asia/Phnom_Penh (UTC+7).
- Atomic reservation and event-registration transactions prevent concurrent capacity conflicts. Past bookings and duplicated reservations are rejected. Guest booking retrieval uses a private access token. Online cancellation closes two hours before a booking.
- Account registration/login/logout, profile updates, reservation/order history, account deletion and server-enforced role checks. Passwords use scrypt, sessions expire, and mutation endpoints are rate limited.
- Demonstration pickup checkout validates current database prices and availability. Integer-cent totals and configurable tax rounding. Checkout retry keys prevent duplicate orders. Every order remains unpaid; only an eventual verified provider integration should change that.
- Order status transitions, reservation statuses, operational dashboard, menu/event management, date blocks, venue settings and audit history.
- Database-backed events with sold-out/cancelled states; gallery filtering and image dialogs; configurable contact details; consent records and token-based unsubscribe.
- Responsive desktop/mobile layouts, labelled controls, focus-capable standard Flutter widgets, form validation and visible errors.

All seed products, hours, capacities and operations are **demonstration data**, clearly identified in the UI. An actual database confirmation is a local demo record, never a booking at an operating venue. SQLite files live in `server/social.sqlite3` by default and are ignored by Git. Set `SOCIAL_DB` to change the path. Back up this file if retaining your local records.

## Validation

```powershell
flutter analyze
flutter test
python -m unittest discover -s server -v
flutter build web
```

Widget tests cover cart arithmetic, search filtering and mobile navigation/layout. API tests exercise real HTTP requests, account access controls, administrator menu edits, persistent records, simultaneous table conflicts, event capacity, closed dates, past bookings, newsletter consent, current-price validation and idempotent order submission.

## Production requirements and remaining scope

This is not the entire production platform described in the master brief. The following still require implementation or supplied business/provider configuration:

- Deploy behind HTTPS with a production application server/reverse proxy, durable managed database or backed-up SQLite storage, monitored backups, hardened request limits, and distributed rate limiting. The bundled Python HTTP server is development-only. No public deployment was performed.
- Email verification, password reset delivery, booking/cancellation notifications and newsletter campaigns need a transactional email provider. Password reset explicitly returns unavailable instead of pretending to send. Accounts are marked unverified. No outbound messages are sent.
- Payment/KHQR integration and verified webhooks, promotions, refunds and fulfillment provider connections are absent. No payment/card data is collected, and no sales are represented as verified revenue.
- Supply genuine business identity, location, contact details, final legal documents, taxes, cancellation policy, hours, real seating inventory, product data and photography before launch. Policy text is development disclosure, not final legal terms.
- Production account recovery, email verification enforcement, staff assignment rules, staff/user administration, secure image uploads, product extras/variants, inventory, advanced reports and analytics remain to be built. Staff can work with local operations; assignment-specific permissions are not yet modeled.
- Khmer translation management, a Khmer font, language switcher, KHR conversion configuration and complete localization remain outstanding. USD is the only displayed currency. Do not infer an exchange rate.
- Event category/date filters, registration management, detailed content CMS, promotional rules and media uploads are not yet implemented. Admins can manage event content/capacity/status with the supported editor.
- Flutter web does not provide server-rendered semantic pages or the full SEO requested by the brief. Titles/manifest metadata are configured, but production SEO, sitemap/structured data, comprehensive accessibility auditing and cross-browser testing remain outstanding.
- Menu data falls back to clearly labelled bundled sample data when the service is offline. Reservations/orders/authentication never fabricate a successful server response. No currency rates, addresses, star reviews or sales statistics were invented.

## Asset sources

Bundled photographs are from Unsplash, used as demonstration serving/interior inspiration:
- Dessert: https://images.unsplash.com/photo-1488477181946-6428a0291777
- Sandwich: https://images.unsplash.com/photo-1528735602780-2552fd46c7af
- Chicken: https://images.unsplash.com/photo-1562967914-608f82629710
- Sushi: https://images.unsplash.com/photo-1579871494447-9811cf80d66c
- Coffee: https://images.unsplash.com/photo-1442512595331-e89e73853f31
- Interior: https://images.unsplash.com/photo-1414235077428-338989a2e8c0

Fonts: Google Fonts Manrope and Cormorant Garamond, distributed under the SIL Open Font License. See bundled OFL files in assets/fonts.

## After Work — separate QR for each of five tables

The initial restaurant tables are `T01` through `T05`. Each is a separate persistent database record, with its own name, capacity, area and active status. Each QR encodes a distinct URL such as `http://192.168.0.102:8080/#/Table:T01`. Scanning opens the menu with that table selected; submitted orders save its validated `table_id`. The selected table persists in this browser until cleared or replaced by another scanned code. A QR code identifies a table; it does not authenticate the person scanning it.

Open **Tables** from the navigation to see all five codes. Download individual labelled PNG cards using each card’s PNG button. Managers can add any number of additional tables, edit names/capacities/areas, or deactivate a table. Table IDs and existing links remain stable when names change. Duplicate IDs and inactive table orders are rejected by the API. Sign in with a manager/super-admin account to manage tables; provision the initial administrator with the CLI command above.

Current local QR website address: `http://192.168.0.102:8080` (the computer's Wi-Fi IP at setup time). All five initial SVGs and a printable sheet are in `qr-codes/`:

- `after-work-T01.svg` through `after-work-T05.svg`
- `after-work-tables.html` — open and choose Print table cards

To regenerate the printable sheet from current database tables after adding tables or changing the website address:

```powershell
dart run tool/export_qr.dart
```

For phone access on the same Wi-Fi network, run:

```powershell
python server/app.py --host 0.0.0.0
flutter build web --dart-define=SOCIAL_API=http://192.168.0.102:8787/api
python -m http.server 8080 --bind 0.0.0.0 --directory build/web
```

The website URL setting allows that exact browser origin through the API's CORS policy. Localhost origins continue to work. Ports 8080 and 8787 must be reachable on the private network; no firewall rules were changed automatically. Keep both servers running. If your Wi-Fi IP changes, update the website address in Tables, rebuild with the new API address, and regenerate/reprint QR cards. A stable HTTPS production domain avoids this local-network limitation.
