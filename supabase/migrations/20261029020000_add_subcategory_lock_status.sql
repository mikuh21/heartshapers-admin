-- Add explicit access state to subcategories (categories table).
-- Existing subcategories remain unlocked; newly created subcategories default to unlocked.
begin;

alter table public.categories
  add column if not exists is_locked boolean not null default false;

commit;
