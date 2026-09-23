create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid null
);

create table if not exists public.admin_logs (
  id uuid primary key default gen_random_uuid(),
  action text not null,
  details jsonb not null default '{}'::jsonb,
  admin_email text,
  created_at timestamptz not null default now()
);

create index if not exists admin_logs_created_at_idx
  on public.admin_logs (created_at desc);

insert into public.app_settings (key, value)
select 'upload_settings', jsonb_build_object(
  'maximum_upload_size_mb', 10,
  'acceptable_file_types', jsonb_build_array('pdf', 'jpg', 'jpeg', 'png', 'webp')
)
where not exists (
  select 1 from public.app_settings where key = 'upload_settings'
);
