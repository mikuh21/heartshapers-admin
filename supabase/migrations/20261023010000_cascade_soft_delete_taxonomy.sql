-- Keep content records and references intact while hiding all content under deleted taxonomy.
-- The functions execute atomically: if any update fails, the whole deletion is rolled back.
begin;

-- Repair records affected by taxonomy deletions performed before cascading was added.
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

  update public.books
  set deleted_at = v_deleted_at
  where deleted_at is null
    and lower(trim(coalesce(pillar, ''))) = lower(trim(v_pillar_name));

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
