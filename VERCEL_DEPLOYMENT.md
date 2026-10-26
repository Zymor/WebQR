# Vercel deployment for After Work

The Vercel project is `starling-gg/afterwork`; production is https://afterwork-livid.vercel.app.

## Why the previous deployment returned NOT_FOUND

The previous prebuilt artifact placed the Flutter source project inside `.vercel/output/static`. That directory contained `lib/`, `server/`, `.dart_tool/` and a SQLite database, but no compiled `index.html` at its root. Vercel successfully uploaded those files and marked the deployment Ready; this does not mean an application entry page exists. A request for `/` therefore returned Vercel's platform 404. That faulty deployment has been removed.

A Flutter app must be compiled first. Its deployable website is `build/web`, not the project root and not the `web` template directory. `build/` remains Git-ignored; the hosting build creates it from tracked source.

## Git-based builds

Import this repository with Root Directory `.` (the directory containing `pubspec.yaml` and `vercel.json`). Framework preset: Other. `vercel.json` sets the build command and output directory. `tool/vercel_build.mjs` installs Flutter 3.47.6 if needed, compiles the website, and validates the output. Do not set Root Directory to `build/web`, as that folder does not exist in a fresh Git checkout.

Set `SOCIAL_API` in Vercel to the HTTPS URL of a separately hosted backend, for example `https://your-api.example/api`. With no configured backend, the build uses `/api`, which is same-origin and does not connect to a visitor's localhost. No backend is deployed by this static configuration. Bookings, orders and accounts remain unavailable until the actual service and durable database are hosted and configured. Publishing the SQLite file cannot start the Python server and would expose data instead.

## Local prebuilt deployment

```powershell
$env:FLUTTER_BIN = 'C:\flutter\bin\flutter.bat'
node tool/vercel_build.mjs
node tool/package_vercel.mjs
npx vercel deploy --prebuilt --prod --scope starling-gg
```

Run from this repository after explicitly linking it to `afterwork`. The packager only copies the verified compiled website into `.vercel/output/static`; it does not copy source, databases, browser caches or local-network QR exports. It retains any prior packaging as a sibling snapshot rather than merging stale files into a release.

The compiler and packager reject missing bootstrap files, uncompiled `$FLUTTER_BASE_HREF` placeholders, and unsafe source/database files in the web output. `.vercelignore` excludes local build caches, databases, environment files and unrelated native source from source uploads.

## Routing and validation

The current application uses hash routes such as `/#/Home` and `/#/Table:T03`. Browsers do not send the hash to the server, so these request `/`; a catch-all rewrite is unnecessary. Do not rewrite every missing path to `index.html`: it can turn absent JavaScript and `/api` requests into HTML with status 200, hiding configuration failures.

After each release verify:

- `/` returns HTML, status 200.
- `/flutter_bootstrap.js` and `/main.dart.js` return JavaScript, status 200.
- `/after-work-favicon.png` returns PNG, status 200.
- `/server/social.sqlite3`, `/.dart_tool/package_config.json` and `/lib/main.dart` return 404.
- A missing backend endpoint remains a real error instead of returning HTML or fabricated success.

If every URL including `/` returns NOT_FOUND, inspect the production alias and deployment artifact first. If `/` works but a plain `/some-route` fails, investigate whether the client router expects path routing or hash routing. If the deployment URL is missing/deleted, changing application rewrites will not recreate it; redeploy and verify the alias.

Public table QR codes must be regenerated with the final public origin and valid backend table configuration; the old `192.168...` codes only work on their original Wi-Fi network.
