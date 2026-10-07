create table if not exists public.user_book_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid not null references public.books(id) on delete cascade,
  access_status text not null check (access_status in ('free', 'locked')),
  granted_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, book_id)
);

create index if not exists user_book_access_book_id_idx
  on public.user_book_access (book_id);

alter table public.user_book_access enable row level security;

revoke all on table public.user_book_access from public, anon, authenticated;
grant select (user_id, book_id, access_status) on table public.user_book_access to authenticated;
grant select, insert, update, delete on table public.user_book_access to service_role;

create policy user_book_access_user_select
  on public.user_book_access for select to authenticated
  using (user_id = auth.uid());
