begin;

drop policy if exists games_authenticated_select on public.games;
drop policy if exists game_placements_authenticated_select on public.game_placements;
drop policy if exists game_rules_authenticated_select on public.game_rules;
drop policy if exists game_cards_authenticated_select on public.game_cards;
drop policy if exists game_assets_active_read on storage.objects;
drop policy if exists game_assets_entitlement_read on storage.objects;

drop index if exists public.games_active_sort_order_idx;

create policy games_authenticated_select
  on public.games for select to authenticated
  using (true);

create policy game_placements_authenticated_select
  on public.game_placements for select to authenticated
  using (
    public.has_game_access(game_id)
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  );

create policy game_rules_authenticated_select
  on public.game_rules for select to authenticated
  using (
    public.has_game_access(game_id)
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  );

create policy game_cards_authenticated_select
  on public.game_cards for select to authenticated
  using (
    public.has_game_access(game_id)
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  );

create policy game_assets_entitlement_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'game-assets'
    and (storage.foldername(name))[1] = 'games'
    and (
      public.has_game_access((storage.foldername(name))[2])
      or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
    )
  );

alter table public.games drop column if exists is_active;

commit;
