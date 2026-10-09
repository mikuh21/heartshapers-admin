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
