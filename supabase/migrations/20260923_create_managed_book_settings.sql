create extension if not exists "pgcrypto";

create table if not exists public.pillars (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  pillar_id uuid not null references public.pillars(id) on delete restrict,
  name text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists pillars_name_lower_unique
  on public.pillars (lower(trim(name)));

create unique index if not exists categories_pillar_name_lower_unique
  on public.categories (pillar_id, lower(trim(name)));

insert into public.pillars (name)
select v.name
from (
  values ('Family'), ('Work'), ('Ministry')
) as v(name)
where not exists (
  select 1 from public.pillars p where lower(trim(p.name)) = lower(trim(v.name))
);

insert into public.categories (pillar_id, name)
select p.id, v.name
from (
  values
    ('Family', 'Devotionals'),
    ('Family', 'Discipleship'),
    ('Work', 'Leadership'),
    ('Ministry', 'Heroes of Faith'),
    ('Ministry', 'Group Activities')
) as v(pillar_name, name)
inner join public.pillars p on lower(trim(p.name)) = lower(trim(v.pillar_name))
where not exists (
  select 1
  from public.categories c
  where c.pillar_id = p.id
    and lower(trim(c.name)) = lower(trim(v.name))
);
