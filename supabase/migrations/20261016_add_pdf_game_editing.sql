begin;

create or replace function public.update_pdf_game(p_game jsonb, p_cards jsonb, p_rules text)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  existing_game public.games;
  updated_game public.games;
  cover_path text;
  source_path text;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('admin', 'super_admin') then
    raise exception 'Only administrators can update PDF games.';
  end if;
  if jsonb_typeof(p_game) is distinct from 'object'
    or nullif(trim(p_game ->> 'id'), '') is null
    or nullif(trim(p_game ->> 'title'), '') is null
    or coalesce(p_game ->> 'price', '') !~ '^[0-9]+([.][0-9]{1,2})?$'
    or jsonb_typeof(p_game -> 'is_locked') is distinct from 'boolean'
    or coalesce(p_game ->> 'sort_order', '') !~ '^[0-9]+$'
    or jsonb_typeof(p_cards) not in ('array', 'null')
  then
    raise exception 'The PDF game information is invalid.';
  end if;
  if nullif(trim(p_rules), '') is null then
    raise exception 'Game rules are required.';
  end if;

  select * into existing_game
  from public.games
  where id = p_game ->> 'id'
  for update;

  if not found or existing_game.game_type is distinct from 'pdf_deck' then
    raise exception 'The selected game is not an existing PDF game.';
  end if;

  cover_path := coalesce(p_game ->> 'cover_image_url', existing_game.cover_image_url);
  source_path := coalesce(p_game ->> 'source_pdf_path', existing_game.source_pdf_path);

  if cover_path is null
    or left(cover_path, length('games/' || existing_game.id || '/cover/'))
      <> 'games/' || existing_game.id || '/cover/'
    or substring(cover_path from length('games/' || existing_game.id || '/cover/') + 1)
      !~ '^[A-Za-z0-9-]+[.](jpg|png|webp)$'
  then
    raise exception 'A valid game cover path is required.';
  end if;
  if source_path is null
    or left(source_path, length('games/' || existing_game.id || '/source/'))
      <> 'games/' || existing_game.id || '/source/'
    or substring(source_path from length('games/' || existing_game.id || '/source/') + 1)
      !~ '^[A-Za-z0-9-]+[.]pdf$'
  then
    raise exception 'A valid game PDF path is required.';
  end if;
  if source_path is distinct from existing_game.source_pdf_path
    and (p_cards is null or p_cards = 'null'::jsonb)
  then
    raise exception 'Replacing the source PDF also requires replacing its selected card pages.';
  end if;

  if p_cards is not null and p_cards <> 'null'::jsonb then
    if jsonb_typeof(p_cards) is distinct from 'array'
      or jsonb_array_length(p_cards) = 0
    then
      raise exception 'Select at least one PDF page for the card deck.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_cards) with ordinality as entry(card, position)
      where (entry.card ->> 'sort_order')::integer is distinct from entry.position::integer
        or jsonb_typeof(entry.card -> 'metadata') is distinct from 'object'
        or jsonb_typeof(entry.card -> 'metadata' -> 'pairs') is distinct from 'array'
        or entry.card -> 'metadata' ->> 'content_type' is distinct from 'pdf_page'
        or coalesce((entry.card -> 'metadata' ->> 'pdf_page_number')::integer, 0) < 1
        or (entry.card -> 'metadata' ->> 'page_order')::integer is distinct from entry.position::integer
        or left(
          coalesce(entry.card -> 'metadata' ->> 'pdf_page_path', ''),
          length('games/' || existing_game.id || '/cards/')
        ) <> 'games/' || existing_game.id || '/cards/'
        or substring(
          coalesce(entry.card -> 'metadata' ->> 'pdf_page_path', '')
          from length('games/' || existing_game.id || '/cards/') + 1
        ) !~ '^[A-Za-z0-9-]+/page-[0-9]{4}[.]png$'
    ) then
      raise exception 'The PDF card list is invalid.';
    end if;
    if exists (
      select 1
      from jsonb_array_elements(p_cards) as entry(card)
      group by entry.card -> 'metadata' ->> 'pdf_page_number'
      having count(*) > 1
    ) then
      raise exception 'A PDF page can only be selected once.';
    end if;
  end if;

  update public.games
  set title = trim(p_game ->> 'title'),
      subtitle = nullif(trim(p_game ->> 'subtitle'), ''),
      description = nullif(trim(p_game ->> 'description'), ''),
      cover_image_url = cover_path,
      source_pdf_path = source_path,
      price = (p_game ->> 'price')::numeric,
      is_locked = (p_game ->> 'is_locked')::boolean,
      sort_order = (p_game ->> 'sort_order')::integer
  where id = existing_game.id
  returning * into updated_game;

  if p_cards is not null and p_cards <> 'null'::jsonb then
    delete from public.game_cards where game_id = existing_game.id;

    insert into public.game_cards (game_id, sort_order, front_text, back_text, metadata)
    select
      existing_game.id,
      card.sort_order,
      card.front_text,
      card.back_text,
      card.metadata
    from jsonb_to_recordset(p_cards) as card(
      sort_order integer,
      front_text text,
      back_text text,
      metadata jsonb
    );
  end if;

  update public.game_rules
  set rule_text = trim(p_rules)
  where game_id = existing_game.id and sort_order = 1;

  if not found then
    insert into public.game_rules (game_id, sort_order, rule_text, metadata)
    values (existing_game.id, 1, trim(p_rules), '{}'::jsonb);
  end if;

  return to_jsonb(updated_game);
end;
$$;

revoke all on function public.update_pdf_game(jsonb, jsonb, text) from public, anon;
grant execute on function public.update_pdf_game(jsonb, jsonb, text) to authenticated;

commit;
