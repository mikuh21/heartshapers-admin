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

3. Copy `.env.example` to `.env` and fill in:

```env
VITE_SUPABASE_URL=...
VITE_SUPABASE_ANON_KEY=...
VITE_BOOK_COVERS_BUCKET=book-covers
VITE_BOOK_PDFS_BUCKET=book-pdfs
```

4. Create a Supabase Auth user for the administrator.
5. Create two Supabase Storage buckets named `book-covers` and `book-pdfs` (or change the names in `.env`).
6. Configure Storage policies and `books` table RLS so the authenticated admin can read/insert/update/delete rows and upload files.
7. Run:

```bash
npm run dev
```

## Important security note

This first version uses Supabase Auth and the `books` table only. There is no admin-role table because none currently exists in the HeartShapers database. Use a dedicated Supabase Auth account for the admin.

If the PDF files must be protected from direct public access, use private storage buckets and signed URLs in the app. The current starter uses public URLs because `pdf_url` is a URL field and the exact existing HeartShapers storage setup was not provided.

## Production

Build with:

```bash
npm run build
```

Then deploy the `dist` folder to your preferred static host.
