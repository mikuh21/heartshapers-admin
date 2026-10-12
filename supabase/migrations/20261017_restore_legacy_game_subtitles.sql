-- Restore legacy game subtitles from their original rule headings.
-- The previous generic subtitle is retained as Description only where that
-- field is NULL; existing descriptions and rule metadata are left untouched.
with legacy_subtitles as (
  select distinct on (game.id)
    game.id,
    game.subtitle as previous_subtitle,
    rule.metadata->'source_rule'->>'heading' as source_heading
  from public.games as game
  join public.game_rules as rule on rule.game_id = game.id
  where game.game_type in (
      'bible_action',
      'bible_draw',
      'bible_groups',
      'bible_proverbs',
      'bible_question',
      'bible_talk',
      'inspirational_talk_1',
      'inspirational_talk_2'
    )
    and lower(btrim(game.subtitle)) = 'card game'
    and jsonb_typeof(rule.metadata->'source_rule') = 'object'
    and nullif(btrim(rule.metadata->'source_rule'->>'heading'), '') is not null
  order by game.id, rule.sort_order, rule.id
)
update public.games as game
set
  subtitle = legacy_subtitles.source_heading,
  description = case
    when game.description is null then legacy_subtitles.previous_subtitle
    else game.description
  end
from legacy_subtitles
where game.id = legacy_subtitles.id
  and (
    game.subtitle is distinct from legacy_subtitles.source_heading
    or game.description is null
  );
