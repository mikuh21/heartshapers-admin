-- Retain content records and references while hiding everything under deleted taxonomy.
-- Database changes are atomic: a failure rolls the operation back.

begin;

-- Repair books/games left active by taxonomy soft-deletes from the earlier implementation.
update public.books b
set deleted_at = p.deleted_at
from public.pillars p
where b.deleted_at is null
  and p.deleted_at is not null
  and lower(trim(coalesce(b.pillar, ''))) = lower(trim(p.name));

update public.books b
set deleted_at = c.deleted_at
from public.categories c
left join public.pillars p on p.id = c.pillar_id
where b.deleted_at is null
  and c.deleted_at is not null
  and lower(trim(coalesce(b.subcategory, ''))) = lower(trim(c.name))
  and (
    p.name is null
    or lower(trim(coalesce(b.pillar, ''))) = lower(trim(p.name))
  );

update public.games g
set deleted_at = coalesce(p.deleted_at, c.deleted_at, now())
from public.game_placements gp
left join public.pillars p on p.id = gp.pillar_id
left join public.categories c on c.id = gp.category_id
where g.id = gp.game_id
  and g.deleted_at is null
  and (p.deleted_at is not null or c.deleted_at is not null);

create or replace function public.soft_delete_pillar(p_pillar_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_pillar_name text;
  v_deleted_at timestamptz := now();
begin
  select name into v_pillar_name
  from public.pillars
  where id = p_pillar_id and deleted_at is null
  for update;

  if not found then
    return false;
  end if;

  -- Books store taxonomy names, while games use explicit placement rows.
  update public.books
  set deleted_at = v_deleted_at
  where deleted_at is null
    and lower(trim(coalesce(pillar, ''))) = lower(trim(v_pillar_name));

  update public.games g
  set deleted_at = v_deleted_at
  where g.deleted_at is null
    and exists (
      select 1
      from public.game_placements gp
      where gp.game_id = g.id
        and gp.pillar_id = p_pillar_id
    );

  update public.categories
  set deleted_at = v_deleted_at
  where pillar_id = p_pillar_id
    and deleted_at is null;

  update public.pillars
  set deleted_at = v_deleted_at
  where id = p_pillar_id
    and deleted_at is null;

  return true;
end;
$$;

create or replace function public.soft_delete_category(p_category_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_category_name text;
  v_pillar_name text;
  v_deleted_at timestamptz := now();
begin
  select c.name, p.name
    into v_category_name, v_pillar_name
  from public.categories c
  left join public.pillars p on p.id = c.pillar_id
  where c.id = p_category_id
    and c.deleted_at is null
  for update of c;

  if not found then
    return false;
  end if;

  update public.books
  set deleted_at = v_deleted_at
  where deleted_at is null
    and lower(trim(coalesce(subcategory, ''))) = lower(trim(v_category_name))
    and (
      v_pillar_name is null
      or lower(trim(coalesce(pillar, ''))) = lower(trim(v_pillar_name))
    );

  update public.games g
  set deleted_at = v_deleted_at
  where g.deleted_at is null
    and exists (
      select 1
      from public.game_placements gp
      where gp.game_id = g.id
        and gp.category_id = p_category_id
    );

  update public.categories
  set deleted_at = v_deleted_at
  where id = p_category_id
    and deleted_at is null;

  return true;
end;
$$;

grant execute on function public.soft_delete_pillar(uuid) to authenticated;
grant execute on function public.soft_delete_category(uuid) to authenticated;

commit;
