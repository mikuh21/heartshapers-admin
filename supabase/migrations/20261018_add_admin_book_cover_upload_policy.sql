begin;

drop policy if exists book_covers_admin_insert on storage.objects;
create policy book_covers_admin_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'covers'
    and (storage.foldername(name))[1] = 'covers'
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  );

commit;
