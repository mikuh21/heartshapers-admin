-- Retain deleted content and taxonomy records without exposing them in app listings.
-- Existing purchase/payment references remain intact; storage assets are intentionally retained.
begin;

alter table public.books add column if not exists deleted_at timestamptz;
alter table public.games add column if not exists deleted_at timestamptz;
alter table public.pillars add column if not exists deleted_at timestamptz;
alter table public.categories add column if not exists deleted_at timestamptz;

create index if not exists books_active_created_at_idx
  on public.books (created_at desc) where deleted_at is null;
create index if not exists games_not_deleted_sort_order_idx
  on public.games (sort_order) where deleted_at is null;
create index if not exists pillars_active_name_idx
  on public.pillars (name) where deleted_at is null;
create index if not exists categories_active_pillar_name_idx
  on public.categories (pillar_id, name) where deleted_at is null;

comment on column public.books.deleted_at is 'Soft-delete timestamp. Non-null records are hidden from normal app/admin listings.';
comment on column public.games.deleted_at is 'Soft-delete timestamp. Non-null records are hidden from normal app/admin listings.';
comment on column public.pillars.deleted_at is 'Soft-delete timestamp. Non-null records are hidden from normal app/admin listings.';
comment on column public.categories.deleted_at is 'Soft-delete timestamp. Non-null records are hidden from normal app/admin listings.';

commit;
