begin;

alter table public.games
  add column if not exists source_pdf_path text;

alter table public.games
  drop constraint if exists games_game_type_check;

alter table public.games
  add constraint games_game_type_check
  check (
    game_type in (
      'bible_action',
      'bible_draw',
      'bible_groups',
      'bible_proverbs',
      'bible_question',
      'bible_talk',
      'inspirational_talk_1',
      'inspirational_talk_2',
      'pdf_deck'
    )
  );

drop policy if exists game_covers_authenticated_read on storage.objects;
create policy game_covers_authenticated_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'game-assets'
    and (storage.foldername(name))[1] = 'games'
    and (storage.foldername(name))[3] = 'cover'
    and exists (
      select 1
      from public.games game
      where game.id = (storage.foldername(name))[2]
    )
  );

create or replace function public.create_pdf_game(p_game jsonb, p_cards jsonb, p_rules text)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  created_game public.games;
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') not in ('admin', 'super_admin') then
    raise exception 'Only administrators can create games.';
  end if;
  if jsonb_typeof(p_game) is distinct from 'object'
    or p_game ->> 'game_type' is distinct from 'pdf_deck'
    or jsonb_typeof(p_cards) is distinct from 'array'
  then
    raise exception 'A PDF game and at least one card are required.';
  end if;
  if jsonb_array_length(p_cards) = 0 then
    raise exception 'A PDF game and at least one card are required.';
  end if;
  if nullif(trim(p_game ->> 'title'), '') is null
    or coalesce(p_game ->> 'id', '') !~ '^game-[a-z0-9]+(-[a-z0-9]+)*-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or coalesce(p_game ->> 'sort_order', '') !~ '^[0-9]+$'
    or coalesce(p_game ->> 'price', '') !~ '^[0-9]+([.][0-9]+)?$'
  then
    raise exception 'The game title or generated game information is invalid.';
  end if;
  if nullif(trim(p_rules), '') is null then
    raise exception 'Game rules are required.';
  end if;
  if coalesce(p_game ->> 'cover_image_url', '') !~ (
    '^games/' || (p_game ->> 'id') || '/cover/cover[.](jpg|png|webp)$'
  ) then
    raise exception 'A valid uploaded game cover is required.';
  end if;
  if p_game ->> 'source_pdf_path' is distinct from (
    'games/' || (p_game ->> 'id') || '/source/content.pdf'
  ) then
    raise exception 'A valid uploaded game PDF is required.';
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
      or entry.card -> 'metadata' ->> 'pdf_page_path' is distinct from (
        'games/' || (p_game ->> 'id') || '/cards/page-' ||
        lpad(entry.position::text, 4, '0') || '.png'
      )
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

  insert into public.games (
    id,
    title,
    game_type,
    subtitle,
    description,
    cover_image_url,
    source_pdf_path,
    sort_order,
    price,
    is_locked
  )
  values (
    p_game ->> 'id',
    p_game ->> 'title',
    'pdf_deck',
    nullif(p_game ->> 'subtitle', ''),
    nullif(p_game ->> 'description', ''),
    p_game ->> 'cover_image_url',
    p_game ->> 'source_pdf_path',
    (p_game ->> 'sort_order')::integer,
    (p_game ->> 'price')::numeric,
    true
  )
  returning * into created_game;

  insert into public.game_cards (game_id, sort_order, front_text, back_text, metadata)
  select
    created_game.id,
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

  insert into public.game_rules (game_id, sort_order, rule_text, metadata)
  values (created_game.id, 1, trim(p_rules), '{}'::jsonb);

  return to_jsonb(created_game);
end;
$$;

revoke all on function public.create_pdf_game(jsonb, jsonb, text) from public, anon;
grant execute on function public.create_pdf_game(jsonb, jsonb, text) to authenticated;

commit;
