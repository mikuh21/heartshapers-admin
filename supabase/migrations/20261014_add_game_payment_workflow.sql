begin;

alter table public.games
  add column if not exists price numeric not null default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.games'::regclass
      and conname = 'games_price_nonnegative'
  ) then
    alter table public.games
      add constraint games_price_nonnegative check (price >= 0);
  end if;
end;
$$;

create table if not exists public.game_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id) on delete restrict,
  amount numeric not null check (amount > 0),
  reference_number text not null,
  proof_image_url text not null,
  status text not null default 'pending'
    check (status in ('pending', 'verified', 'rejected')),
  admin_id uuid null references auth.users(id) on delete set null,
  admin_notes text null,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz null
);

create index if not exists game_payment_submissions_created_at_idx
  on public.game_payment_submissions (created_at desc);
create index if not exists game_payment_submissions_status_idx
  on public.game_payment_submissions (status);
create unique index if not exists game_payment_submissions_one_pending_idx
  on public.game_payment_submissions (user_id, game_id)
  where status = 'pending';

create table if not exists public.game_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id) on delete restrict,
  payment_id uuid not null unique
    references public.game_payment_submissions(id) on delete restrict,
  purchased_at timestamptz not null default now(),
  unique (user_id, game_id)
);

create index if not exists game_purchases_game_id_idx
  on public.game_purchases (game_id);

alter table public.game_payment_submissions enable row level security;
alter table public.game_purchases enable row level security;

revoke all on table public.game_payment_submissions, public.game_purchases
  from public, anon, authenticated;
grant select on table public.game_payment_submissions to authenticated;
grant insert on table public.game_payment_submissions to authenticated;
grant select on table public.game_purchases to authenticated;
grant all on table public.game_payment_submissions, public.game_purchases
  to service_role;

create policy game_payment_submissions_customer_insert
  on public.game_payment_submissions for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'pending'
    and admin_id is null
    and reviewed_at is null
    and split_part(proof_image_url, '/', 1) = auth.uid()::text
    and exists (
      select 1
      from public.games game
      where game.id = game_payment_submissions.game_id
        and game.price = game_payment_submissions.amount
        and game.price > 0
        and coalesce(
          (
            select access_override.access_status
            from public.user_game_access access_override
            where access_override.user_id = auth.uid()
              and access_override.game_id = game_payment_submissions.game_id
          ),
          case when game.is_locked then 'locked' else 'free' end
        ) = 'locked'
    )
    and not exists (
      select 1
      from public.game_purchases purchase
      where purchase.user_id = auth.uid()
        and purchase.game_id = game_payment_submissions.game_id
    )
  );

create policy game_payment_submissions_customer_select
  on public.game_payment_submissions for select to authenticated
  using (user_id = auth.uid());

create policy game_payment_submissions_admin_select
  on public.game_payment_submissions for select to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin', 'super_admin')
  );

create policy game_purchases_customer_select
  on public.game_purchases for select to authenticated
  using (user_id = auth.uid());

create policy game_purchases_admin_select
  on public.game_purchases for select to authenticated
  using (
    coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      in ('admin', 'super_admin')
  );

create or replace function public.has_game_access(p_game_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    exists (
      select 1
      from public.game_purchases purchase
      where purchase.game_id = game.id
        and purchase.user_id = auth.uid()
    ),
    false
  )
  or coalesce(
    (
      select override_row.access_status
      from public.user_game_access override_row
      where override_row.game_id = game.id
        and override_row.user_id = auth.uid()
    ),
    case when game.is_locked then 'locked' else 'free' end
  ) = 'free'
  from public.games game
  where game.id = p_game_id;
$$;

create or replace function public.verify_game_payment_submission(
  payment_id uuid,
  note text default null
)
returns public.game_payment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.game_payment_submissions;
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  game_title text;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      not in ('admin', 'super_admin') then
    raise exception 'Only admins can verify payments';
  end if;

  select * into payment
  from public.game_payment_submissions
  where id = payment_id
  for update;

  if payment.id is null then raise exception 'Payment not found'; end if;
  if payment.status = 'verified' then
    if exists (
      select 1 from public.game_purchases
      where game_purchases.payment_id = payment.id
        and game_purchases.user_id = payment.user_id
        and game_purchases.game_id = payment.game_id
    ) then
      return payment;
    end if;
    raise exception 'Verified payment is missing its game entitlement';
  end if;
  if payment.status <> 'pending' then
    raise exception 'Only pending payments can be verified';
  end if;

  select title into game_title from public.games where id = payment.game_id;
  if game_title is null or not exists (
    select 1 from auth.users where id = payment.user_id
  ) then
    raise exception 'Payment target or user is no longer valid';
  end if;

  update public.game_payment_submissions
  set status = 'verified',
      admin_id = current_admin,
      reviewed_at = now(),
      admin_notes = nullif(trim(note), '')
  where id = payment.id
  returning * into payment;

  insert into public.game_purchases (user_id, game_id, payment_id)
  values (payment.user_id, payment.game_id, payment.id)
  on conflict (user_id, game_id) do nothing;

  if not exists (
    select 1 from public.game_purchases
    where game_purchases.user_id = payment.user_id
      and game_purchases.game_id = payment.game_id
  ) then
    raise exception 'Unable to create game purchase entitlement';
  end if;

  insert into public.admin_logs (action, details, admin_email)
  values (
    'game_payment_verified',
    jsonb_build_object(
      'payment_id', payment.id,
      'game_id', payment.game_id,
      'game_title', game_title,
      'user_id', payment.user_id,
      'amount', payment.amount,
      'reference_number', payment.reference_number
    ),
    current_email
  );

  return payment;
end;
$$;

create or replace function public.reject_game_payment_submission(
  payment_id uuid,
  note text
)
returns public.game_payment_submissions
language plpgsql
security definer
set search_path = public
as $$
declare
  payment public.game_payment_submissions;
  current_admin uuid := auth.uid();
  current_email text := auth.jwt() ->> 'email';
  game_title text;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')
      not in ('admin', 'super_admin') then
    raise exception 'Only admins can reject payments';
  end if;
  if nullif(trim(note), '') is null then
    raise exception 'A rejection reason is required';
  end if;

  select * into payment
  from public.game_payment_submissions
  where id = payment_id
  for update;
  if payment.id is null then raise exception 'Payment not found'; end if;
  if payment.status <> 'pending' then
    raise exception 'Only pending payments can be rejected';
  end if;

  select title into game_title from public.games where id = payment.game_id;
  update public.game_payment_submissions
  set status = 'rejected',
      admin_id = current_admin,
      reviewed_at = now(),
      admin_notes = trim(note)
  where id = payment.id
  returning * into payment;

  insert into public.admin_logs (action, details, admin_email)
  values (
    'game_payment_rejected',
    jsonb_build_object(
      'payment_id', payment.id,
      'game_id', payment.game_id,
      'game_title', game_title,
      'user_id', payment.user_id,
      'amount', payment.amount,
      'reference_number', payment.reference_number,
      'rejection_reason', payment.admin_notes
    ),
    current_email
  );

  return payment;
end;
$$;

revoke all on function public.verify_game_payment_submission(uuid, text)
  from public, anon;
revoke all on function public.reject_game_payment_submission(uuid, text)
  from public, anon;
grant execute on function public.verify_game_payment_submission(uuid, text)
  to authenticated;
grant execute on function public.reject_game_payment_submission(uuid, text)
  to authenticated;

commit;
