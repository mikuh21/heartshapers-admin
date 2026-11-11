# HeartShapers Admin

A simple React + Vite admin website for the current HeartShapers Supabase database.

## Current database scope

The confirmed table is `books` with:

- `id` uuid
- `title` text
- `cover_image_url` text
- `pdf_url` text
- `pillar` text
- `subcategory` text
- `created_at` timestamp
- `is_locked` bool

The admin app does not invent additional database fields.

## Setup

1. Install Node.js.
2. Run:

```bash
npm install
```

3. Fill in `.env`:

```env
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_FIREBASE_API_KEY=...
VITE_FIREBASE_AUTH_DOMAIN=...
VITE_FIREBASE_PROJECT_ID=...
VITE_FIREBASE_STORAGE_BUCKET=...
VITE_FIREBASE_MESSAGING_SENDER_ID=...
VITE_FIREBASE_APP_ID=...
```

4. Create a Supabase Auth user for the administrator (database access).
5. Create or reuse a Firebase Auth account with an admin role for the same person. Uploads go to Firebase Storage, so this account is required by the deployed Storage rules.
6. Configure `books` table RLS in Supabase so the authenticated admin can read/insert/update/delete rows.
7. Run:

```bash
npm run dev
```

## Important security note

This first version uses Supabase Auth and the `books` table only. There is no admin-role table because none currently exists in the HeartShapers database. Use a dedicated Supabase Auth account for the admin.

## Storage

File uploads go to Firebase Storage; the database still lives in Supabase. The two sessions are separate on purpose:

- Supabase Auth signs the administrator in for the `books`, `games`, and settings tables.
- Firebase Auth unlocks Storage. The banner at the top of the admin asks for the Firebase admin account once per browser; the SDK keeps that session afterwards. Signing out of the admin signs out of both.

Object paths keep the old bucket layout so existing app lookups keep working:

| Content | Path |
| --- | --- |
| Book covers | `covers/<uuid>-<name>` (also `covers/optimized/<book-id>-<time>.webp`) |
| Book PDFs | `pdfs/<uuid>-<name>` |
| Game cover, source PDF, card pages | `games/<id>/...` |
| Payment QR codes | `payment-proofs/settings/<uuid>-<name>` |
| User payment proofs (mobile) | `payment-proofs/...` |

Book covers and QR codes are stored as the resolved Firebase download URL; book PDFs and game assets are stored as object paths because the mobile app resolves them with `getDownloadURL`. No Supabase Storage call remains in the admin source.

The deployed Storage rules must allow the signed-in admin to write these paths and read them back. Rules are not part of this repository.

## Production

Build with:

```bash
npm run build
```

Then deploy the `dist` folder to your preferred static host.
