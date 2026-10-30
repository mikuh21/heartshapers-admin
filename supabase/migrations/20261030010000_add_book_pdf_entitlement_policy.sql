-- Add entitlement-aware signed access before the PDF bucket is made private.
-- This migration intentionally does not change bucket visibility or existing URLs.
--
-- Keep precedence aligned with the mobile hasBookAccess() implementation:
-- VIP, purchase, and explicit free grants allow access; an explicit locked
-- override denies access before the book-level unlocked default is considered.

create or replace function public.can_read_book_pdf(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.books b
    where b.deleted_at is null
      and (
        b.pdf_url = object_name
        or right(
          b.pdf_url,
          length('/storage/v1/object/public/pdfs/' || object_name)
        ) = '/storage/v1/object/public/pdfs/' || object_name
        or right(
          b.pdf_url,
          length('/storage/v1/object/sign/pdfs/' || object_name)
        ) = '/storage/v1/object/sign/pdfs/' || object_name
      )
      and (
        lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'membership_tier', '')) = 'vip'
        or lower(coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) in ('admin', 'super_admin')
        or exists (
          select 1
          from public.book_purchases bp
          where bp.book_id = b.id
            and bp.user_id = auth.uid()
        )
        or exists (
          select 1
          from public.user_book_access uba
          where uba.book_id = b.id
            and uba.user_id = auth.uid()
            and lower(uba.access_status) = 'free'
        )
        or (
          coalesce(b.is_locked, true) = false
          and not exists (
            select 1
            from public.user_book_access uba
            where uba.book_id = b.id
              and uba.user_id = auth.uid()
              and lower(uba.access_status) = 'locked'
          )
        )
      )
  );
$$;

revoke all on function public.can_read_book_pdf(text) from public, anon;
grant execute on function public.can_read_book_pdf(text) to authenticated;

drop policy if exists book_pdfs_entitlement_read on storage.objects;
create policy book_pdfs_entitlement_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'pdfs'
  and public.can_read_book_pdf(name)
);
