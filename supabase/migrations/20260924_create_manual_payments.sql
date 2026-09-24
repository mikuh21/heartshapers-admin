create extension if not exists "pgcrypto";

alter table public.books
  add column if not exists price numeric not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.books'::regclass and conname = 'books_price_nonnegative'
  ) then
    alter table public.books add constraint books_price_nonnegative check (price >= 0);
  end if;
end;
$$;

create table if not exists public.payment_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid not null references public.books(id) on delete restrict,
  amount numeric not null check (amount >= 0),
  reference_number text not null,
  proof_image_url text not null,
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  admin_id uuid null references auth.users(id) on delete set null,
  admin_notes text null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz null
);

create index if not exists payment_submissions_created_at_idx
  on public.payment_submissions (created_at desc);
create index if not exists payment_submissions_status_idx
  on public.payment_submissions (status);

create table if not exists public.book_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id uuid not null references public.books(id) on delete restrict,
  payment_id uuid not null references public.payment_submissions(id) on delete restrict,
  purchased_at timestamptz not null default now(),
  unique (user_id, book_id)
);

insert into public.app_settings (key, value)
values (
  'payment_settings',
  '{"payment_method":"gcash","qr_image_url":"","merchant_name":"HEARTSHAPERS","instructions":"Scan the GCash QR code to pay."}'::jsonb
)
on conflict (key) do nothing;

insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do nothing;

alter table public.payment_submissions enable row level security;
alter table public.book_purchases enable row level security;

create policy payment_submissions_customer_insert
  on public.payment_submissions for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and admin_id is null and reviewed_at is null);

create policy payment_submissions_customer_select
  on public.payment_submissions for select to authenticated
  using (user_id = auth.uid());

create policy payment_submissions_admin_select
  on public.payment_submissions for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin'));

create policy payment_submissions_admin_update
  on public.payment_submissions for update to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin'))
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin'));

create policy book_purchases_customer_select
  on public.book_purchases for select to authenticated
  using (user_id = auth.uid());

create policy book_purchases_admin_select
  on public.book_purchases for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin'));

create policy payment_proofs_customer_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy payment_proofs_customer_select
  on storage.objects for select to authenticated
  using (
    bucket_id = 'payment-proofs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy payment_proofs_admin_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'payment-proofs'
    and (auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin')
  );

create policy payment_proofs_admin_select
  on storage.objects for select to authenticated
  using (
    bucket_id = 'payment-proofs'
    and (auth.jwt() -> 'app_metadata' ->> 'role') in ('admin', 'super_admin')
  );

create or replace function public.verify_payment_submission(payment_id uuid, note text default null)
returns public.payment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.payment_submissions;
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  book_title text;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') not in ('admin', 'super_admin') then
    raise exception 'Only admins can verify payments';
  end if;

  select * into payment
  from public.payment_submissions
  where id = payment_id
  for update;

  if payment.id is null then raise exception 'Payment not found'; end if;
  if payment.status <> 'pending' then raise exception 'Only pending payments can be verified'; end if;

  update public.payment_submissions
  set status = 'verified', admin_id = current_admin, reviewed_at = now(), admin_notes = nullif(trim(note), '')
  where id = payment_id
  returning * into payment;

  insert into public.book_purchases (user_id, book_id, payment_id)
  values (payment.user_id, payment.book_id, payment.id)
  on conflict (user_id, book_id) do nothing;

  select title into book_title from public.books where id = payment.book_id;
  insert into public.admin_logs (action, details, admin_email)
  values ('payment_verified', jsonb_build_object(
    'payment_id', payment.id, 'book_id', payment.book_id, 'book_title', book_title,
    'user_id', payment.user_id, 'amount', payment.amount,
    'reference_number', payment.reference_number
  ), current_email);

  return payment;
end;
$$;

create or replace function public.reject_payment_submission(payment_id uuid, note text)
returns public.payment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.payment_submissions;
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  book_title text;
begin
  if (auth.jwt() -> 'app_metadata' ->> 'role') not in ('admin', 'super_admin') then
    raise exception 'Only admins can reject payments';
  end if;
  if nullif(trim(note), '') is null then raise exception 'A rejection reason is required'; end if;

  select * into payment from public.payment_submissions where id = payment_id for update;
  if payment.id is null then raise exception 'Payment not found'; end if;
  if payment.status <> 'pending' then raise exception 'Only pending payments can be rejected'; end if;

  update public.payment_submissions
  set status = 'rejected', admin_id = current_admin, reviewed_at = now(), admin_notes = trim(note)
  where id = payment_id
  returning * into payment;

  select title into book_title from public.books where id = payment.book_id;
  insert into public.admin_logs (action, details, admin_email)
  values ('payment_rejected', jsonb_build_object(
    'payment_id', payment.id, 'book_id', payment.book_id, 'book_title', book_title,
    'user_id', payment.user_id, 'amount', payment.amount,
    'reference_number', payment.reference_number, 'rejection_reason', payment.admin_notes
  ), current_email);

  return payment;
end;
$$;

revoke all on function public.verify_payment_submission(uuid, text) from public;
revoke all on function public.reject_payment_submission(uuid, text) from public;
grant execute on function public.verify_payment_submission(uuid, text) to authenticated;
grant execute on function public.reject_payment_submission(uuid, text) to authenticated;
