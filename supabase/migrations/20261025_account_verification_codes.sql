-- Heartshapers email account-verification OTP storage.
-- Run this migration in the Supabase SQL Editor before deploying account-verification-otp.

create table if not exists public.account_verification_codes (
  email text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  code_hash text,
  expires_at timestamptz,
  attempts integer not null default 0,
  verified_at timestamptz,
  last_sent_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists account_verification_codes_user_id_idx
  on public.account_verification_codes (user_id);

alter table public.account_verification_codes enable row level security;

-- No client-facing policies are intentionally created. The Edge Function uses
-- the service-role key and is the only intended reader/writer of this table.

