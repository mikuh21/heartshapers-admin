create table if not exists public.password_reset_codes (
  email text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  code_hash text,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0 and attempts <= 5),
  verified_at timestamptz,
  reset_token_hash text,
  reset_token_expires_at timestamptz,
  last_sent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists password_reset_codes_user_id_idx on public.password_reset_codes (user_id);
alter table public.password_reset_codes enable row level security;
revoke all on table public.password_reset_codes from anon, authenticated;
grant all on table public.password_reset_codes to service_role;
comment on table public.password_reset_codes is 'Short-lived password-reset OTPs and single-use reset tokens. Restricted to the Supabase service role.';
