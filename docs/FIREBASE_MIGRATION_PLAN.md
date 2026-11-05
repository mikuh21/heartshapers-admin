# Heartshapers Firebase Migration (Admin)

## Current status — 2026-11-06

The admin dashboard runtime now uses Firebase Auth/custom claims, Firestore, Firebase Storage, and callable Cloud Functions. The current branch has book/game CRUD, taxonomy/settings management, optimization/recovery trackers, user and access management, payment review, admin audit logs, verification email, protected mobile asset URL issuance, OTP password reset, and server-validated cart submission. Supabase Edge Function source remains in the repository as legacy migration/reference material; the admin app and Functions packages no longer depend on the Supabase SDK.

Recent migration work also adds server-side cart total/entitlement checks, single-use hashed OTP reset tokens, UID-scoped payment-proof upload rules, private book/game asset signing, Firestore composite indexes, and safe mobile self-profile creation. The malformed escaped newlines in `functions/userManagement.js` were corrected so the Functions source parses.

## Current status — 2026-11-06

The confirmed production target is `brewing-connections-ce316`. The Android app (`com.heartshapers.app`) and Admin Web app are registered; Firestore `(default)` is STANDARD in `asia-southeast1`; Auth Email/Password and Blaze billing are enabled.

Completed:

- Deployed all 20 Cloud Functions on Node.js 22, Firestore Rules/indexes, and Storage Rules. `getProtectedBookPdfUrl` was subsequently updated and redeployed to translate legacy Supabase PDF references into Firebase Storage paths.
- Imported and reconciled source Firestore data. Seventeen Supabase users were matched by normalized email to Firebase Auth accounts, profile documents were created under their Firebase UIDs, and custom role/tier/legacy UID claims were set (5 admin, 2 super_admin, 10 user). One extra Firebase account remains unmapped and has no migrated role.
- Re-keyed 14 book purchases, 1 game purchase, 2 book access overrides, and 3 game access overrides to Firebase UID-based keys. Updated payment/admin ownership references and verified all current payment/purchase/access owner IDs map to Firebase Auth accounts.
- Replicated 602 game cards and 8 game rules into each game's subcollections while retaining legacy root collections.
- Configured function secrets for SMTP verification/reset delivery and OTP hashing. Do not print or commit their values.

Remaining / blocked:

- The project owner confirms the book PDFs and game PDFs are already in Firebase Storage. Inventory found 57 PDF objects (39 under `pdfs/`, 18 under `games/`); the 18 game PDFs span the 8 game-name folders. The current 8 Firestore game records have no `source_pdf_path`; the app uses Firestore game/card records.
- Compared the 42 book records with Storage by exact normalized title. Updated 39 `pdf_url` fields to verified Firebase object paths and preserved their prior values in `legacy_supabase_pdf_url`; readback confirmed the 39 paths exist. The owner will upload the remaining three PDFs later; those records stay unchanged until upload: Working with Integrity, The Spirit-Filled Home, and The Anchor and the Anvil.
- Web hosting is on DreamHost per the owner. Firebase Hosting is not configured; build the admin SPA and deploy its `dist/` output through the existing DreamHost workflow.
- Supabase Storage returns HTTP 402 `exceed_cached_egress_quota`, blocking source-side inventory/download of remaining non-PDF assets. Private game assets and payment proofs need an authorized private-object export path only if reconciliation shows they are absent; keep proof files private.
- The admin web app has not been deployed to Firebase Hosting in this migration. The updated mobile app must also be rebuilt/released. No end-to-end production cutover has been completed.
- Notifications have no active source table or mobile backend implementation in the inspected source.
- Validation: Admin Vite production build passed with a large-chunk advisory; `node --check functions/index.js` and `node --check functions/userManagement.js` passed. Android JS export passed with Hermes bytecode disabled. Full mobile `npm run lint` exits with `import/namespace` parser errors for imports of `ProfileScreen.js`; the file parses under Babel/Espree and targeted ESLint, and disabling the three affected import-analysis rules yields zero errors with 8 warnings. No automated test suite or Firebase emulator end-to-end/security tests are configured/run.

## Deployment source

This repository owns the admin web app, Cloud Functions, Firestore Rules/indexes, and Storage Rules. Backend resources have been deployed to `brewing-connections-ce316`; the admin web app still needs a Hosting release. Keep Supabase available and validate administrator separation, payment/cart atomicity, content access, soft deletion, upload recovery, and optimized asset-cache behavior before cutover.

## Security and data notes

- Client code cannot grant roles, verify payments, create purchases, change access overrides, or access protected book/game assets directly.
- Auth UID differences require a verified mapping for all historical purchases and access overrides.
- Never commit service-account credentials, SMTP/OTP secrets, production exports, or payment-proof files.
