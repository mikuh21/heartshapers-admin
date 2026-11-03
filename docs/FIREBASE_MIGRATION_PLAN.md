# Heartshapers Firebase Migration Plan (Admin)

## Objective
Move the React + Vite admin dashboard off Supabase while retaining the current dashboard workflows, records, file pipeline, role controls, payment review, and optimization trackers.

## Current source baseline
- Vite/React admin currently depends on `@supabase/supabase-js`; client setup is `src/lib/supabase.js`.
- `src/lib/adminUsers.js` invokes Supabase Edge Functions for user listing, role/status changes, and book/game access overrides.
- `src/lib/games.js` performs Firestore-replacement relevant direct Postgres and Storage operations (currently Supabase) for game records and asset upload.
- Supabase Edge Functions currently include `admin-management`, `admin-user-management`, OTP functions, and payment verification email function.
- Supabase migrations hold important domain rules: book/game purchases, VIP access, user access overrides, payment workflows, soft-deletion, audit logs, and PDF entitlement logic.

## Firebase target responsibilities
- Firebase Authentication with custom claims for `admin` / `super_admin`; enforce claims on backend.
- Cloud Firestore for books/games/catalog taxonomy, users/profile records, purchase/payment records, access overrides, app settings, upload settings, audit logs, and optimization progress.
- Cloud Storage for covers, PDFs, game assets, avatars, and payment proof files.
- Cloud Functions for admin user management, content mutation, payment verification/rejection, cart review transaction, OTP/email flows, signed/protected asset access, and audit writes.
- Security Rules and server-side validation: clients must not approve payments, assign privileged claims, create purchase entitlements, or override protected records.

## Migration sequence
1. Inventory every Supabase table/query/RPC/function/bucket and its callers in dashboard pages and libraries.
2. Define Firestore document contracts and Storage object path mapping; retain legacy content IDs where practical.
3. Implement Firebase web config through Vite environment variables; use no service-account secret in browser code.
4. Build auth adapter and role claim checks, then user management via callable/HTTPS Cloud Functions.
5. Implement data adapters for books, games, taxonomy, app settings, upload settings, users, access overrides, purchases, payments, admin audit, and soft deletion.
6. Port upload pipelines to Firebase Storage, preserving optimization and stable paths, resumable upload handling, content types, cache headers, and recovery tracker semantics.
7. Port payment-review operations to trusted Functions with Firestore transactions (including multi-item cart review atomicity).
8. Port OTP/email functions, with secrets in managed Secret Manager; do not expose SMTP/OTP pepper.
9. Implement Firestore and Storage Rules, automated emulator tests, and export/import reconciliation.
10. Validate admin build and flows, then coordinate cutover with mobile. Keep Supabase available until both apps pass.

## Critical preservation requirements
- Preserve admin vs super-admin privilege separation.
- Preserve purchase records and VIP entitlements; user UID mapping must remain explicit.
- Preserve verified-purchase protection on access override operations.
- Preserve soft-delete timestamps and retain existing content/storage references.
- Preserve optimization progress/retry/recovery keys and never reprocess already optimized assets needlessly.
- Payment approval/rejection and access grants are server-trusted operations only.
- No service-account JSON, production data dumps, secrets, or payment proof files committed to Git.

## Verification checklist
- Admin login and claim validation; user listing/status/access changes.
- Book/game CRUD, taxonomy filters, uploads, optimizations, and soft deletion.
- Payment queue, verify/reject, and multi-item cart atomicity.
- Audit log, app settings, upload limit settings, OTP/email flows.
- Firestore/Storage Rules emulator tests, Vite production build, data counts and sampled ownership reconciliation.
