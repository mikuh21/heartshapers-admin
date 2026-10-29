-- Protect book PDF objects behind the same entitlements enforced by the mobile app.
-- Deploy only after the mobile reader can request signed URLs and the updated
-- app has been released to users; older app versions use public PDF URLs directly.

begin;

-- Convert existing public URLs to bucket-relative object paths.
update public.books
set pdf_url = regexp_replace(
  substring(pdf_url from '/storage/v1/object/public/pdfs/(.*)$'),
  '\\?.*$',
  ''
)
where pdf_url like '%/storage/v1/object/public/pdfs/%';

-- Make the PDF bucket private. Covers remain in the separate public covers bucket.
update storage.buckets
set public = false
where id = 'pdfs';

drop policy if exists pdfs_entitlement_read on storage.objects;
create policy pdfs_entitlement_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pdfs'
  and (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
    or exists (
      select 1
      from public.books b
      where b.pdf_url = storage.objects.name
        and b.deleted_at is null
        and (
          coalesce(auth.jwt() -> 'app_metadata' ->> 'membership_tier', 'regular') = 'vip'
          or exists (
            select 1
            from public.book_purchases bp
            where bp.user_id = (select auth.uid())
              and bp.book_id = b.id
          )
          or exists (
            select 1
            from public.user_book_access uba
            where uba.user_id = (select auth.uid())
              and uba.book_id = b.id
              and uba.access_status = 'free'
          )
          or (
            coalesce((
              select uba.access_status
              from public.user_book_access uba
              where uba.user_id = (select auth.uid())
                and uba.book_id = b.id
            ), '') <> 'locked'
            and coalesce(b.is_locked, false) = false
          )
        )
    )
  )
);

commit;
