-- SECURITY CUTOVER: apply only after the entitlement policy and the updated
-- mobile/admin clients are deployed. Existing app versions that fetch public
-- PDF URLs directly will stop working after this migration.

do $$
declare
  unexpected_count integer;
begin
  select count(*)
  into unexpected_count
  from public.books
  where deleted_at is null
    and pdf_url is not null
    and btrim(pdf_url) <> ''
    and pdf_url not like 'pdfs/%'
    and pdf_url !~* '^https?://[^/]+/storage/v1/object/public/pdfs/';

  if unexpected_count > 0 then
    raise exception
      'Cannot make pdfs private: % active book PDF references are not recognized Supabase pdfs paths or public URLs.',
      unexpected_count;
  end if;
end;
$$;

-- Replace legacy public URLs with their Storage object paths. The bucket's
-- actual object names include the "pdfs/" prefix.
update public.books
set pdf_url = regexp_replace(
  pdf_url,
  '^https?://[^/]+/storage/v1/object/public/pdfs/',
  ''
)
where pdf_url ~* '^https?://[^/]+/storage/v1/object/public/pdfs/';

-- The entitlement SELECT policy must already exist before private access is
-- enabled; otherwise even entitled users cannot create signed URLs.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'book_pdfs_entitlement_read'
  ) then
    raise exception
      'Cannot make pdfs private: book_pdfs_entitlement_read policy is missing. Apply the prerequisite policy migration first.';
  end if;
end;
$$;

update storage.buckets
set public = false
where id = 'pdfs';

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'pdfs' and public = false) then
    raise exception 'PDF bucket "pdfs" was not found or could not be made private.';
  end if;
end;
$$;
