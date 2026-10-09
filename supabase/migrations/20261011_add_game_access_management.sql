alter table public.games
  add column if not exists is_locked boolean not null default false;

update public.games game
set is_locked = case game.id
  when 'game-bible-action' then false
  when 'game-bible-draw' then false
  else true
end
where game.id in (
  'game-bible-action',
  'game-bible-draw',
  'game-bible-groups',
  'game-bible-proverbs',
  'game-bible-question',
  'game-bible-talk',
  'game-inspirational-talk-1',
  'game-inspirational-talk-2'
)
and not exists (
  select 1
  from public.admin_logs log
  where log.action = 'game_access_changed'
    and log.details ->> 'target_id' = game.id
);

create table if not exists public.user_game_access (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id text not null references public.games(id) on delete cascade,
  access_status text not null check (access_status in ('free', 'locked')),
  granted_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, game_id)
);

create index if not exists user_game_access_game_id_idx
  on public.user_game_access (game_id);

alter table public.user_game_access enable row level security;
revoke all on table public.user_game_access from public, anon, authenticated;
grant select (user_id, game_id, access_status) on table public.user_game_access to authenticated;
grant select, insert, update, delete on table public.user_game_access to service_role;

drop policy if exists user_game_access_user_select on public.user_game_access;
create policy user_game_access_user_select
  on public.user_game_access for select to authenticated
  using (user_id = auth.uid());

create or replace function public.has_game_access(p_game_id text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
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

revoke all on function public.has_game_access(text) from public, anon;
grant execute on function public.has_game_access(text) to authenticated;

drop policy if exists game_placements_authenticated_select on public.game_placements;
create policy game_placements_authenticated_select
  on public.game_placements for select to authenticated
  using (
    exists (
      select 1
      from public.games game
      where game.id = game_placements.game_id
        and (
          (
            game.is_active
            and public.has_game_access(game.id)
          )
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
        )
    )
  );

drop policy if exists game_rules_authenticated_select on public.game_rules;
create policy game_rules_authenticated_select
  on public.game_rules for select to authenticated
  using (
    exists (
      select 1
      from public.games game
      where game.id = game_rules.game_id
        and (
          (
            game.is_active
            and public.has_game_access(game.id)
          )
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
        )
    )
  );

drop policy if exists game_cards_authenticated_select on public.game_cards;
create policy game_cards_authenticated_select
  on public.game_cards for select to authenticated
  using (
    exists (
      select 1
      from public.games game
      where game.id = game_cards.game_id
        and (
          (
            game.is_active
            and public.has_game_access(game.id)
          )
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
        )
    )
  );

drop policy if exists game_assets_active_read on storage.objects;
create policy game_assets_active_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'game-assets'
    and (storage.foldername(name))[1] = 'games'
    and exists (
      select 1
      from public.games game
      where game.id = (storage.foldername(name))[2]
        and game.is_active
        and public.has_game_access(game.id)
    )
  );
