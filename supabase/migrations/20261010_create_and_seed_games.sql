begin;

create extension if not exists "pgcrypto";

create table if not exists public.games (
  id text primary key,
  title text not null,
  subtitle text,
  description text,
  cover_image_url text,
  game_type text not null check (
    game_type in (
      'bible_action',
      'bible_draw',
      'bible_groups',
      'bible_proverbs',s
      'bible_question',
      'bible_talk',
      'inspirational_talk_1',
      'inspirational_talk_2'
    )
  ),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create table if not exists public.game_placements (
  id uuid primary key default gen_random_uuid(),
  game_id text not null references public.games(id) on delete cascade,
  pillar_id uuid not null references public.pillars(id) on delete cascade,
  category_id uuid not null references public.categories(id) on delete cascade,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (game_id, pillar_id, category_id)
);

create table if not exists public.game_rules (
  id uuid primary key default gen_random_uuid(),
  game_id text not null references public.games(id) on delete cascade,
  sort_order integer not null default 0,
  rule_text text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, sort_order)
);

create table if not exists public.game_cards (
  id uuid primary key default gen_random_uuid(),
  game_id text not null references public.games(id) on delete cascade,
  sort_order integer not null,
  front_text text,
  back_text text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (game_id, sort_order)
);

create index if not exists game_cards_game_sort_order_idx
  on public.game_cards (game_id, sort_order);
create index if not exists game_rules_game_sort_order_idx
  on public.game_rules (game_id, sort_order);
create index if not exists game_placements_pillar_category_idx
  on public.game_placements (pillar_id, category_id, sort_order);
create index if not exists games_active_sort_order_idx
  on public.games (is_active, sort_order);

create or replace function public.set_games_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists games_set_updated_at on public.games;
create trigger games_set_updated_at
  before update on public.games
  for each row execute function public.set_games_updated_at();

drop trigger if exists game_rules_set_updated_at on public.game_rules;
create trigger game_rules_set_updated_at
  before update on public.game_rules
  for each row execute function public.set_games_updated_at();

drop trigger if exists game_cards_set_updated_at on public.game_cards;
create trigger game_cards_set_updated_at
  before update on public.game_cards
  for each row execute function public.set_games_updated_at();

insert into storage.buckets (id, name, public)
values ('game-assets', 'game-assets', false)
on conflict (id) do update set public = false;

insert into public.categories (pillar_id, name)
select p.id, 'Games'
from public.pillars p
where lower(trim(p.name)) in ('family', 'work', 'ministry')
  and not exists (
    select 1
    from public.categories c
    where c.pillar_id = p.id
      and lower(trim(c.name)) = 'games'
  );

insert into public.games (
  id,
  title,
  subtitle,
  description,
  cover_image_url,
  game_type,
  is_active,
  sort_order
)
values
  ('game-bible-action', 'Bible Action', 'Card Game', null, null, 'bible_action', true, 1),
  ('game-bible-draw', 'Bible Draw', 'Card Game', null, null, 'bible_draw', true, 2),
  ('game-bible-groups', 'Bible Groups', 'Card Game', null, null, 'bible_groups', true, 3),
  ('game-bible-proverbs', 'Bible Proverbs', 'Card Game', null, null, 'bible_proverbs', true, 4),
  ('game-bible-question', 'Bible Question', 'Card Game', null, null, 'bible_question', true, 5),
  ('game-bible-talk', 'Bible Talk', 'Card Game', null, null, 'bible_talk', true, 6),
  ('game-inspirational-talk-1', 'Inspirational Talk 1', 'Card Game', null, null, 'inspirational_talk_1', true, 7),
  ('game-inspirational-talk-2', 'Inspirational Talk 2', 'Card Game', null, null, 'inspirational_talk_2', true, 8)
on conflict (id) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  game_type = excluded.game_type,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;

-- Rule metadata retains the original mockData rule object and Action/Draw screen-effective copy.
insert into public.game_rules (game_id, sort_order, rule_text, metadata)
select seed.game_id, seed.sort_order, seed.rule_text, seed.metadata
from jsonb_to_recordset($game_rules$[
  {
    "game_id": "game-bible-action",
    "sort_order": 1,
    "rule_text": "One player draws a card and acts out the word or phrase using only body movements and facial expressions.\nThe rest of the team must guess the Bible reference or key idea within 30 seconds.\nA correct guess earns one point, and the next player takes a turn.",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-bible-action-1",
        "contentItemId": "game-bible-action",
        "heading": "READY, GET SET, ACT!",
        "subheading": "BIBLE ACTION GAME",
        "rules": [
          "One player draws a card and acts out the word or phrase using only body movements and facial expressions.",
          "The rest of the team must guess the Bible reference or key idea within 30 seconds.",
          "A correct guess earns one point, and the next player takes a turn."
        ]
      },
      "screen_effective_rule": {
        "source": "GameRulesScreen.js",
        "subheading": "This game aims to make the Bible as fun and exciting as it can be by being creative with one's body moves.",
        "rules": [
          {
            "prefix": "This game is to be played by ",
            "bold": "two (2) teams",
            "suffix": "."
          },
          {
            "prefix": "A team member will ",
            "bold": "\"act out\"",
            "suffix": " within one minute the word/words assigned to him/her by the game master as found in the card."
          },
          {
            "prefix": "If the team guesses the word/words correctly within 1 minute, the team wins a point. ",
            "bold": "The first team to win 5 points wins.",
            "suffix": ""
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 1,
    "rule_text": "One player draws a Bible scene, character, or phrase without using letters or numbers.\nThe team has 45 seconds to guess the correct story, verse, or idea.\nA correct guess earns one point, and the next artist takes a turn.",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-bible-draw-1",
        "contentItemId": "game-bible-draw",
        "heading": "READY, GET SET, DRAW!",
        "subheading": "Bible Draw Game",
        "rules": [
          "One player draws a Bible scene, character, or phrase without using letters or numbers.",
          "The team has 45 seconds to guess the correct story, verse, or idea.",
          "A correct guess earns one point, and the next artist takes a turn."
        ]
      },
      "screen_effective_rule": {
        "source": "GameRulesScreen.js",
        "subheading": "Bible Draw Game",
        "rules": [
          {
            "prefix": "This game is to be played by ",
            "bold": "two (2) teams",
            "suffix": ", one team at a time."
          },
          {
            "prefix": "A team member will ",
            "bold": "\"Draw on a piece of paper\"",
            "suffix": " within one minute the word/words assigned to him/her by the game master as found in the card."
          },
          {
            "prefix": "If a team guesses the word/words correctly within 1 minute, the team wins a point. ",
            "bold": "The first team to win 5 points wins.",
            "suffix": ""
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 1,
    "rule_text": "This game is to be played by two (2) teams, one team at a time.\nThe Game Master will read aloud a Bible group card to a team.\nFor example: Name 5 land animals in the Bible. Within one minute, the team tries to guess the 5 entries that are listed in the card.\nIf the team guessed 3 answers correctly and missed the other two answers, they get 2 points per correct answer, based on the scoring system below.\nScoring: 5 Entries, for each correct answer, 2 points. 10 Entries, 1 point for each correct answer. 20 Entries, half a point per correct answer.\nThe first team to win 40 points wins.",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-bible-groups-1",
        "contentItemId": "game-bible-groups",
        "heading": "NAME 5 LAND ANIMALS IN THE BIBLE:",
        "subheading": "Lion, Sheep, Goat, Ram, and Deer",
        "rules": [
          "This game is to be played by two (2) teams, one team at a time.",
          "The Game Master will read aloud a Bible group card to a team.",
          "For example: Name 5 land animals in the Bible. Within one minute, the team tries to guess the 5 entries that are listed in the card.",
          "If the team guessed 3 answers correctly and missed the other two answers, they get 2 points per correct answer, based on the scoring system below.",
          "Scoring: 5 Entries, for each correct answer, 2 points. 10 Entries, 1 point for each correct answer. 20 Entries, half a point per correct answer.",
          "The first team to win 40 points wins."
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 1,
    "rule_text": "This game is to be played by two (2) teams. The Game Master will assign a proverb to a Team Member and the team member will read out the proverb without the underlined words.\nA Team Member will \"Describe using words\" or \"Act out\" within two (2) minutes the underlined words. The underlined words are the missing words in the Proverbs.\nIf the team guesses the whole Proverb correctly within two (2) minutes, the team wins a point. The first team to win 5 points wins.",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-bible-proverbs-1",
        "contentItemId": "game-bible-proverbs",
        "heading": "READY, GET SET, ACT!",
        "subheading": "[underlined]Trust[/underlined] in the [underlined]Lord[/underlined] with all your [underlined]heart[/underlined] - Proverbs 3:5",
        "rules": [
          "This game is to be played by two (2) teams. The Game Master will assign a proverb to a Team Member and the team member will read out the proverb without the underlined words.",
          "A Team Member will \"Describe using words\" or \"Act out\" within two (2) minutes the underlined words. The underlined words are the missing words in the Proverbs.",
          "If the team guesses the whole Proverb correctly within two (2) minutes, the team wins a point. The first team to win 5 points wins."
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 1,
    "rule_text": "GAME 1 RULES\nObjective: To guess the given \"mystery word\" (Bible word).\nParticipants: Two pairs of contestants: one \"guesser\" and one \"clue-giver\".\nGuesser: He has to guess the \"mystery word\". He must only reply \"Yes\", \"No\", and \"Can be\", other replies will incur a 3 second penalty for every wrong reply which will be deducted from their official time.\nTime Limit: Each \"guesser\" has 2 minutes to guess the word correctly.\nGAME 2 RULES\nA Team is given the right to ask 20 questions in order to guess the word assigned to them by the Game Master.\nIf the team guesses the word correctly, the team wins a point. The first team to win 5 points wins.",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-bible-question-1",
        "contentItemId": "game-bible-question",
        "heading": "READY, GET SET, GUESS!",
        "subheading": "This game is to be played by two (2) teams.",
        "rules": [
          "GAME 1 RULES",
          "Objective: To guess the given \"mystery word\" (Bible word).",
          "Participants: Two pairs of contestants: one \"guesser\" and one \"clue-giver\".",
          "Guesser: He has to guess the \"mystery word\". He must only reply \"Yes\", \"No\", and \"Can be\", other replies will incur a 3 second penalty for every wrong reply which will be deducted from their official time.",
          "Time Limit: Each \"guesser\" has 2 minutes to guess the word correctly.",
          "GAME 2 RULES",
          "A Team is given the right to ask 20 questions in order to guess the word assigned to them by the Game Master.",
          "If the team guesses the word correctly, the team wins a point. The first team to win 5 points wins."
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 1,
    "rule_text": "This game is to be played by two (2) teams, one team at a time.\nA Team Member will \"Describe using words\" the word assigned to him/her by the Game Master as found in the card. None of the five descriptions below the card can be used to describing the word.\nFor example:\nWhen describing Noah, the words Ark, Flood, Rainbow, Forty, and Dove cannot be used to describe Noah.\nIf the team guesses the word correctly within 1 minute, the team wins a point. The first team to win 15 points wins.",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-bible-talk-1",
        "contentItemId": "game-bible-talk",
        "heading": "NOAH-ARK, FLOOD, RAINBOW, FORTY, DOVE",
        "subheading": "Bible Talk Game",
        "rules": [
          "This game is to be played by two (2) teams, one team at a time.",
          "A Team Member will \"Describe using words\" the word assigned to him/her by the Game Master as found in the card. None of the five descriptions below the card can be used to describing the word.",
          "For example:",
          "When describing Noah, the words Ark, Flood, Rainbow, Forty, and Dove cannot be used to describe Noah.",
          "If the team guesses the word correctly within 1 minute, the team wins a point. The first team to win 15 points wins."
        ]
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 1,
    "rule_text": "READ THE VERSE\nIf you want to enrich days, plant flowers; if you wish to enrich years, plant trees; if you wish to enrich eternity, plant ideals in the lives of others.\nANSWER THE QUESTION\nWho has influenced you the most in your life? How?",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-inspirational-talk-1",
        "contentItemId": "game-inspirational-talk-1",
        "heading": "READ THE VERSE, ANSWER THE QUESTION",
        "subheading": "Inspirational Talk 1",
        "rules": [
          "READ THE VERSE",
          "If you want to enrich days, plant flowers; if you wish to enrich years, plant trees; if you wish to enrich eternity, plant ideals in the lives of others.",
          "ANSWER THE QUESTION",
          "Who has influenced you the most in your life? How?"
        ]
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 1,
    "rule_text": "READ THE VERSE\nThe Magi, who studied the stars, came from the east to Jerusalem and asked, \"Where is the baby born to be the king of the Jews? We have come to worship Him?\"\nANSWER THE QUESTION\nWhat is the most important thing you have looked for?",
    "metadata": {
      "source": "mockData",
      "source_rule": {
        "id": "rule-inspirational-talk-2",
        "contentItemId": "game-inspirational-talk-2",
        "heading": "READ THE VERSE, ANSWER THE QUESTION",
        "subheading": "Inspirational Talk 2",
        "rules": [
          "READ THE VERSE",
          "The Magi, who studied the stars, came from the east to Jerusalem and asked, \"Where is the baby born to be the king of the Jews? We have come to worship Him?\"",
          "ANSWER THE QUESTION",
          "What is the most important thing you have looked for?"
        ]
      }
    }
  }
]$game_rules$::jsonb) as seed(
  game_id text, sort_order integer, rule_text text, metadata jsonb
)
on conflict (game_id, sort_order) do update set
  rule_text = excluded.rule_text,
  metadata = excluded.metadata;

-- Card metadata retains each active getGameCards() result and its original source card.
insert into public.game_cards (game_id, sort_order, front_text, back_text, metadata)
select seed.game_id, seed.sort_order, seed.front_text, seed.back_text, seed.metadata
from jsonb_to_recordset($game_cards$[
  {
    "game_id": "game-bible-action",
    "sort_order": 1,
    "front_text": "12 Disciples",
    "back_text": "Luke 6:13",
    "metadata": {
      "pairs": [
        {
          "left": "12 Disciples",
          "right": "Luke 6:13"
        },
        {
          "left": "40 days",
          "right": "Exodus 24:18"
        },
        {
          "left": "Abba",
          "right": "Mark 14:36"
        },
        {
          "left": "Adam and Eve",
          "right": "Genesis 2"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "12 Disciples",
            "right": "Luke 6:13"
          },
          {
            "left": "40 days",
            "right": "Exodus 24:18"
          },
          {
            "left": "Abba",
            "right": "Mark 14:36"
          },
          {
            "left": "Adam and Eve",
            "right": "Genesis 2"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 2,
    "front_text": "Altar",
    "back_text": "Leviticus 1:15",
    "metadata": {
      "pairs": [
        {
          "left": "Altar",
          "right": "Leviticus 1:15"
        },
        {
          "left": "Amen",
          "right": "1 Chronicles 16:36"
        },
        {
          "left": "Angel",
          "right": "Genesis 48:16"
        },
        {
          "left": "Apples",
          "right": "Song of Solomon 2:5"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Altar",
            "right": "Leviticus 1:15"
          },
          {
            "left": "Amen",
            "right": "1 Chronicles 16:36"
          },
          {
            "left": "Angel",
            "right": "Genesis 48:16"
          },
          {
            "left": "Apples",
            "right": "Song of Solomon 2:5"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 3,
    "front_text": "Horse",
    "back_text": "Revelation 6:8",
    "metadata": {
      "pairs": [
        {
          "left": "Horse",
          "right": "Revelation 6:8"
        },
        {
          "left": "Ark",
          "right": "Genesis 7:1"
        },
        {
          "left": "Army",
          "right": "Exodus 14:6"
        },
        {
          "left": "Knock",
          "right": "Matthew 7:7"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Horse",
            "right": "Revelation 6:8"
          },
          {
            "left": "Ark",
            "right": "Genesis 7:1"
          },
          {
            "left": "Army",
            "right": "Exodus 14:6"
          },
          {
            "left": "Knock",
            "right": "Matthew 7:7"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 4,
    "front_text": "Baby",
    "back_text": "Exodus 2:6",
    "metadata": {
      "pairs": [
        {
          "left": "Baby",
          "right": "Exodus 2:6"
        },
        {
          "left": "Baptism",
          "right": "Matthew 3:13"
        },
        {
          "left": "Bathsheba",
          "right": "2 Samuel 11"
        },
        {
          "left": "Beast",
          "right": "Revelation 16:2"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Baby",
            "right": "Exodus 2:6"
          },
          {
            "left": "Baptism",
            "right": "Matthew 3:13"
          },
          {
            "left": "Bathsheba",
            "right": "2 Samuel 11"
          },
          {
            "left": "Beast",
            "right": "Revelation 16:2"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 5,
    "front_text": "Bible",
    "back_text": "",
    "metadata": {
      "pairs": [
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Blood",
          "right": "John 6:53"
        },
        {
          "left": "Book",
          "right": "Exodus 24:7"
        },
        {
          "left": "Bow",
          "right": "Genesis 27:29"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Bible",
            "right": ""
          },
          {
            "left": "Blood",
            "right": "John 6:53"
          },
          {
            "left": "Book",
            "right": "Exodus 24:7"
          },
          {
            "left": "Bow",
            "right": "Genesis 27:29"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 6,
    "front_text": "Bracelet",
    "back_text": "Ezekiel 16:11",
    "metadata": {
      "pairs": [
        {
          "left": "Bracelet",
          "right": "Ezekiel 16:11"
        },
        {
          "left": "Earrings",
          "right": "Isaiah 3:19"
        },
        {
          "left": "Bread",
          "right": "Mark 8:14"
        },
        {
          "left": "Belt",
          "right": "Ephesians 6:14"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Bracelet",
            "right": "Ezekiel 16:11"
          },
          {
            "left": "Earrings",
            "right": "Isaiah 3:19"
          },
          {
            "left": "Bread",
            "right": "Mark 8:14"
          },
          {
            "left": "Belt",
            "right": "Ephesians 6:14"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 7,
    "front_text": "Brother",
    "back_text": "Philemon 1:7",
    "metadata": {
      "pairs": [
        {
          "left": "Brother",
          "right": "Philemon 1:7"
        },
        {
          "left": "Burn",
          "right": "Exodus 3:2"
        },
        {
          "left": "Camel",
          "right": "Genesis 24:10"
        },
        {
          "left": "Carpenter",
          "right": "Isaiah 13:44"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Brother",
            "right": "Philemon 1:7"
          },
          {
            "left": "Burn",
            "right": "Exodus 3:2"
          },
          {
            "left": "Camel",
            "right": "Genesis 24:10"
          },
          {
            "left": "Carpenter",
            "right": "Isaiah 13:44"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 8,
    "front_text": "Chains",
    "back_text": "Philippians 1:7",
    "metadata": {
      "pairs": [
        {
          "left": "Chains",
          "right": "Philippians 1:7"
        },
        {
          "left": "Child",
          "right": "Matthew 18:2-6"
        },
        {
          "left": "Christ",
          "right": "John 1:41"
        },
        {
          "left": "Coin",
          "right": "Luke 15:8"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Chains",
            "right": "Philippians 1:7"
          },
          {
            "left": "Child",
            "right": "Matthew 18:2-6"
          },
          {
            "left": "Christ",
            "right": "John 1:41"
          },
          {
            "left": "Coin",
            "right": "Luke 15:8"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 9,
    "front_text": "Covenant",
    "back_text": "Genesis 15:1",
    "metadata": {
      "pairs": [
        {
          "left": "Covenant",
          "right": "Genesis 15:1"
        },
        {
          "left": "Cow",
          "right": "Genesis 32:15"
        },
        {
          "left": "Cross",
          "right": "Luke 23:26"
        },
        {
          "left": "Harp",
          "right": "1 Chronicles 15:16"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Covenant",
            "right": "Genesis 15:1"
          },
          {
            "left": "Cow",
            "right": "Genesis 32:15"
          },
          {
            "left": "Cross",
            "right": "Luke 23:26"
          },
          {
            "left": "Harp",
            "right": "1 Chronicles 15:16"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 10,
    "front_text": "Crucifixion",
    "back_text": "John 18:19",
    "metadata": {
      "pairs": [
        {
          "left": "Crucifixion",
          "right": "John 18:19"
        },
        {
          "left": "Cymbals",
          "right": "2 Samuel 6:5"
        },
        {
          "left": "David and Goliath",
          "right": "1 Samuel 17"
        },
        {
          "left": "Days",
          "right": "Genesis 1:14"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Crucifixion",
            "right": "John 18:19"
          },
          {
            "left": "Cymbals",
            "right": "2 Samuel 6:5"
          },
          {
            "left": "David and Goliath",
            "right": "1 Samuel 17"
          },
          {
            "left": "Days",
            "right": "Genesis 1:14"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 11,
    "front_text": "Dead",
    "back_text": "Romans 6:9",
    "metadata": {
      "pairs": [
        {
          "left": "Dead",
          "right": "Romans 6:9"
        },
        {
          "left": "Death",
          "right": "Romans 5:12"
        },
        {
          "left": "Devil",
          "right": "Hebrews 2:14"
        },
        {
          "left": "Delilah",
          "right": "Judges 16:13"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Dead",
            "right": "Romans 6:9"
          },
          {
            "left": "Death",
            "right": "Romans 5:12"
          },
          {
            "left": "Devil",
            "right": "Hebrews 2:14"
          },
          {
            "left": "Delilah",
            "right": "Judges 16:13"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 12,
    "front_text": "Dove",
    "back_text": "Genesis 8:9",
    "metadata": {
      "pairs": [
        {
          "left": "Dove",
          "right": "Genesis 8:9"
        },
        {
          "left": "Dragon",
          "right": "Revelation 12:7"
        },
        {
          "left": "Dream",
          "right": "Daniel 7:1"
        },
        {
          "left": "Drink",
          "right": "Numbers 28:7"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Dove",
            "right": "Genesis 8:9"
          },
          {
            "left": "Dragon",
            "right": "Revelation 12:7"
          },
          {
            "left": "Dream",
            "right": "Daniel 7:1"
          },
          {
            "left": "Drink",
            "right": "Numbers 28:7"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 13,
    "front_text": "Eagle",
    "back_text": "Proverbs 23:5",
    "metadata": {
      "pairs": [
        {
          "left": "Eagle",
          "right": "Proverbs 23:5"
        },
        {
          "left": "Earthquake",
          "right": "Revelation 16:18"
        },
        {
          "left": "Egyptian",
          "right": "Acts 7:24"
        },
        {
          "left": "Elder",
          "right": "3 John 1:1"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Eagle",
            "right": "Proverbs 23:5"
          },
          {
            "left": "Earthquake",
            "right": "Revelation 16:18"
          },
          {
            "left": "Egyptian",
            "right": "Acts 7:24"
          },
          {
            "left": "Elder",
            "right": "3 John 1:1"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 14,
    "front_text": "Eye",
    "back_text": "Matthew 5:38",
    "metadata": {
      "pairs": [
        {
          "left": "Eye",
          "right": "Matthew 5:38"
        },
        {
          "left": "Family",
          "right": "Joshua 7:14"
        },
        {
          "left": "Jump",
          "right": "John 21:7"
        },
        {
          "left": "Farmer",
          "right": "2 Timothy 2:6"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Eye",
            "right": "Matthew 5:38"
          },
          {
            "left": "Family",
            "right": "Joshua 7:14"
          },
          {
            "left": "Jump",
            "right": "John 21:7"
          },
          {
            "left": "Farmer",
            "right": "2 Timothy 2:6"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 15,
    "front_text": "Fast and Pray",
    "back_text": "Acts 13:3",
    "metadata": {
      "pairs": [
        {
          "left": "Fast and Pray",
          "right": "Acts 13:3"
        },
        {
          "left": "Father",
          "right": "John 8:19"
        },
        {
          "left": "Fear",
          "right": "1 John 4:18"
        },
        {
          "left": "Fear God",
          "right": "Ecclesiastes 12:13"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Fast and Pray",
            "right": "Acts 13:3"
          },
          {
            "left": "Father",
            "right": "John 8:19"
          },
          {
            "left": "Fear",
            "right": "1 John 4:18"
          },
          {
            "left": "Fear God",
            "right": "Ecclesiastes 12:13"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 16,
    "front_text": "Fire",
    "back_text": "Exodus 3:2",
    "metadata": {
      "pairs": [
        {
          "left": "Fire",
          "right": "Exodus 3:2"
        },
        {
          "left": "First-fruits",
          "right": "Nehemiah 12:44"
        },
        {
          "left": "Fisherman",
          "right": "Matthew 4:18"
        },
        {
          "left": "Flood",
          "right": "Genesis 6:9"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Fire",
            "right": "Exodus 3:2"
          },
          {
            "left": "First-fruits",
            "right": "Nehemiah 12:44"
          },
          {
            "left": "Fisherman",
            "right": "Matthew 4:18"
          },
          {
            "left": "Flood",
            "right": "Genesis 6:9"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 17,
    "front_text": "Food offering",
    "back_text": "Exodus 29:41",
    "metadata": {
      "pairs": [
        {
          "left": "Food offering",
          "right": "Exodus 29:41"
        },
        {
          "left": "Seven Days",
          "right": "Genesis 29:20"
        },
        {
          "left": "Free",
          "right": "John 8:36"
        },
        {
          "left": "Friend",
          "right": "Psalm 55:13"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Food offering",
            "right": "Exodus 29:41"
          },
          {
            "left": "Seven Days",
            "right": "Genesis 29:20"
          },
          {
            "left": "Free",
            "right": "John 8:36"
          },
          {
            "left": "Friend",
            "right": "Psalm 55:13"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 18,
    "front_text": "Gate",
    "back_text": "Ezekiel 46:9",
    "metadata": {
      "pairs": [
        {
          "left": "Gate",
          "right": "Ezekiel 46:9"
        },
        {
          "left": "Gentle",
          "right": "Ephesians 4:2"
        },
        {
          "left": "Gift",
          "right": "Romans 5:15"
        },
        {
          "left": "Love God",
          "right": "Deuteronomy 11:13"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Gate",
            "right": "Ezekiel 46:9"
          },
          {
            "left": "Gentle",
            "right": "Ephesians 4:2"
          },
          {
            "left": "Gift",
            "right": "Romans 5:15"
          },
          {
            "left": "Love God",
            "right": "Deuteronomy 11:13"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 19,
    "front_text": "God",
    "back_text": "",
    "metadata": {
      "pairs": [
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "God's Armor",
          "right": "Ephesians 6:9-11"
        },
        {
          "left": "God's love",
          "right": "John 3:16"
        },
        {
          "left": "Gold",
          "right": "1 Kings 6:21"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "God",
            "right": ""
          },
          {
            "left": "God's Armor",
            "right": "Ephesians 6:9-11"
          },
          {
            "left": "God's love",
            "right": "John 3:16"
          },
          {
            "left": "Gold",
            "right": "1 Kings 6:21"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 20,
    "front_text": "Golden Rule",
    "back_text": "Matthew 7:12",
    "metadata": {
      "pairs": [
        {
          "left": "Golden Rule",
          "right": "Matthew 7:12"
        },
        {
          "left": "Good",
          "right": "Luke 6:33"
        },
        {
          "left": "Grasshopper",
          "right": "Psalm 78:46"
        },
        {
          "left": "Hands",
          "right": "2 Kings 13:16"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Golden Rule",
            "right": "Matthew 7:12"
          },
          {
            "left": "Good",
            "right": "Luke 6:33"
          },
          {
            "left": "Grasshopper",
            "right": "Psalm 78:46"
          },
          {
            "left": "Hands",
            "right": "2 Kings 13:16"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 21,
    "front_text": "Happiness",
    "back_text": "Matthew 25:21",
    "metadata": {
      "pairs": [
        {
          "left": "Happiness",
          "right": "Matthew 25:21"
        },
        {
          "left": "Head",
          "right": "1 Corinthians 11:3"
        },
        {
          "left": "Heal",
          "right": "Luke 10:9"
        },
        {
          "left": "Bride",
          "right": "Song of Songs 4:9"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Happiness",
            "right": "Matthew 25:21"
          },
          {
            "left": "Head",
            "right": "1 Corinthians 11:3"
          },
          {
            "left": "Heal",
            "right": "Luke 10:9"
          },
          {
            "left": "Bride",
            "right": "Song of Songs 4:9"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 22,
    "front_text": "Heart",
    "back_text": "Psalm 57:7",
    "metadata": {
      "pairs": [
        {
          "left": "Heart",
          "right": "Psalm 57:7"
        },
        {
          "left": "Tears",
          "right": "Job 16:20"
        },
        {
          "left": "Heaven",
          "right": "Matthew 16:19"
        },
        {
          "left": "Hell",
          "right": "Mark 9:43"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Heart",
            "right": "Psalm 57:7"
          },
          {
            "left": "Tears",
            "right": "Job 16:20"
          },
          {
            "left": "Heaven",
            "right": "Matthew 16:19"
          },
          {
            "left": "Hell",
            "right": "Mark 9:43"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 23,
    "front_text": "Helmet",
    "back_text": "Ephesians 6:17",
    "metadata": {
      "pairs": [
        {
          "left": "Helmet",
          "right": "Ephesians 6:17"
        },
        {
          "left": "High Priest",
          "right": "Hebrews 8:1"
        },
        {
          "left": "Holy",
          "right": "Leviticus 21:8"
        },
        {
          "left": "House",
          "right": "Psalm 135:2"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Helmet",
            "right": "Ephesians 6:17"
          },
          {
            "left": "High Priest",
            "right": "Hebrews 8:1"
          },
          {
            "left": "Holy",
            "right": "Leviticus 21:8"
          },
          {
            "left": "House",
            "right": "Psalm 135:2"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 24,
    "front_text": "Hymn",
    "back_text": "Matthew 26:30",
    "metadata": {
      "pairs": [
        {
          "left": "Hymn",
          "right": "Matthew 26:30"
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Judas",
          "right": "Luke 6:16"
        },
        {
          "left": "Peter",
          "right": "Matthew 14:28"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Hymn",
            "right": "Matthew 26:30"
          },
          {
            "left": "Jesus",
            "right": ""
          },
          {
            "left": "Judas",
            "right": "Luke 6:16"
          },
          {
            "left": "Peter",
            "right": "Matthew 14:28"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 25,
    "front_text": "Judgment day",
    "back_text": "Matthew 7:22",
    "metadata": {
      "pairs": [
        {
          "left": "Judgment day",
          "right": "Matthew 7:22"
        },
        {
          "left": "Justice",
          "right": "Deuteronomy 16:20"
        },
        {
          "left": "King",
          "right": "2 Kings 3:9"
        },
        {
          "left": "Kingdom",
          "right": "Luke 17:20"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Judgment day",
            "right": "Matthew 7:22"
          },
          {
            "left": "Justice",
            "right": "Deuteronomy 16:20"
          },
          {
            "left": "King",
            "right": "2 Kings 3:9"
          },
          {
            "left": "Kingdom",
            "right": "Luke 17:20"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 26,
    "front_text": "Knowledge",
    "back_text": "1 Corinthians 8:1",
    "metadata": {
      "pairs": [
        {
          "left": "Knowledge",
          "right": "1 Corinthians 8:1"
        },
        {
          "left": "Lamb",
          "right": "Revelation 14:4"
        },
        {
          "left": "Law",
          "right": "Romans 2:14"
        },
        {
          "left": "Lay hands",
          "right": "Acts 28:8"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Knowledge",
            "right": "1 Corinthians 8:1"
          },
          {
            "left": "Lamb",
            "right": "Revelation 14:4"
          },
          {
            "left": "Law",
            "right": "Romans 2:14"
          },
          {
            "left": "Lay hands",
            "right": "Acts 28:8"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 27,
    "front_text": "Leader",
    "back_text": "2 Chronicles 13:12",
    "metadata": {
      "pairs": [
        {
          "left": "Leader",
          "right": "2 Chronicles 13:12"
        },
        {
          "left": "Light",
          "right": "Genesis 1:3"
        },
        {
          "left": "Lion",
          "right": "Proverbs 28:15"
        },
        {
          "left": "Listen carefully",
          "right": "Genesis 27:8"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Leader",
            "right": "2 Chronicles 13:12"
          },
          {
            "left": "Light",
            "right": "Genesis 1:3"
          },
          {
            "left": "Lion",
            "right": "Proverbs 28:15"
          },
          {
            "left": "Listen carefully",
            "right": "Genesis 27:8"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 28,
    "front_text": "Living water",
    "back_text": "John 4:10",
    "metadata": {
      "pairs": [
        {
          "left": "Living water",
          "right": "John 4:10"
        },
        {
          "left": "Look",
          "right": "Psalm 123:2"
        },
        {
          "left": "Lost sheep",
          "right": "Luke 15:4"
        },
        {
          "left": "Love",
          "right": "1 John 4:7"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Living water",
            "right": "John 4:10"
          },
          {
            "left": "Look",
            "right": "Psalm 123:2"
          },
          {
            "left": "Lost sheep",
            "right": "Luke 15:4"
          },
          {
            "left": "Love",
            "right": "1 John 4:7"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 29,
    "front_text": "Melons",
    "back_text": "Numbers 11:5",
    "metadata": {
      "pairs": [
        {
          "left": "Melons",
          "right": "Numbers 11:5"
        },
        {
          "left": "Men",
          "right": "Psalm 148:12"
        },
        {
          "left": "Mighty men",
          "right": "Ezekiel 39:20"
        },
        {
          "left": "Mind",
          "right": "1 Samuel 15:29"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Melons",
            "right": "Numbers 11:5"
          },
          {
            "left": "Men",
            "right": "Psalm 148:12"
          },
          {
            "left": "Mighty men",
            "right": "Ezekiel 39:20"
          },
          {
            "left": "Mind",
            "right": "1 Samuel 15:29"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 30,
    "front_text": "Miracle",
    "back_text": "John 7:21",
    "metadata": {
      "pairs": [
        {
          "left": "Miracle",
          "right": "John 7:21"
        },
        {
          "left": "Money",
          "right": "1 Timothy 6:10"
        },
        {
          "left": "Moon",
          "right": "Joshua 10:13"
        },
        {
          "left": "Moses",
          "right": "Exodus 2"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Miracle",
            "right": "John 7:21"
          },
          {
            "left": "Money",
            "right": "1 Timothy 6:10"
          },
          {
            "left": "Moon",
            "right": "Joshua 10:13"
          },
          {
            "left": "Moses",
            "right": "Exodus 2"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 31,
    "front_text": "Mother",
    "back_text": "Matthew 15:4",
    "metadata": {
      "pairs": [
        {
          "left": "Mother",
          "right": "Matthew 15:4"
        },
        {
          "left": "Mouth",
          "right": "Proverbs 10:11"
        },
        {
          "left": "Musician",
          "right": "2 Chronicles 5:13"
        },
        {
          "left": "Name",
          "right": "Matthew 7:22"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Mother",
            "right": "Matthew 15:4"
          },
          {
            "left": "Mouth",
            "right": "Proverbs 10:11"
          },
          {
            "left": "Musician",
            "right": "2 Chronicles 5:13"
          },
          {
            "left": "Name",
            "right": "Matthew 7:22"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 32,
    "front_text": "Necklace",
    "back_text": "Psalm 73:6",
    "metadata": {
      "pairs": [
        {
          "left": "Necklace",
          "right": "Psalm 73:6"
        },
        {
          "left": "Offering",
          "right": "Leviticus 7:37"
        },
        {
          "left": "Oil",
          "right": "Exodus 35:28"
        },
        {
          "left": "Old",
          "right": "Luke 5:39"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Necklace",
            "right": "Psalm 73:6"
          },
          {
            "left": "Offering",
            "right": "Leviticus 7:37"
          },
          {
            "left": "Oil",
            "right": "Exodus 35:28"
          },
          {
            "left": "Old",
            "right": "Luke 5:39"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 33,
    "front_text": "Peace",
    "back_text": "Jeremiah 6:14",
    "metadata": {
      "pairs": [
        {
          "left": "Peace",
          "right": "Jeremiah 6:14"
        },
        {
          "left": "Perfume",
          "right": "Song of Solomon 1:3"
        },
        {
          "left": "Pharoah",
          "right": "Deuteronomy 6:21"
        },
        {
          "left": "Poor",
          "right": "Proverbs 28:8"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Peace",
            "right": "Jeremiah 6:14"
          },
          {
            "left": "Perfume",
            "right": "Song of Solomon 1:3"
          },
          {
            "left": "Pharoah",
            "right": "Deuteronomy 6:21"
          },
          {
            "left": "Poor",
            "right": "Proverbs 28:8"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 34,
    "front_text": "Power",
    "back_text": "Ephesians 1:19",
    "metadata": {
      "pairs": [
        {
          "left": "Power",
          "right": "Ephesians 1:19"
        },
        {
          "left": "Preacher",
          "right": "2 Peter 2:5"
        },
        {
          "left": "Prisoners",
          "right": "Acts 27:1"
        },
        {
          "left": "Prophet",
          "right": "Hosea 12:13"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Power",
            "right": "Ephesians 1:19"
          },
          {
            "left": "Preacher",
            "right": "2 Peter 2:5"
          },
          {
            "left": "Prisoners",
            "right": "Acts 27:1"
          },
          {
            "left": "Prophet",
            "right": "Hosea 12:13"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 35,
    "front_text": "Psalm",
    "back_text": "",
    "metadata": {
      "pairs": [
        {
          "left": "Psalm",
          "right": ""
        },
        {
          "left": "Queen",
          "right": "Isaiah 47:7"
        },
        {
          "left": "Rain",
          "right": "Zechariah 10:1"
        },
        {
          "left": "Receive",
          "right": "Matthew 21:22"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Psalm",
            "right": ""
          },
          {
            "left": "Queen",
            "right": "Isaiah 47:7"
          },
          {
            "left": "Rain",
            "right": "Zechariah 10:1"
          },
          {
            "left": "Receive",
            "right": "Matthew 21:22"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 36,
    "front_text": "Rest",
    "back_text": "Hebrews 4:1",
    "metadata": {
      "pairs": [
        {
          "left": "Rest",
          "right": "Hebrews 4:1"
        },
        {
          "left": "Resurrection",
          "right": "John 20"
        },
        {
          "left": "Reward",
          "right": "Psalm 62:12"
        },
        {
          "left": "Rich",
          "right": "James 5:1"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Rest",
            "right": "Hebrews 4:1"
          },
          {
            "left": "Resurrection",
            "right": "John 20"
          },
          {
            "left": "Reward",
            "right": "Psalm 62:12"
          },
          {
            "left": "Rich",
            "right": "James 5:1"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 37,
    "front_text": "Right hand",
    "back_text": "Psalm 118:16",
    "metadata": {
      "pairs": [
        {
          "left": "Right hand",
          "right": "Psalm 118:16"
        },
        {
          "left": "Ring",
          "right": "Genesis 24:47"
        },
        {
          "left": "Rooster",
          "right": "Matthew 26:34"
        },
        {
          "left": "Root",
          "right": "Proverbs 12:12"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Right hand",
            "right": "Psalm 118:16"
          },
          {
            "left": "Ring",
            "right": "Genesis 24:47"
          },
          {
            "left": "Rooster",
            "right": "Matthew 26:34"
          },
          {
            "left": "Root",
            "right": "Proverbs 12:12"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 38,
    "front_text": "Rose",
    "back_text": "Song of Songs 2:1",
    "metadata": {
      "pairs": [
        {
          "left": "Rose",
          "right": "Song of Songs 2:1"
        },
        {
          "left": "Ruler",
          "right": "Micah 5:1"
        },
        {
          "left": "Samson",
          "right": "Judges 16:13"
        },
        {
          "left": "Satan",
          "right": "Job 2:2"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Rose",
            "right": "Song of Songs 2:1"
          },
          {
            "left": "Ruler",
            "right": "Micah 5:1"
          },
          {
            "left": "Samson",
            "right": "Judges 16:13"
          },
          {
            "left": "Satan",
            "right": "Job 2:2"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 39,
    "front_text": "Scroll",
    "back_text": "Revelation 22:18",
    "metadata": {
      "pairs": [
        {
          "left": "Scroll",
          "right": "Revelation 22:18"
        },
        {
          "left": "Sea",
          "right": "Exodus 14:16"
        },
        {
          "left": "Search",
          "right": "Psalm 4:4"
        },
        {
          "left": "Self-control",
          "right": "Galatians 5:23"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Scroll",
            "right": "Revelation 22:18"
          },
          {
            "left": "Sea",
            "right": "Exodus 14:16"
          },
          {
            "left": "Search",
            "right": "Psalm 4:4"
          },
          {
            "left": "Self-control",
            "right": "Galatians 5:23"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 40,
    "front_text": "Serpent",
    "back_text": "Genesis 3:4",
    "metadata": {
      "pairs": [
        {
          "left": "Serpent",
          "right": "Genesis 3:4"
        },
        {
          "left": "Servant",
          "right": "Proverbs 14:35"
        },
        {
          "left": "Shepherd",
          "right": "John 10:11"
        },
        {
          "left": "Sick",
          "right": "Luke 9:2"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Serpent",
            "right": "Genesis 3:4"
          },
          {
            "left": "Servant",
            "right": "Proverbs 14:35"
          },
          {
            "left": "Shepherd",
            "right": "John 10:11"
          },
          {
            "left": "Sick",
            "right": "Luke 9:2"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 41,
    "front_text": "Sin",
    "back_text": "Romans 8:3",
    "metadata": {
      "pairs": [
        {
          "left": "Sin",
          "right": "Romans 8:3"
        },
        {
          "left": "Sing",
          "right": "Psalm 33:1"
        },
        {
          "left": "Slave",
          "right": "Romans 7:14"
        },
        {
          "left": "Sling",
          "right": "1 Samuel 17:50"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Sin",
            "right": "Romans 8:3"
          },
          {
            "left": "Sing",
            "right": "Psalm 33:1"
          },
          {
            "left": "Slave",
            "right": "Romans 7:14"
          },
          {
            "left": "Sling",
            "right": "1 Samuel 17:50"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 42,
    "front_text": "Snake",
    "back_text": "Proverbs 23:32",
    "metadata": {
      "pairs": [
        {
          "left": "Snake",
          "right": "Proverbs 23:32"
        },
        {
          "left": "Soldier",
          "right": "2 Timothy 2:4"
        },
        {
          "left": "Son",
          "right": "Luke 3:34"
        },
        {
          "left": "Soul",
          "right": "Matthew 16:26"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Snake",
            "right": "Proverbs 23:32"
          },
          {
            "left": "Soldier",
            "right": "2 Timothy 2:4"
          },
          {
            "left": "Son",
            "right": "Luke 3:34"
          },
          {
            "left": "Soul",
            "right": "Matthew 16:26"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 43,
    "front_text": "Spy",
    "back_text": "Joshua 2:2",
    "metadata": {
      "pairs": [
        {
          "left": "Spy",
          "right": "Joshua 2:2"
        },
        {
          "left": "Stand",
          "right": "Luke 21:19"
        },
        {
          "left": "Star",
          "right": "Matthew 2:7"
        },
        {
          "left": "Stars",
          "right": "Genesis 1:16"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Spy",
            "right": "Joshua 2:2"
          },
          {
            "left": "Stand",
            "right": "Luke 21:19"
          },
          {
            "left": "Star",
            "right": "Matthew 2:7"
          },
          {
            "left": "Stars",
            "right": "Genesis 1:16"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 44,
    "front_text": "Stone tablet",
    "back_text": "Exodus 34:4",
    "metadata": {
      "pairs": [
        {
          "left": "Stone tablet",
          "right": "Exodus 34:4"
        },
        {
          "left": "Storm",
          "right": "Matthew 8:23"
        },
        {
          "left": "Strong",
          "right": "Ephesians 6:10"
        },
        {
          "left": "Sun",
          "right": "Psalm 121:6"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Stone tablet",
            "right": "Exodus 34:4"
          },
          {
            "left": "Storm",
            "right": "Matthew 8:23"
          },
          {
            "left": "Strong",
            "right": "Ephesians 6:10"
          },
          {
            "left": "Sun",
            "right": "Psalm 121:6"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 45,
    "front_text": "Sword",
    "back_text": "Matthew 26:52",
    "metadata": {
      "pairs": [
        {
          "left": "Sword",
          "right": "Matthew 26:52"
        },
        {
          "left": "Teacher",
          "right": "Mark 10:20"
        },
        {
          "left": "Temple",
          "right": "1 Corinthians 3:17"
        },
        {
          "left": "Ten Commandments",
          "right": "Exodus 34:28"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Sword",
            "right": "Matthew 26:52"
          },
          {
            "left": "Teacher",
            "right": "Mark 10:20"
          },
          {
            "left": "Temple",
            "right": "1 Corinthians 3:17"
          },
          {
            "left": "Ten Commandments",
            "right": "Exodus 34:28"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 46,
    "front_text": "Tent",
    "back_text": "Genesis 31:33",
    "metadata": {
      "pairs": [
        {
          "left": "Tent",
          "right": "Genesis 31:33"
        },
        {
          "left": "Throne",
          "right": "Genesis 41:40"
        },
        {
          "left": "Tongue",
          "right": "Psalm 139:4"
        },
        {
          "left": "Trumpet",
          "right": "Joshua 6:20"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Tent",
            "right": "Genesis 31:33"
          },
          {
            "left": "Throne",
            "right": "Genesis 41:40"
          },
          {
            "left": "Tongue",
            "right": "Psalm 139:4"
          },
          {
            "left": "Trumpet",
            "right": "Joshua 6:20"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 47,
    "front_text": "Unclean",
    "back_text": "Romans 14:14",
    "metadata": {
      "pairs": [
        {
          "left": "Unclean",
          "right": "Romans 14:14"
        },
        {
          "left": "Vinegar",
          "right": "Ruth 2:14"
        },
        {
          "left": "Voice",
          "right": "John 10:27"
        },
        {
          "left": "Wait",
          "right": "Psalm 27:14"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Unclean",
            "right": "Romans 14:14"
          },
          {
            "left": "Vinegar",
            "right": "Ruth 2:14"
          },
          {
            "left": "Voice",
            "right": "John 10:27"
          },
          {
            "left": "Wait",
            "right": "Psalm 27:14"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 48,
    "front_text": "Wall",
    "back_text": "2 Kings 20:2",
    "metadata": {
      "pairs": [
        {
          "left": "Wall",
          "right": "2 Kings 20:2"
        },
        {
          "left": "War",
          "right": "Deuteronomy 1:20"
        },
        {
          "left": "Warrior",
          "right": "Psalm 16:33"
        },
        {
          "left": "Water",
          "right": "John 4:14"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Wall",
            "right": "2 Kings 20:2"
          },
          {
            "left": "War",
            "right": "Deuteronomy 1:20"
          },
          {
            "left": "Warrior",
            "right": "Psalm 16:33"
          },
          {
            "left": "Water",
            "right": "John 4:14"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 49,
    "front_text": "Whale",
    "back_text": "Jonah 1:17",
    "metadata": {
      "pairs": [
        {
          "left": "Whale",
          "right": "Jonah 1:17"
        },
        {
          "left": "Wife",
          "right": "Proverbs 12:14"
        },
        {
          "left": "Wine",
          "right": "John 2:3"
        },
        {
          "left": "Wisdom",
          "right": "James 3:13"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Whale",
            "right": "Jonah 1:17"
          },
          {
            "left": "Wife",
            "right": "Proverbs 12:14"
          },
          {
            "left": "Wine",
            "right": "John 2:3"
          },
          {
            "left": "Wisdom",
            "right": "James 3:13"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-action",
    "sort_order": 50,
    "front_text": "Woman",
    "back_text": "Deuteronomy 28:56",
    "metadata": {
      "pairs": [
        {
          "left": "Woman",
          "right": "Deuteronomy 28:56"
        },
        {
          "left": "World",
          "right": "John 3:16"
        },
        {
          "left": "Worship",
          "right": "Psalm 99:5"
        },
        {
          "left": "Years",
          "right": "2 Samuel 5:4"
        }
      ],
      "source_card": {
        "pairs": [
          {
            "left": "Woman",
            "right": "Deuteronomy 28:56"
          },
          {
            "left": "World",
            "right": "John 3:16"
          },
          {
            "left": "Worship",
            "right": "Psalm 99:5"
          },
          {
            "left": "Years",
            "right": "2 Samuel 5:4"
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 1,
    "front_text": "1. Sacrificial Offering",
    "back_text": "",
    "metadata": {
      "id": 1,
      "contentItemId": "game-bible-draw",
      "sortOrder": 1,
      "pairs": [
        {
          "left": "1. Sacrificial Offering",
          "right": ""
        },
        {
          "left": "2. A symbol of life",
          "right": ""
        },
        {
          "left": "3. People need the Lord",
          "right": ""
        },
        {
          "left": "4. The Lamb of God",
          "right": ""
        },
        {
          "left": "5. Bearing the fruits",
          "right": ""
        }
      ],
      "source_card": {
        "id": 1,
        "items": [
          "1. Sacrificial Offering",
          "2. A symbol of life",
          "3. People need the Lord",
          "4. The Lamb of God",
          "5. Bearing the fruits"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 2,
    "front_text": "1. Christ the Bread of Life",
    "back_text": "",
    "metadata": {
      "id": 2,
      "contentItemId": "game-bible-draw",
      "sortOrder": 2,
      "pairs": [
        {
          "left": "1. Christ the Bread of Life",
          "right": ""
        },
        {
          "left": "2. Parable of the Bridegroom",
          "right": ""
        },
        {
          "left": "3. The Feast of the Passover",
          "right": ""
        },
        {
          "left": "4. Craftsman",
          "right": ""
        },
        {
          "left": "5. Quick to listen",
          "right": ""
        }
      ],
      "source_card": {
        "id": 2,
        "items": [
          "1. Christ the Bread of Life",
          "2. Parable of the Bridegroom",
          "3. The Feast of the Passover",
          "4. Craftsman",
          "5. Quick to listen"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 3,
    "front_text": "1. Books of the Bible",
    "back_text": "",
    "metadata": {
      "id": 3,
      "contentItemId": "game-bible-draw",
      "sortOrder": 3,
      "pairs": [
        {
          "left": "1. Books of the Bible",
          "right": ""
        },
        {
          "left": "2. Parables of Jesus",
          "right": ""
        },
        {
          "left": "3. Fruit of the spirit",
          "right": ""
        },
        {
          "left": "4. Mary, Mother of Jesus",
          "right": ""
        },
        {
          "left": "5. Disciples of Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 3,
        "items": [
          "1. Books of the Bible",
          "2. Parables of Jesus",
          "3. Fruit of the spirit",
          "4. Mary, Mother of Jesus",
          "5. Disciples of Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 4,
    "front_text": "1. Dry and thirsty land",
    "back_text": "",
    "metadata": {
      "id": 4,
      "contentItemId": "game-bible-draw",
      "sortOrder": 4,
      "pairs": [
        {
          "left": "1. Dry and thirsty land",
          "right": ""
        },
        {
          "left": "2. Garden of Eden",
          "right": ""
        },
        {
          "left": "3. Eve and the Serpent",
          "right": ""
        },
        {
          "left": "4. Let there be Light",
          "right": ""
        },
        {
          "left": "5. Armies",
          "right": ""
        }
      ],
      "source_card": {
        "id": 4,
        "items": [
          "1. Dry and thirsty land",
          "2. Garden of Eden",
          "3. Eve and the Serpent",
          "4. Let there be Light",
          "5. Armies"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 5,
    "front_text": "1. God's chosen people",
    "back_text": "",
    "metadata": {
      "id": 5,
      "contentItemId": "game-bible-draw",
      "sortOrder": 5,
      "pairs": [
        {
          "left": "1. God's chosen people",
          "right": ""
        },
        {
          "left": "2. Brazen Serpent",
          "right": ""
        },
        {
          "left": "3. Give thanks",
          "right": ""
        },
        {
          "left": "4. Law of Moses",
          "right": ""
        },
        {
          "left": "5. First fruits",
          "right": ""
        }
      ],
      "source_card": {
        "id": 5,
        "items": [
          "1. God's chosen people",
          "2. Brazen Serpent",
          "3. Give thanks",
          "4. Law of Moses",
          "5. First fruits"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 6,
    "front_text": "1. Jesus loves you",
    "back_text": "",
    "metadata": {
      "id": 6,
      "contentItemId": "game-bible-draw",
      "sortOrder": 6,
      "pairs": [
        {
          "left": "1. Jesus loves you",
          "right": ""
        },
        {
          "left": "2. Servant of the Lord",
          "right": ""
        },
        {
          "left": "3. Angels and Demons",
          "right": ""
        },
        {
          "left": "4. Sermon on the Mount",
          "right": ""
        },
        {
          "left": "5. Armor and Weapons",
          "right": ""
        }
      ],
      "source_card": {
        "id": 6,
        "items": [
          "1. Jesus loves you",
          "2. Servant of the Lord",
          "3. Angels and Demons",
          "4. Sermon on the Mount",
          "5. Armor and Weapons"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 7,
    "front_text": "1. Meat Offering",
    "back_text": "",
    "metadata": {
      "id": 7,
      "contentItemId": "game-bible-draw",
      "sortOrder": 7,
      "pairs": [
        {
          "left": "1. Meat Offering",
          "right": ""
        },
        {
          "left": "2. Breastplate",
          "right": ""
        },
        {
          "left": "3. Sack cloth",
          "right": ""
        },
        {
          "left": "4. Lost sheep",
          "right": ""
        },
        {
          "left": "5. Steadfast love",
          "right": ""
        }
      ],
      "source_card": {
        "id": 7,
        "items": [
          "1. Meat Offering",
          "2. Breastplate",
          "3. Sack cloth",
          "4. Lost sheep",
          "5. Steadfast love"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 8,
    "front_text": "1. Book of the Covenant",
    "back_text": "",
    "metadata": {
      "id": 8,
      "contentItemId": "game-bible-draw",
      "sortOrder": 8,
      "pairs": [
        {
          "left": "1. Book of the Covenant",
          "right": ""
        },
        {
          "left": "2. Horsemen",
          "right": ""
        },
        {
          "left": "3. Laying of Hand",
          "right": ""
        },
        {
          "left": "4. Sanctuary",
          "right": ""
        },
        {
          "left": "5. Crucified w/ Christ",
          "right": ""
        }
      ],
      "source_card": {
        "id": 8,
        "items": [
          "1. Book of the Covenant",
          "2. Horsemen",
          "3. Laying of Hand",
          "4. Sanctuary",
          "5. Crucified w/ Christ"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 9,
    "front_text": "1. Spread out the Gospel",
    "back_text": "",
    "metadata": {
      "id": 9,
      "contentItemId": "game-bible-draw",
      "sortOrder": 9,
      "pairs": [
        {
          "left": "1. Spread out the Gospel",
          "right": ""
        },
        {
          "left": "2. River of Egypt",
          "right": ""
        },
        {
          "left": "3. Planted a Vineyard",
          "right": ""
        },
        {
          "left": "4. Scriptures",
          "right": ""
        },
        {
          "left": "5. House of Prayer",
          "right": ""
        }
      ],
      "source_card": {
        "id": 9,
        "items": [
          "1. Spread out the Gospel",
          "2. River of Egypt",
          "3. Planted a Vineyard",
          "4. Scriptures",
          "5. House of Prayer"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 10,
    "front_text": "1. Adam's Rib",
    "back_text": "",
    "metadata": {
      "id": 10,
      "contentItemId": "game-bible-draw",
      "sortOrder": 10,
      "pairs": [
        {
          "left": "1. Adam's Rib",
          "right": ""
        },
        {
          "left": "2. Prince of Peace",
          "right": ""
        },
        {
          "left": "3. Amen",
          "right": ""
        },
        {
          "left": "4. Michael the Archangel",
          "right": ""
        },
        {
          "left": "5. Beginning",
          "right": ""
        }
      ],
      "source_card": {
        "id": 10,
        "items": [
          "1. Adam's Rib",
          "2. Prince of Peace",
          "3. Amen",
          "4. Michael the Archangel",
          "5. Beginning"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 11,
    "front_text": "1. Moses' staff",
    "back_text": "",
    "metadata": {
      "id": 11,
      "contentItemId": "game-bible-draw",
      "sortOrder": 11,
      "pairs": [
        {
          "left": "1. Moses' staff",
          "right": ""
        },
        {
          "left": "2. Crystals",
          "right": ""
        },
        {
          "left": "3. Sapphire",
          "right": ""
        },
        {
          "left": "4. Lake of Fire",
          "right": ""
        },
        {
          "left": "5. Musician",
          "right": ""
        }
      ],
      "source_card": {
        "id": 11,
        "items": [
          "1. Moses' staff",
          "2. Crystals",
          "3. Sapphire",
          "4. Lake of Fire",
          "5. Musician"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 12,
    "front_text": "1. Sanctuary",
    "back_text": "",
    "metadata": {
      "id": 12,
      "contentItemId": "game-bible-draw",
      "sortOrder": 12,
      "pairs": [
        {
          "left": "1. Sanctuary",
          "right": ""
        },
        {
          "left": "2. Golden Spoon",
          "right": ""
        },
        {
          "left": "3. Journey",
          "right": ""
        },
        {
          "left": "4. Sycamore Tree",
          "right": ""
        },
        {
          "left": "5. Harvest",
          "right": ""
        }
      ],
      "source_card": {
        "id": 12,
        "items": [
          "1. Sanctuary",
          "2. Golden Spoon",
          "3. Journey",
          "4. Sycamore Tree",
          "5. Harvest"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 13,
    "front_text": "1. Spiritual Gifts",
    "back_text": "",
    "metadata": {
      "id": 13,
      "contentItemId": "game-bible-draw",
      "sortOrder": 13,
      "pairs": [
        {
          "left": "1. Spiritual Gifts",
          "right": ""
        },
        {
          "left": "2. Thanksgiving",
          "right": ""
        },
        {
          "left": "3. The Creation",
          "right": ""
        },
        {
          "left": "4. Altars destroyed by Gideon",
          "right": ""
        },
        {
          "left": "5. Jeremiah preached against Baal",
          "right": ""
        }
      ],
      "source_card": {
        "id": 13,
        "items": [
          "1. Spiritual Gifts",
          "2. Thanksgiving",
          "3. The Creation",
          "4. Altars destroyed by Gideon",
          "5. Jeremiah preached against Baal"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 14,
    "front_text": "1. Hebrews",
    "back_text": "",
    "metadata": {
      "id": 14,
      "contentItemId": "game-bible-draw",
      "sortOrder": 14,
      "pairs": [
        {
          "left": "1. Hebrews",
          "right": ""
        },
        {
          "left": "2. Tormented with fire",
          "right": ""
        },
        {
          "left": "3. Earthquake",
          "right": ""
        },
        {
          "left": "4. Armageddon",
          "right": ""
        },
        {
          "left": "5. Marks in the forehead",
          "right": ""
        }
      ],
      "source_card": {
        "id": 14,
        "items": [
          "1. Hebrews",
          "2. Tormented with fire",
          "3. Earthquake",
          "4. Armageddon",
          "5. Marks in the forehead"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 15,
    "front_text": "1. Walking and Leaping",
    "back_text": "",
    "metadata": {
      "id": 15,
      "contentItemId": "game-bible-draw",
      "sortOrder": 15,
      "pairs": [
        {
          "left": "1. Walking and Leaping",
          "right": ""
        },
        {
          "left": "2. Wilderness",
          "right": ""
        },
        {
          "left": "3. Command His Angels",
          "right": ""
        },
        {
          "left": "4. Worship",
          "right": ""
        },
        {
          "left": "5. Satan",
          "right": ""
        }
      ],
      "source_card": {
        "id": 15,
        "items": [
          "1. Walking and Leaping",
          "2. Wilderness",
          "3. Command His Angels",
          "4. Worship",
          "5. Satan"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 16,
    "front_text": "1. \"I will never leave thee nor forsake thee\"",
    "back_text": "",
    "metadata": {
      "id": 16,
      "contentItemId": "game-bible-draw",
      "sortOrder": 16,
      "pairs": [
        {
          "left": "1. \"I will never leave thee nor forsake thee\"",
          "right": ""
        },
        {
          "left": "2. Marriage",
          "right": ""
        },
        {
          "left": "3. Prayer and Fasting",
          "right": ""
        },
        {
          "left": "4. Jesus teaching in temple",
          "right": ""
        },
        {
          "left": "5. Children of Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 16,
        "items": [
          "1. \"I will never leave thee nor forsake thee\"",
          "2. Marriage",
          "3. Prayer and Fasting",
          "4. Jesus teaching in temple",
          "5. Children of Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 17,
    "front_text": "1. Serpent",
    "back_text": "",
    "metadata": {
      "id": 17,
      "contentItemId": "game-bible-draw",
      "sortOrder": 17,
      "pairs": [
        {
          "left": "1. Serpent",
          "right": ""
        },
        {
          "left": "2. Vineyard",
          "right": ""
        },
        {
          "left": "3. Slaves",
          "right": ""
        },
        {
          "left": "4. Scriptures",
          "right": ""
        },
        {
          "left": "5. Evangelist",
          "right": ""
        }
      ],
      "source_card": {
        "id": 17,
        "items": [
          "1. Serpent",
          "2. Vineyard",
          "3. Slaves",
          "4. Scriptures",
          "5. Evangelist"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 18,
    "front_text": "1. Masters",
    "back_text": "",
    "metadata": {
      "id": 18,
      "contentItemId": "game-bible-draw",
      "sortOrder": 18,
      "pairs": [
        {
          "left": "1. Masters",
          "right": ""
        },
        {
          "left": "2. Humbleness",
          "right": ""
        },
        {
          "left": "3. Persecution",
          "right": ""
        },
        {
          "left": "4. Tribulation",
          "right": ""
        },
        {
          "left": "5. Everlasting Life",
          "right": ""
        }
      ],
      "source_card": {
        "id": 18,
        "items": [
          "1. Masters",
          "2. Humbleness",
          "3. Persecution",
          "4. Tribulation",
          "5. Everlasting Life"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 19,
    "front_text": "1. Paul's shipwreck",
    "back_text": "",
    "metadata": {
      "id": 19,
      "contentItemId": "game-bible-draw",
      "sortOrder": 19,
      "pairs": [
        {
          "left": "1. Paul's shipwreck",
          "right": ""
        },
        {
          "left": "2. Mountain-moving faith",
          "right": ""
        },
        {
          "left": "3. The shepherds",
          "right": ""
        },
        {
          "left": "4. Burning bush",
          "right": ""
        },
        {
          "left": "5. Chariots of fire",
          "right": ""
        }
      ],
      "source_card": {
        "id": 19,
        "items": [
          "1. Paul's shipwreck",
          "2. Mountain-moving faith",
          "3. The shepherds",
          "4. Burning bush",
          "5. Chariots of fire"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 20,
    "front_text": "1. Physician",
    "back_text": "",
    "metadata": {
      "id": 20,
      "contentItemId": "game-bible-draw",
      "sortOrder": 20,
      "pairs": [
        {
          "left": "1. Physician",
          "right": ""
        },
        {
          "left": "2. Horseman",
          "right": ""
        },
        {
          "left": "3. Deputy",
          "right": ""
        },
        {
          "left": "4. Musician",
          "right": ""
        },
        {
          "left": "5. Baker",
          "right": ""
        }
      ],
      "source_card": {
        "id": 20,
        "items": [
          "1. Physician",
          "2. Horseman",
          "3. Deputy",
          "4. Musician",
          "5. Baker"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 21,
    "front_text": "1. Potter",
    "back_text": "",
    "metadata": {
      "id": 21,
      "contentItemId": "game-bible-draw",
      "sortOrder": 21,
      "pairs": [
        {
          "left": "1. Potter",
          "right": ""
        },
        {
          "left": "2. Carpenter",
          "right": ""
        },
        {
          "left": "3. Teacher",
          "right": ""
        },
        {
          "left": "4. Beggar",
          "right": ""
        },
        {
          "left": "5. Singer",
          "right": ""
        }
      ],
      "source_card": {
        "id": 21,
        "items": [
          "1. Potter",
          "2. Carpenter",
          "3. Teacher",
          "4. Beggar",
          "5. Singer"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 22,
    "front_text": "1. Fruit of the Spirit",
    "back_text": "",
    "metadata": {
      "id": 22,
      "contentItemId": "game-bible-draw",
      "sortOrder": 22,
      "pairs": [
        {
          "left": "1. Fruit of the Spirit",
          "right": ""
        },
        {
          "left": "2. Adam names the animals",
          "right": ""
        },
        {
          "left": "3. Baptism",
          "right": ""
        },
        {
          "left": "4. Noah's ark",
          "right": ""
        },
        {
          "left": "5. Dead Sea",
          "right": ""
        }
      ],
      "source_card": {
        "id": 22,
        "items": [
          "1. Fruit of the Spirit",
          "2. Adam names the animals",
          "3. Baptism",
          "4. Noah's ark",
          "5. Dead Sea"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 23,
    "front_text": "1. Crucifixion",
    "back_text": "",
    "metadata": {
      "id": 23,
      "contentItemId": "game-bible-draw",
      "sortOrder": 23,
      "pairs": [
        {
          "left": "1. Crucifixion",
          "right": ""
        },
        {
          "left": "2. Lake of Fire",
          "right": ""
        },
        {
          "left": "3. The Lost Sheep",
          "right": ""
        },
        {
          "left": "4. 12 Apostles",
          "right": ""
        },
        {
          "left": "5. 12 tribes of Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 23,
        "items": [
          "1. Crucifixion",
          "2. Lake of Fire",
          "3. The Lost Sheep",
          "4. 12 Apostles",
          "5. 12 tribes of Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 24,
    "front_text": "1. Joseph's colorful coat",
    "back_text": "",
    "metadata": {
      "id": 24,
      "contentItemId": "game-bible-draw",
      "sortOrder": 24,
      "pairs": [
        {
          "left": "1. Joseph's colorful coat",
          "right": ""
        },
        {
          "left": "2. Weeping & Gnashing of Teeth",
          "right": ""
        },
        {
          "left": "3. Love of money",
          "right": ""
        },
        {
          "left": "4. Jesus' return to earth",
          "right": ""
        },
        {
          "left": "5. Daniel in the lion's den",
          "right": ""
        }
      ],
      "source_card": {
        "id": 24,
        "items": [
          "1. Joseph's colorful coat",
          "2. Weeping & Gnashing of Teeth",
          "3. Love of money",
          "4. Jesus' return to earth",
          "5. Daniel in the lion's den"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 25,
    "front_text": "1. Trumpeter",
    "back_text": "",
    "metadata": {
      "id": 25,
      "contentItemId": "game-bible-draw",
      "sortOrder": 25,
      "pairs": [
        {
          "left": "1. Trumpeter",
          "right": ""
        },
        {
          "left": "2. Cook",
          "right": ""
        },
        {
          "left": "3. Fisherman",
          "right": ""
        },
        {
          "left": "4. Driver",
          "right": ""
        },
        {
          "left": "5. Gardener",
          "right": ""
        }
      ],
      "source_card": {
        "id": 25,
        "items": [
          "1. Trumpeter",
          "2. Cook",
          "3. Fisherman",
          "4. Driver",
          "5. Gardener"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 26,
    "front_text": "1. Harp",
    "back_text": "",
    "metadata": {
      "id": 26,
      "contentItemId": "game-bible-draw",
      "sortOrder": 26,
      "pairs": [
        {
          "left": "1. Harp",
          "right": ""
        },
        {
          "left": "2. Trumpet",
          "right": ""
        },
        {
          "left": "3. Pigeons",
          "right": ""
        },
        {
          "left": "4. The Lamb of God",
          "right": ""
        },
        {
          "left": "5. Fishers of Men",
          "right": ""
        }
      ],
      "source_card": {
        "id": 26,
        "items": [
          "1. Harp",
          "2. Trumpet",
          "3. Pigeons",
          "4. The Lamb of God",
          "5. Fishers of Men"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 27,
    "front_text": "1. Rich man suffering in hell",
    "back_text": "",
    "metadata": {
      "id": 27,
      "contentItemId": "game-bible-draw",
      "sortOrder": 27,
      "pairs": [
        {
          "left": "1. Rich man suffering in hell",
          "right": ""
        },
        {
          "left": "2. Spring of Water",
          "right": ""
        },
        {
          "left": "3. Preach the Good News",
          "right": ""
        },
        {
          "left": "4. Heavenly Places",
          "right": ""
        },
        {
          "left": "5. Hosanna",
          "right": ""
        }
      ],
      "source_card": {
        "id": 27,
        "items": [
          "1. Rich man suffering in hell",
          "2. Spring of Water",
          "3. Preach the Good News",
          "4. Heavenly Places",
          "5. Hosanna"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 28,
    "front_text": "1. Give thanks",
    "back_text": "",
    "metadata": {
      "id": 28,
      "contentItemId": "game-bible-draw",
      "sortOrder": 28,
      "pairs": [
        {
          "left": "1. Give thanks",
          "right": ""
        },
        {
          "left": "2. Garden of Eden",
          "right": ""
        },
        {
          "left": "3. Son of Thunder",
          "right": ""
        },
        {
          "left": "4. Red Sea",
          "right": ""
        },
        {
          "left": "5. Bethlehem",
          "right": ""
        }
      ],
      "source_card": {
        "id": 28,
        "items": [
          "1. Give thanks",
          "2. Garden of Eden",
          "3. Son of Thunder",
          "4. Red Sea",
          "5. Bethlehem"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 29,
    "front_text": "1. Black horse",
    "back_text": "",
    "metadata": {
      "id": 29,
      "contentItemId": "game-bible-draw",
      "sortOrder": 29,
      "pairs": [
        {
          "left": "1. Black horse",
          "right": ""
        },
        {
          "left": "2. White robes",
          "right": ""
        },
        {
          "left": "3. Book of Life",
          "right": ""
        },
        {
          "left": "4. Resurrection",
          "right": ""
        },
        {
          "left": "5. Gifts of tongue",
          "right": ""
        }
      ],
      "source_card": {
        "id": 29,
        "items": [
          "1. Black horse",
          "2. White robes",
          "3. Book of Life",
          "4. Resurrection",
          "5. Gifts of tongue"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 30,
    "front_text": "1. Judgment Day",
    "back_text": "",
    "metadata": {
      "id": 30,
      "contentItemId": "game-bible-draw",
      "sortOrder": 30,
      "pairs": [
        {
          "left": "1. Judgment Day",
          "right": ""
        },
        {
          "left": "2. Daniel in the lion's den",
          "right": ""
        },
        {
          "left": "3. Second coming",
          "right": ""
        },
        {
          "left": "4. Discipleship",
          "right": ""
        },
        {
          "left": "5. The Good Samaritan",
          "right": ""
        }
      ],
      "source_card": {
        "id": 30,
        "items": [
          "1. Judgment Day",
          "2. Daniel in the lion's den",
          "3. Second coming",
          "4. Discipleship",
          "5. The Good Samaritan"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 31,
    "front_text": "1. False prophets",
    "back_text": "",
    "metadata": {
      "id": 31,
      "contentItemId": "game-bible-draw",
      "sortOrder": 31,
      "pairs": [
        {
          "left": "1. False prophets",
          "right": ""
        },
        {
          "left": "2. Wicked Men",
          "right": ""
        },
        {
          "left": "3. Denying God's Word",
          "right": ""
        },
        {
          "left": "4. Act of faith",
          "right": ""
        },
        {
          "left": "5. Seed time and harvest",
          "right": ""
        }
      ],
      "source_card": {
        "id": 31,
        "items": [
          "1. False prophets",
          "2. Wicked Men",
          "3. Denying God's Word",
          "4. Act of faith",
          "5. Seed time and harvest"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 32,
    "front_text": "1. Victory over enemies",
    "back_text": "",
    "metadata": {
      "id": 32,
      "contentItemId": "game-bible-draw",
      "sortOrder": 32,
      "pairs": [
        {
          "left": "1. Victory over enemies",
          "right": ""
        },
        {
          "left": "2. Fear of death",
          "right": ""
        },
        {
          "left": "3. Elijah feed by ravens",
          "right": ""
        },
        {
          "left": "4. Miraculous healing",
          "right": ""
        },
        {
          "left": "5. Burnt offering",
          "right": ""
        }
      ],
      "source_card": {
        "id": 32,
        "items": [
          "1. Victory over enemies",
          "2. Fear of death",
          "3. Elijah feed by ravens",
          "4. Miraculous healing",
          "5. Burnt offering"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 33,
    "front_text": "1. Revelation",
    "back_text": "",
    "metadata": {
      "id": 33,
      "contentItemId": "game-bible-draw",
      "sortOrder": 33,
      "pairs": [
        {
          "left": "1. Revelation",
          "right": ""
        },
        {
          "left": "2. Holiness",
          "right": ""
        },
        {
          "left": "3. The Trinity",
          "right": ""
        },
        {
          "left": "4. King Saul and David",
          "right": ""
        },
        {
          "left": "5. Tithes",
          "right": ""
        }
      ],
      "source_card": {
        "id": 33,
        "items": [
          "1. Revelation",
          "2. Holiness",
          "3. The Trinity",
          "4. King Saul and David",
          "5. Tithes"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 34,
    "front_text": "1. Witness",
    "back_text": "",
    "metadata": {
      "id": 34,
      "contentItemId": "game-bible-draw",
      "sortOrder": 34,
      "pairs": [
        {
          "left": "1. Witness",
          "right": ""
        },
        {
          "left": "2. Feast",
          "right": ""
        },
        {
          "left": "3. Pillar of Fire",
          "right": ""
        },
        {
          "left": "4. Pillars of Salt",
          "right": ""
        },
        {
          "left": "5. 10 Lepers",
          "right": ""
        }
      ],
      "source_card": {
        "id": 34,
        "items": [
          "1. Witness",
          "2. Feast",
          "3. Pillar of Fire",
          "4. Pillars of Salt",
          "5. 10 Lepers"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 35,
    "front_text": "1. Judas paid by betraying Jesus",
    "back_text": "",
    "metadata": {
      "id": 35,
      "contentItemId": "game-bible-draw",
      "sortOrder": 35,
      "pairs": [
        {
          "left": "1. Judas paid by betraying Jesus",
          "right": ""
        },
        {
          "left": "2. Black vulture",
          "right": ""
        },
        {
          "left": "3. Gift of tongues",
          "right": ""
        },
        {
          "left": "4. Gift of God",
          "right": ""
        },
        {
          "left": "5. The Day of Judgment",
          "right": ""
        }
      ],
      "source_card": {
        "id": 35,
        "items": [
          "1. Judas paid by betraying Jesus",
          "2. Black vulture",
          "3. Gift of tongues",
          "4. Gift of God",
          "5. The Day of Judgment"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 36,
    "front_text": "1. Traditions",
    "back_text": "",
    "metadata": {
      "id": 36,
      "contentItemId": "game-bible-draw",
      "sortOrder": 36,
      "pairs": [
        {
          "left": "1. Traditions",
          "right": ""
        },
        {
          "left": "2. Charity",
          "right": ""
        },
        {
          "left": "3. Sun stands still",
          "right": ""
        },
        {
          "left": "4. Appearing of the Lord Jesus",
          "right": ""
        },
        {
          "left": "5. Blasphemers",
          "right": ""
        }
      ],
      "source_card": {
        "id": 36,
        "items": [
          "1. Traditions",
          "2. Charity",
          "3. Sun stands still",
          "4. Appearing of the Lord Jesus",
          "5. Blasphemers"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 37,
    "front_text": "1. Andrew the Apostle",
    "back_text": "",
    "metadata": {
      "id": 37,
      "contentItemId": "game-bible-draw",
      "sortOrder": 37,
      "pairs": [
        {
          "left": "1. Andrew the Apostle",
          "right": ""
        },
        {
          "left": "2. The Lion and the bear",
          "right": ""
        },
        {
          "left": "3. Three Thousand Chosen Men",
          "right": ""
        },
        {
          "left": "4. Rejoice",
          "right": ""
        },
        {
          "left": "5. Punishment",
          "right": ""
        }
      ],
      "source_card": {
        "id": 37,
        "items": [
          "1. Andrew the Apostle",
          "2. The Lion and the bear",
          "3. Three Thousand Chosen Men",
          "4. Rejoice",
          "5. Punishment"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 38,
    "front_text": "1. Alpha and Omega",
    "back_text": "",
    "metadata": {
      "id": 38,
      "contentItemId": "game-bible-draw",
      "sortOrder": 38,
      "pairs": [
        {
          "left": "1. Alpha and Omega",
          "right": ""
        },
        {
          "left": "2. Idolaters",
          "right": ""
        },
        {
          "left": "3. Fire",
          "right": ""
        },
        {
          "left": "4. Sorcerers",
          "right": ""
        },
        {
          "left": "5. Gates of Heaven",
          "right": ""
        }
      ],
      "source_card": {
        "id": 38,
        "items": [
          "1. Alpha and Omega",
          "2. Idolaters",
          "3. Fire",
          "4. Sorcerers",
          "5. Gates of Heaven"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 39,
    "front_text": "1. Meat Offering",
    "back_text": "",
    "metadata": {
      "id": 39,
      "contentItemId": "game-bible-draw",
      "sortOrder": 39,
      "pairs": [
        {
          "left": "1. Meat Offering",
          "right": ""
        },
        {
          "left": "2. Prince of the guards",
          "right": ""
        },
        {
          "left": "3. Mighty men",
          "right": ""
        },
        {
          "left": "4. Walk with God",
          "right": ""
        },
        {
          "left": "5. Precious Stone",
          "right": ""
        }
      ],
      "source_card": {
        "id": 39,
        "items": [
          "1. Meat Offering",
          "2. Prince of the guards",
          "3. Mighty men",
          "4. Walk with God",
          "5. Precious Stone"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 40,
    "front_text": "1. Blood of the covenant",
    "back_text": "",
    "metadata": {
      "id": 40,
      "contentItemId": "game-bible-draw",
      "sortOrder": 40,
      "pairs": [
        {
          "left": "1. Blood of the covenant",
          "right": ""
        },
        {
          "left": "2. Drink offering",
          "right": ""
        },
        {
          "left": "3. Voice of Thunder",
          "right": ""
        },
        {
          "left": "4. Cherub",
          "right": ""
        },
        {
          "left": "5. Unleavened Bread",
          "right": ""
        }
      ],
      "source_card": {
        "id": 40,
        "items": [
          "1. Blood of the covenant",
          "2. Drink offering",
          "3. Voice of Thunder",
          "4. Cherub",
          "5. Unleavened Bread"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 41,
    "front_text": "1. Dancer",
    "back_text": "",
    "metadata": {
      "id": 41,
      "contentItemId": "game-bible-draw",
      "sortOrder": 41,
      "pairs": [
        {
          "left": "1. Dancer",
          "right": ""
        },
        {
          "left": "2. King",
          "right": ""
        },
        {
          "left": "3. Maidservant",
          "right": ""
        },
        {
          "left": "4. Tent maker",
          "right": ""
        },
        {
          "left": "5. Military Commander",
          "right": ""
        }
      ],
      "source_card": {
        "id": 41,
        "items": [
          "1. Dancer",
          "2. King",
          "3. Maidservant",
          "4. Tent maker",
          "5. Military Commander"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 42,
    "front_text": "1. Lovers of their own selves",
    "back_text": "",
    "metadata": {
      "id": 42,
      "contentItemId": "game-bible-draw",
      "sortOrder": 42,
      "pairs": [
        {
          "left": "1. Lovers of their own selves",
          "right": ""
        },
        {
          "left": "2. Heaven",
          "right": ""
        },
        {
          "left": "3. Tabernacle",
          "right": ""
        },
        {
          "left": "4. Paths for your Feet",
          "right": ""
        },
        {
          "left": "5. Holiness",
          "right": ""
        }
      ],
      "source_card": {
        "id": 42,
        "items": [
          "1. Lovers of their own selves",
          "2. Heaven",
          "3. Tabernacle",
          "4. Paths for your Feet",
          "5. Holiness"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 43,
    "front_text": "1. Paradise",
    "back_text": "",
    "metadata": {
      "id": 43,
      "contentItemId": "game-bible-draw",
      "sortOrder": 43,
      "pairs": [
        {
          "left": "1. Paradise",
          "right": ""
        },
        {
          "left": "2. Passover",
          "right": ""
        },
        {
          "left": "3. Babylon",
          "right": ""
        },
        {
          "left": "4. Mount of Olives",
          "right": ""
        },
        {
          "left": "5. \"Watch and Pray\"",
          "right": ""
        }
      ],
      "source_card": {
        "id": 43,
        "items": [
          "1. Paradise",
          "2. Passover",
          "3. Babylon",
          "4. Mount of Olives",
          "5. \"Watch and Pray\""
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 44,
    "front_text": "1. The lost sheep",
    "back_text": "",
    "metadata": {
      "id": 44,
      "contentItemId": "game-bible-draw",
      "sortOrder": 44,
      "pairs": [
        {
          "left": "1. The lost sheep",
          "right": ""
        },
        {
          "left": "2. Jesus loves the little children",
          "right": ""
        },
        {
          "left": "3. Peter in Prison",
          "right": ""
        },
        {
          "left": "4. Jacob deceives Esau",
          "right": ""
        },
        {
          "left": "5. Temptation of Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 44,
        "items": [
          "1. The lost sheep",
          "2. Jesus loves the little children",
          "3. Peter in Prison",
          "4. Jacob deceives Esau",
          "5. Temptation of Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 45,
    "front_text": "1. Spy",
    "back_text": "",
    "metadata": {
      "id": 45,
      "contentItemId": "game-bible-draw",
      "sortOrder": 45,
      "pairs": [
        {
          "left": "1. Spy",
          "right": ""
        },
        {
          "left": "2. Preacher",
          "right": ""
        },
        {
          "left": "3. Hunter",
          "right": ""
        },
        {
          "left": "4. Sewer",
          "right": ""
        },
        {
          "left": "5. Shepherd",
          "right": ""
        }
      ],
      "source_card": {
        "id": 45,
        "items": [
          "1. Spy",
          "2. Preacher",
          "3. Hunter",
          "4. Sewer",
          "5. Shepherd"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 46,
    "front_text": "1. Magician",
    "back_text": "",
    "metadata": {
      "id": 46,
      "contentItemId": "game-bible-draw",
      "sortOrder": 46,
      "pairs": [
        {
          "left": "1. Magician",
          "right": ""
        },
        {
          "left": "2. Judge",
          "right": ""
        },
        {
          "left": "3. Queen",
          "right": ""
        },
        {
          "left": "4. Writer",
          "right": ""
        },
        {
          "left": "5. Warrior",
          "right": ""
        }
      ],
      "source_card": {
        "id": 46,
        "items": [
          "1. Magician",
          "2. Judge",
          "3. Queen",
          "4. Writer",
          "5. Warrior"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 47,
    "front_text": "1. Angels of God",
    "back_text": "",
    "metadata": {
      "id": 47,
      "contentItemId": "game-bible-draw",
      "sortOrder": 47,
      "pairs": [
        {
          "left": "1. Angels of God",
          "right": ""
        },
        {
          "left": "2. Honor the Lord",
          "right": ""
        },
        {
          "left": "3. Kingdom of God",
          "right": ""
        },
        {
          "left": "4. Mother's womb",
          "right": ""
        },
        {
          "left": "5. Satan tempted Job",
          "right": ""
        }
      ],
      "source_card": {
        "id": 47,
        "items": [
          "1. Angels of God",
          "2. Honor the Lord",
          "3. Kingdom of God",
          "4. Mother's womb",
          "5. Satan tempted Job"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 48,
    "front_text": "1. \"Follow Me\"",
    "back_text": "",
    "metadata": {
      "id": 48,
      "contentItemId": "game-bible-draw",
      "sortOrder": 48,
      "pairs": [
        {
          "left": "1. \"Follow Me\"",
          "right": ""
        },
        {
          "left": "2. \"For God so loved the world\"",
          "right": ""
        },
        {
          "left": "3. \"Seek and ye shall find\"",
          "right": ""
        },
        {
          "left": "4. Jesus wept.",
          "right": ""
        },
        {
          "left": "5. \"My sheep hear my voice\"",
          "right": ""
        }
      ],
      "source_card": {
        "id": 48,
        "items": [
          "1. \"Follow Me\"",
          "2. \"For God so loved the world\"",
          "3. \"Seek and ye shall find\"",
          "4. Jesus wept.",
          "5. \"My sheep hear my voice\""
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 49,
    "front_text": "1. The Second Coming",
    "back_text": "",
    "metadata": {
      "id": 49,
      "contentItemId": "game-bible-draw",
      "sortOrder": 49,
      "pairs": [
        {
          "left": "1. The Second Coming",
          "right": ""
        },
        {
          "left": "2. Wings like eagles",
          "right": ""
        },
        {
          "left": "3. Clothing of priest",
          "right": ""
        },
        {
          "left": "4. Ark of the Covenant",
          "right": ""
        },
        {
          "left": "5. The Light of the World",
          "right": ""
        }
      ],
      "source_card": {
        "id": 49,
        "items": [
          "1. The Second Coming",
          "2. Wings like eagles",
          "3. Clothing of priest",
          "4. Ark of the Covenant",
          "5. The Light of the World"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-draw",
    "sort_order": 50,
    "front_text": "1. Pharaoh's Dream",
    "back_text": "",
    "metadata": {
      "id": 50,
      "contentItemId": "game-bible-draw",
      "sortOrder": 50,
      "pairs": [
        {
          "left": "1. Pharaoh's Dream",
          "right": ""
        },
        {
          "left": "2. Life Sanctification",
          "right": ""
        },
        {
          "left": "3. Grow in Grace",
          "right": ""
        },
        {
          "left": "4. Water baptism",
          "right": ""
        },
        {
          "left": "5. Everlasting Life",
          "right": ""
        }
      ],
      "source_card": {
        "id": 50,
        "items": [
          "1. Pharaoh's Dream",
          "2. Life Sanctification",
          "3. Grow in Grace",
          "4. Water baptism",
          "5. Everlasting Life"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 1,
    "front_text": "5 Last Words of Jesus",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-1",
      "contentItemId": "game-bible-groups",
      "sortOrder": 1,
      "pairs": [
        {
          "left": "5 Last Words of Jesus",
          "right": ""
        },
        {
          "left": "1. Father, forgive them; for they know not what they do.",
          "right": ""
        },
        {
          "left": "2. My God, my God, why hast thou forsaken me?",
          "right": ""
        },
        {
          "left": "3. I thirst.",
          "right": ""
        },
        {
          "left": "4. It is finished.",
          "right": ""
        },
        {
          "left": "5. Father, into thy hands I commend my spirit.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 1,
        "category": "5 Last Words of Jesus",
        "items": [
          "1. Father, forgive them; for they know not what they do.",
          "2. My God, my God, why hast thou forsaken me?",
          "3. I thirst.",
          "4. It is finished.",
          "5. Father, into thy hands I commend my spirit."
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 2,
    "front_text": "5 N.T. Books — The Gospels",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-2",
      "contentItemId": "game-bible-groups",
      "sortOrder": 2,
      "pairs": [
        {
          "left": "5 N.T. Books — The Gospels",
          "right": ""
        },
        {
          "left": "1. Matthew",
          "right": ""
        },
        {
          "left": "2. Mark",
          "right": ""
        },
        {
          "left": "3. Luke",
          "right": ""
        },
        {
          "left": "4. John",
          "right": ""
        },
        {
          "left": "5. Acts",
          "right": ""
        }
      ],
      "source_card": {
        "id": 2,
        "category": "5 N.T. Books — The Gospels",
        "items": [
          "1. Matthew",
          "2. Mark",
          "3. Luke",
          "4. John",
          "5. Acts"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 3,
    "front_text": "5 Armor of God",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-3",
      "contentItemId": "game-bible-groups",
      "sortOrder": 3,
      "pairs": [
        {
          "left": "5 Armor of God",
          "right": ""
        },
        {
          "left": "1. Belt of Truth",
          "right": ""
        },
        {
          "left": "2. Breastplate of Righteousness",
          "right": ""
        },
        {
          "left": "3. Shield of Faith",
          "right": ""
        },
        {
          "left": "4. Helmet of Salvation",
          "right": ""
        },
        {
          "left": "5. Sword of the Spirit",
          "right": ""
        }
      ],
      "source_card": {
        "id": 3,
        "category": "5 Armor of God",
        "items": [
          "1. Belt of Truth",
          "2. Breastplate of Righteousness",
          "3. Shield of Faith",
          "4. Helmet of Salvation",
          "5. Sword of the Spirit"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 4,
    "front_text": "5 Patriarchs of the O.T.",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-4",
      "contentItemId": "game-bible-groups",
      "sortOrder": 4,
      "pairs": [
        {
          "left": "5 Patriarchs of the O.T.",
          "right": ""
        },
        {
          "left": "1. Abraham",
          "right": ""
        },
        {
          "left": "2. Moses",
          "right": ""
        },
        {
          "left": "3. Isaac",
          "right": ""
        },
        {
          "left": "4. Jacob/Israel",
          "right": ""
        },
        {
          "left": "5. David",
          "right": ""
        }
      ],
      "source_card": {
        "id": 4,
        "category": "5 Patriarchs of the O.T.",
        "items": [
          "1. Abraham",
          "2. Moses",
          "3. Isaac",
          "4. Jacob/Israel",
          "5. David"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 5,
    "front_text": "5 Things Which the Lord Hates (Prov. 6:16-19 NIV)",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-5",
      "contentItemId": "game-bible-groups",
      "sortOrder": 5,
      "pairs": [
        {
          "left": "5 Things Which the Lord Hates (Prov. 6:16-19 NIV)",
          "right": ""
        },
        {
          "left": "1. Haughty eyes",
          "right": ""
        },
        {
          "left": "2. Lying Tongue",
          "right": ""
        },
        {
          "left": "3. Hands That Kill Innocent",
          "right": ""
        },
        {
          "left": "4. Heart That Plots Evil",
          "right": ""
        },
        {
          "left": "5. Feet That Race to Do Wrong",
          "right": ""
        }
      ],
      "source_card": {
        "id": 5,
        "category": "5 Things Which the Lord Hates (Prov. 6:16-19 NIV)",
        "items": [
          "1. Haughty eyes",
          "2. Lying Tongue",
          "3. Hands That Kill Innocent",
          "4. Heart That Plots Evil",
          "5. Feet That Race to Do Wrong"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 6,
    "front_text": "5 Qualities of a Deacon (1 Tim. 3:8-10;12-13 NLT)",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-6",
      "contentItemId": "game-bible-groups",
      "sortOrder": 6,
      "pairs": [
        {
          "left": "5 Qualities of a Deacon (1 Tim. 3:8-10;12-13 NLT)",
          "right": ""
        },
        {
          "left": "1. Well-respected",
          "right": ""
        },
        {
          "left": "2. Has integrity",
          "right": ""
        },
        {
          "left": "3. Not Heavy Drinker",
          "right": ""
        },
        {
          "left": "4. Not Dishonest With Money",
          "right": ""
        },
        {
          "left": "5. Faithful to His Wife",
          "right": ""
        }
      ],
      "source_card": {
        "id": 6,
        "category": "5 Qualities of a Deacon (1 Tim. 3:8-10;12-13 NLT)",
        "items": [
          "1. Well-respected",
          "2. Has integrity",
          "3. Not Heavy Drinker",
          "4. Not Dishonest With Money",
          "5. Faithful to His Wife"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 7,
    "front_text": "5 Crowns When We Get to Heaven",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-7",
      "contentItemId": "game-bible-groups",
      "sortOrder": 7,
      "pairs": [
        {
          "left": "5 Crowns When We Get to Heaven",
          "right": ""
        },
        {
          "left": "1. Incorruptible Crown",
          "right": ""
        },
        {
          "left": "2. Crown of Rejoicing",
          "right": ""
        },
        {
          "left": "3. Crown of Life",
          "right": ""
        },
        {
          "left": "4. Crown of Righteousness",
          "right": ""
        },
        {
          "left": "5. Crown of Glory",
          "right": ""
        }
      ],
      "source_card": {
        "id": 7,
        "category": "5 Crowns When We Get to Heaven",
        "items": [
          "1. Incorruptible Crown",
          "2. Crown of Rejoicing",
          "3. Crown of Life",
          "4. Crown of Righteousness",
          "5. Crown of Glory"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 8,
    "front_text": "5 O.T. Books About the Origin of Jewish Race and Culture",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-8",
      "contentItemId": "game-bible-groups",
      "sortOrder": 8,
      "pairs": [
        {
          "left": "5 O.T. Books About the Origin of Jewish Race and Culture",
          "right": ""
        },
        {
          "left": "1. Genesis",
          "right": ""
        },
        {
          "left": "2. Exodus",
          "right": ""
        },
        {
          "left": "3. Leviticus",
          "right": ""
        },
        {
          "left": "4. Numbers",
          "right": ""
        },
        {
          "left": "5. Deuteronomy",
          "right": ""
        }
      ],
      "source_card": {
        "id": 8,
        "category": "5 O.T. Books About the Origin of Jewish Race and Culture",
        "items": [
          "1. Genesis",
          "2. Exodus",
          "3. Leviticus",
          "4. Numbers",
          "5. Deuteronomy"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 9,
    "front_text": "5 Poetry Books of the O.T.",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-9",
      "contentItemId": "game-bible-groups",
      "sortOrder": 9,
      "pairs": [
        {
          "left": "5 Poetry Books of the O.T.",
          "right": ""
        },
        {
          "left": "1. Job",
          "right": ""
        },
        {
          "left": "2. Psalms",
          "right": ""
        },
        {
          "left": "3. Proverbs",
          "right": ""
        },
        {
          "left": "4. Ecclesiastes",
          "right": ""
        },
        {
          "left": "5. Song of Solomon",
          "right": ""
        }
      ],
      "source_card": {
        "id": 9,
        "category": "5 Poetry Books of the O.T.",
        "items": [
          "1. Job",
          "2. Psalms",
          "3. Proverbs",
          "4. Ecclesiastes",
          "5. Song of Solomon"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 10,
    "front_text": "5 Rivers in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-10",
      "contentItemId": "game-bible-groups",
      "sortOrder": 10,
      "pairs": [
        {
          "left": "5 Rivers in the Bible",
          "right": ""
        },
        {
          "left": "1. Damascus River",
          "right": ""
        },
        {
          "left": "2. Euphrates River",
          "right": ""
        },
        {
          "left": "3. Jordan River",
          "right": ""
        },
        {
          "left": "4. Judah River",
          "right": ""
        },
        {
          "left": "5. Nile River",
          "right": ""
        }
      ],
      "source_card": {
        "id": 10,
        "category": "5 Rivers in the Bible",
        "items": [
          "1. Damascus River",
          "2. Euphrates River",
          "3. Jordan River",
          "4. Judah River",
          "5. Nile River"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 11,
    "front_text": "5 Forms of Money in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-11",
      "contentItemId": "game-bible-groups",
      "sortOrder": 11,
      "pairs": [
        {
          "left": "5 Forms of Money in the Bible",
          "right": ""
        },
        {
          "left": "1. Farthing",
          "right": ""
        },
        {
          "left": "2. Mite",
          "right": ""
        },
        {
          "left": "3. Pound",
          "right": ""
        },
        {
          "left": "4. Shekel",
          "right": ""
        },
        {
          "left": "5. Talent",
          "right": ""
        }
      ],
      "source_card": {
        "id": 11,
        "category": "5 Forms of Money in the Bible",
        "items": [
          "1. Farthing",
          "2. Mite",
          "3. Pound",
          "4. Shekel",
          "5. Talent"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 12,
    "front_text": "5 Miracles in the Old Testament",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-12",
      "contentItemId": "game-bible-groups",
      "sortOrder": 12,
      "pairs": [
        {
          "left": "5 Miracles in the Old Testament",
          "right": ""
        },
        {
          "left": "1. The Burning Bush",
          "right": ""
        },
        {
          "left": "2. The Ten Plagues of Egypt",
          "right": ""
        },
        {
          "left": "3. The Parting of Red Sea",
          "right": ""
        },
        {
          "left": "4. The Fall of Jericho",
          "right": ""
        },
        {
          "left": "5. Joshua Commanding the Sun to Stand Still",
          "right": ""
        }
      ],
      "source_card": {
        "id": 12,
        "category": "5 Miracles in the Old Testament",
        "items": [
          "1. The Burning Bush",
          "2. The Ten Plagues of Egypt",
          "3. The Parting of Red Sea",
          "4. The Fall of Jericho",
          "5. Joshua Commanding the Sun to Stand Still"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 13,
    "front_text": "5 Beatitudes of Christ",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-13",
      "contentItemId": "game-bible-groups",
      "sortOrder": 13,
      "pairs": [
        {
          "left": "5 Beatitudes of Christ",
          "right": ""
        },
        {
          "left": "1. Blessed are those who mourn, for they will be comforted.",
          "right": ""
        },
        {
          "left": "2. Blessed are the meek, for they will inherit the earth.",
          "right": ""
        },
        {
          "left": "3. Blessed are the merciful, for they will be shown mercy.",
          "right": ""
        },
        {
          "left": "4. Blessed are the pure in heart, for they will see God.",
          "right": ""
        },
        {
          "left": "5. Blessed are the peacemakers, for they will be called sons of God.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 13,
        "category": "5 Beatitudes of Christ",
        "items": [
          "1. Blessed are those who mourn, for they will be comforted.",
          "2. Blessed are the meek, for they will inherit the earth.",
          "3. Blessed are the merciful, for they will be shown mercy.",
          "4. Blessed are the pure in heart, for they will see God.",
          "5. Blessed are the peacemakers, for they will be called sons of God."
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 14,
    "front_text": "5 High Priests in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-14",
      "contentItemId": "game-bible-groups",
      "sortOrder": 14,
      "pairs": [
        {
          "left": "5 High Priests in the Bible",
          "right": ""
        },
        {
          "left": "1. Aaron",
          "right": ""
        },
        {
          "left": "2. Eleazar",
          "right": ""
        },
        {
          "left": "3. Eli",
          "right": ""
        },
        {
          "left": "4. Caiphas",
          "right": ""
        },
        {
          "left": "5. Jesus Christ",
          "right": ""
        }
      ],
      "source_card": {
        "id": 14,
        "category": "5 High Priests in the Bible",
        "items": [
          "1. Aaron",
          "2. Eleazar",
          "3. Eli",
          "4. Caiphas",
          "5. Jesus Christ"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 15,
    "front_text": "5 Signs of End Times",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-15",
      "contentItemId": "game-bible-groups",
      "sortOrder": 15,
      "pairs": [
        {
          "left": "5 Signs of End Times",
          "right": ""
        },
        {
          "left": "1. False Teachers",
          "right": ""
        },
        {
          "left": "2. Wars",
          "right": ""
        },
        {
          "left": "3. Famines",
          "right": ""
        },
        {
          "left": "4. Earthquakes",
          "right": ""
        },
        {
          "left": "5. Darkness",
          "right": ""
        }
      ],
      "source_card": {
        "id": 15,
        "category": "5 Signs of End Times",
        "items": [
          "1. False Teachers",
          "2. Wars",
          "3. Famines",
          "4. Earthquakes",
          "5. Darkness"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 16,
    "front_text": "5 Names/Types of Angels in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-16",
      "contentItemId": "game-bible-groups",
      "sortOrder": 16,
      "pairs": [
        {
          "left": "5 Names/Types of Angels in the Bible",
          "right": ""
        },
        {
          "left": "1. Michael",
          "right": ""
        },
        {
          "left": "2. Gabriel",
          "right": ""
        },
        {
          "left": "3. Seraphim",
          "right": ""
        },
        {
          "left": "4. Cherubim",
          "right": ""
        },
        {
          "left": "5. Archangels",
          "right": ""
        }
      ],
      "source_card": {
        "id": 16,
        "category": "5 Names/Types of Angels in the Bible",
        "items": [
          "1. Michael",
          "2. Gabriel",
          "3. Seraphim",
          "4. Cherubim",
          "5. Archangels"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 17,
    "front_text": "5 Fruit of the Spirit",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-17",
      "contentItemId": "game-bible-groups",
      "sortOrder": 17,
      "pairs": [
        {
          "left": "5 Fruit of the Spirit",
          "right": ""
        },
        {
          "left": "1. Faithfulness",
          "right": ""
        },
        {
          "left": "2. Peace",
          "right": ""
        },
        {
          "left": "3. Patience",
          "right": ""
        },
        {
          "left": "4. Kindness",
          "right": ""
        },
        {
          "left": "5. Goodness",
          "right": ""
        }
      ],
      "source_card": {
        "id": 17,
        "category": "5 Fruit of the Spirit",
        "items": [
          "1. Faithfulness",
          "2. Peace",
          "3. Patience",
          "4. Kindness",
          "5. Goodness"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 18,
    "front_text": "10 Influential Leaders in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-18",
      "contentItemId": "game-bible-groups",
      "sortOrder": 18,
      "pairs": [
        {
          "left": "10 Influential Leaders in the Bible",
          "right": ""
        },
        {
          "left": "1. Abraham",
          "right": ""
        },
        {
          "left": "2. Moses",
          "right": ""
        },
        {
          "left": "3. Joshua",
          "right": ""
        },
        {
          "left": "4. David",
          "right": ""
        },
        {
          "left": "5. Solomon",
          "right": ""
        },
        {
          "left": "6. Elijah",
          "right": ""
        },
        {
          "left": "7. Isaiah",
          "right": ""
        },
        {
          "left": "8. Peter",
          "right": ""
        },
        {
          "left": "9. Paul",
          "right": ""
        },
        {
          "left": "10. Jesus Christ",
          "right": ""
        }
      ],
      "source_card": {
        "id": 18,
        "category": "10 Influential Leaders in the Bible",
        "items": [
          "1. Abraham",
          "2. Moses",
          "3. Joshua",
          "4. David",
          "5. Solomon",
          "6. Elijah",
          "7. Isaiah",
          "8. Peter",
          "9. Paul",
          "10. Jesus Christ"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 19,
    "front_text": "10 Weapons in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-19",
      "contentItemId": "game-bible-groups",
      "sortOrder": 19,
      "pairs": [
        {
          "left": "10 Weapons in the Bible",
          "right": ""
        },
        {
          "left": "1. Arrow",
          "right": ""
        },
        {
          "left": "2. Axe",
          "right": ""
        },
        {
          "left": "3. Bow",
          "right": ""
        },
        {
          "left": "4. Dart",
          "right": ""
        },
        {
          "left": "5. Hammer",
          "right": ""
        },
        {
          "left": "6. Knife",
          "right": ""
        },
        {
          "left": "7. Sling",
          "right": ""
        },
        {
          "left": "8. Stones",
          "right": ""
        },
        {
          "left": "9. Sword",
          "right": ""
        },
        {
          "left": "10. Spear",
          "right": ""
        }
      ],
      "source_card": {
        "id": 19,
        "category": "10 Weapons in the Bible",
        "items": [
          "1. Arrow",
          "2. Axe",
          "3. Bow",
          "4. Dart",
          "5. Hammer",
          "6. Knife",
          "7. Sling",
          "8. Stones",
          "9. Sword",
          "10. Spear"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 20,
    "front_text": "10 Plagues on Egypt",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-20",
      "contentItemId": "game-bible-groups",
      "sortOrder": 20,
      "pairs": [
        {
          "left": "10 Plagues on Egypt",
          "right": ""
        },
        {
          "left": "1. Water Turned to Blood",
          "right": ""
        },
        {
          "left": "2. Frogs",
          "right": ""
        },
        {
          "left": "3. Lice",
          "right": ""
        },
        {
          "left": "4. Flies",
          "right": ""
        },
        {
          "left": "5. Livestock Death",
          "right": ""
        },
        {
          "left": "6. Boils",
          "right": ""
        },
        {
          "left": "7. Thunder and Hail",
          "right": ""
        },
        {
          "left": "8. Locusts",
          "right": ""
        },
        {
          "left": "9. Darkness",
          "right": ""
        },
        {
          "left": "10. Death of Firstborn",
          "right": ""
        }
      ],
      "source_card": {
        "id": 20,
        "category": "10 Plagues on Egypt",
        "items": [
          "1. Water Turned to Blood",
          "2. Frogs",
          "3. Lice",
          "4. Flies",
          "5. Livestock Death",
          "6. Boils",
          "7. Thunder and Hail",
          "8. Locusts",
          "9. Darkness",
          "10. Death of Firstborn"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 21,
    "front_text": "10 Qualities of an Overseer/Elder (1 Tim 3:2-10 NLT)",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-21",
      "contentItemId": "game-bible-groups",
      "sortOrder": 21,
      "pairs": [
        {
          "left": "10 Qualities of an Overseer/Elder (1 Tim 3:2-10 NLT)",
          "right": ""
        },
        {
          "left": "1. Faithful to His Wife",
          "right": ""
        },
        {
          "left": "2. Self-controlled",
          "right": ""
        },
        {
          "left": "3. With Good Reputation",
          "right": ""
        },
        {
          "left": "4. Hospitable (Enjoys having guests in the home)",
          "right": ""
        },
        {
          "left": "5. Able to Teach",
          "right": ""
        },
        {
          "left": "6. Not Heavy Drinker",
          "right": ""
        },
        {
          "left": "7. Not Violent",
          "right": ""
        },
        {
          "left": "8. Not Lover of Money",
          "right": ""
        },
        {
          "left": "9. Must Manage His Own Family Well",
          "right": ""
        },
        {
          "left": "10. Must Not Be a New Believer",
          "right": ""
        }
      ],
      "source_card": {
        "id": 21,
        "category": "10 Qualities of an Overseer/Elder (1 Tim 3:2-10 NLT)",
        "items": [
          "1. Faithful to His Wife",
          "2. Self-controlled",
          "3. With Good Reputation",
          "4. Hospitable (Enjoys having guests in the home)",
          "5. Able to Teach",
          "6. Not Heavy Drinker",
          "7. Not Violent",
          "8. Not Lover of Money",
          "9. Must Manage His Own Family Well",
          "10. Must Not Be a New Believer"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 22,
    "front_text": "10 Things/People Connected with Paul/Saul",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-22",
      "contentItemId": "game-bible-groups",
      "sortOrder": 22,
      "pairs": [
        {
          "left": "10 Things/People Connected with Paul/Saul",
          "right": ""
        },
        {
          "left": "1. Persecutor of Christians",
          "right": ""
        },
        {
          "left": "2. Damascus",
          "right": ""
        },
        {
          "left": "3. Ananias",
          "right": ""
        },
        {
          "left": "4. Pharisee",
          "right": ""
        },
        {
          "left": "5. Benjamite",
          "right": ""
        },
        {
          "left": "6. Timothy",
          "right": ""
        },
        {
          "left": "7. Barnabas",
          "right": ""
        },
        {
          "left": "8. Silas",
          "right": ""
        },
        {
          "left": "9. Tarsus",
          "right": ""
        },
        {
          "left": "10. Titus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 22,
        "category": "10 Things/People Connected with Paul/Saul",
        "items": [
          "1. Persecutor of Christians",
          "2. Damascus",
          "3. Ananias",
          "4. Pharisee",
          "5. Benjamite",
          "6. Timothy",
          "7. Barnabas",
          "8. Silas",
          "9. Tarsus",
          "10. Titus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 23,
    "front_text": "10 Disciples of Jesus Christ",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-23",
      "contentItemId": "game-bible-groups",
      "sortOrder": 23,
      "pairs": [
        {
          "left": "10 Disciples of Jesus Christ",
          "right": ""
        },
        {
          "left": "1. Simon Peter",
          "right": ""
        },
        {
          "left": "2. Andrew",
          "right": ""
        },
        {
          "left": "3. James son of Zebedee",
          "right": ""
        },
        {
          "left": "4. John son of Zebedee",
          "right": ""
        },
        {
          "left": "5. Philip",
          "right": ""
        },
        {
          "left": "6. Thomas",
          "right": ""
        },
        {
          "left": "7. Bartholomew/Nathaniel",
          "right": ""
        },
        {
          "left": "8. Matthew",
          "right": ""
        },
        {
          "left": "9. Simon the Zealot",
          "right": ""
        },
        {
          "left": "10. Judas Iscariot",
          "right": ""
        }
      ],
      "source_card": {
        "id": 23,
        "category": "10 Disciples of Jesus Christ",
        "items": [
          "1. Simon Peter",
          "2. Andrew",
          "3. James son of Zebedee",
          "4. John son of Zebedee",
          "5. Philip",
          "6. Thomas",
          "7. Bartholomew/Nathaniel",
          "8. Matthew",
          "9. Simon the Zealot",
          "10. Judas Iscariot"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 24,
    "front_text": "10 Sons of Jacob / Israel",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-24",
      "contentItemId": "game-bible-groups",
      "sortOrder": 24,
      "pairs": [
        {
          "left": "10 Sons of Jacob / Israel",
          "right": ""
        },
        {
          "left": "1. Reuben",
          "right": ""
        },
        {
          "left": "2. Simeon",
          "right": ""
        },
        {
          "left": "3. Levi",
          "right": ""
        },
        {
          "left": "4. Judah",
          "right": ""
        },
        {
          "left": "5. Issachar",
          "right": ""
        },
        {
          "left": "6. Dan",
          "right": ""
        },
        {
          "left": "7. Joseph",
          "right": ""
        },
        {
          "left": "8. Naphtali",
          "right": ""
        },
        {
          "left": "9. Gad",
          "right": ""
        },
        {
          "left": "10. Benjamin",
          "right": ""
        }
      ],
      "source_card": {
        "id": 24,
        "category": "10 Sons of Jacob / Israel",
        "items": [
          "1. Reuben",
          "2. Simeon",
          "3. Levi",
          "4. Judah",
          "5. Issachar",
          "6. Dan",
          "7. Joseph",
          "8. Naphtali",
          "9. Gad",
          "10. Benjamin"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 25,
    "front_text": "20 Well-Known Events in the O.T.",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-25",
      "contentItemId": "game-bible-groups",
      "sortOrder": 25,
      "pairs": [
        {
          "left": "20 Well-Known Events in the O.T.",
          "right": ""
        },
        {
          "left": "1. Creation",
          "right": ""
        },
        {
          "left": "2. Fall of Man",
          "right": ""
        },
        {
          "left": "3. Noah & the Ark",
          "right": ""
        },
        {
          "left": "4. Sodom & Gomorrah",
          "right": ""
        },
        {
          "left": "5. Abraham Sacrificed Isaac",
          "right": ""
        },
        {
          "left": "6. Moses & the Burning Bush",
          "right": ""
        },
        {
          "left": "7. Joseph's Story",
          "right": ""
        },
        {
          "left": "8. Plagues on Egypt",
          "right": ""
        },
        {
          "left": "9. The Parting of the Red Sea",
          "right": ""
        },
        {
          "left": "10. The Ten Commandments",
          "right": ""
        },
        {
          "left": "11. The Battle of Jericho",
          "right": ""
        },
        {
          "left": "12. David and Goliath",
          "right": ""
        },
        {
          "left": "13. David and Bathsheba",
          "right": ""
        },
        {
          "left": "14. Solomon's Wisdom",
          "right": ""
        },
        {
          "left": "15. Samson and Delilah",
          "right": ""
        },
        {
          "left": "16. Elijah vs. the Priests of Baal",
          "right": ""
        },
        {
          "left": "17. The Miracles of Elisha",
          "right": ""
        },
        {
          "left": "18. Daniel in the Lion's Den",
          "right": ""
        },
        {
          "left": "19. Jonah and the Fish",
          "right": ""
        },
        {
          "left": "20. The Building of the Temple",
          "right": ""
        }
      ],
      "source_card": {
        "id": 25,
        "category": "20 Well-Known Events in the O.T.",
        "items": [
          "1. Creation",
          "2. Fall of Man",
          "3. Noah & the Ark",
          "4. Sodom & Gomorrah",
          "5. Abraham Sacrificed Isaac",
          "6. Moses & the Burning Bush",
          "7. Joseph's Story",
          "8. Plagues on Egypt",
          "9. The Parting of the Red Sea",
          "10. The Ten Commandments",
          "11. The Battle of Jericho",
          "12. David and Goliath",
          "13. David and Bathsheba",
          "14. Solomon's Wisdom",
          "15. Samson and Delilah",
          "16. Elijah vs. the Priests of Baal",
          "17. The Miracles of Elisha",
          "18. Daniel in the Lion's Den",
          "19. Jonah and the Fish",
          "20. The Building of the Temple"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 26,
    "front_text": "20 Things/People About the First Christmas",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-26",
      "contentItemId": "game-bible-groups",
      "sortOrder": 26,
      "pairs": [
        {
          "left": "20 Things/People About the First Christmas",
          "right": ""
        },
        {
          "left": "1. Baby Jesus",
          "right": ""
        },
        {
          "left": "2. Immanuel",
          "right": ""
        },
        {
          "left": "3. Holy Spirit",
          "right": ""
        },
        {
          "left": "4. Mary",
          "right": ""
        },
        {
          "left": "5. Joseph",
          "right": ""
        },
        {
          "left": "6. Gabriel",
          "right": ""
        },
        {
          "left": "7. Virgin Birth",
          "right": ""
        },
        {
          "left": "8. Star",
          "right": ""
        },
        {
          "left": "9. Wise Men/Magi",
          "right": ""
        },
        {
          "left": "10. King Herod",
          "right": ""
        },
        {
          "left": "11. Killing of Boys Two Years Old and Under",
          "right": ""
        },
        {
          "left": "12. Escape from Egypt",
          "right": ""
        },
        {
          "left": "13. Micah",
          "right": ""
        },
        {
          "left": "14. Isaiah",
          "right": ""
        },
        {
          "left": "15. Star",
          "right": ""
        },
        {
          "left": "16. Angels",
          "right": ""
        },
        {
          "left": "17. Shepherds",
          "right": ""
        },
        {
          "left": "18. Gold",
          "right": ""
        },
        {
          "left": "19. Myrrh",
          "right": ""
        },
        {
          "left": "20. Frankincense",
          "right": ""
        }
      ],
      "source_card": {
        "id": 26,
        "category": "20 Things/People About the First Christmas",
        "items": [
          "1. Baby Jesus",
          "2. Immanuel",
          "3. Holy Spirit",
          "4. Mary",
          "5. Joseph",
          "6. Gabriel",
          "7. Virgin Birth",
          "8. Star",
          "9. Wise Men/Magi",
          "10. King Herod",
          "11. Killing of Boys Two Years Old and Under",
          "12. Escape from Egypt",
          "13. Micah",
          "14. Isaiah",
          "15. Star",
          "16. Angels",
          "17. Shepherds",
          "18. Gold",
          "19. Myrrh",
          "20. Frankincense"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 27,
    "front_text": "20 Old Testament Books",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-27",
      "contentItemId": "game-bible-groups",
      "sortOrder": 27,
      "pairs": [
        {
          "left": "20 Old Testament Books",
          "right": ""
        },
        {
          "left": "1. Leviticus",
          "right": ""
        },
        {
          "left": "2. Deuteronomy",
          "right": ""
        },
        {
          "left": "3. Judges",
          "right": ""
        },
        {
          "left": "4. 2 Samuel",
          "right": ""
        },
        {
          "left": "5. 2 Chronicles",
          "right": ""
        },
        {
          "left": "6. Ezra",
          "right": ""
        },
        {
          "left": "7. Nehemiah",
          "right": ""
        },
        {
          "left": "8. Ecclesiastes",
          "right": ""
        },
        {
          "left": "9. Song of Solomon",
          "right": ""
        },
        {
          "left": "10. Jeremiah",
          "right": ""
        },
        {
          "left": "11. Lamentations",
          "right": ""
        },
        {
          "left": "12. Ezekiel",
          "right": ""
        },
        {
          "left": "13. Amos",
          "right": ""
        },
        {
          "left": "14. Obadiah",
          "right": ""
        },
        {
          "left": "15. Micah",
          "right": ""
        },
        {
          "left": "16. Nahum",
          "right": ""
        },
        {
          "left": "17. Habakkuk",
          "right": ""
        },
        {
          "left": "18. Zephaniah",
          "right": ""
        },
        {
          "left": "19. Haggai",
          "right": ""
        },
        {
          "left": "20. Zechariah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 27,
        "category": "20 Old Testament Books",
        "items": [
          "1. Leviticus",
          "2. Deuteronomy",
          "3. Judges",
          "4. 2 Samuel",
          "5. 2 Chronicles",
          "6. Ezra",
          "7. Nehemiah",
          "8. Ecclesiastes",
          "9. Song of Solomon",
          "10. Jeremiah",
          "11. Lamentations",
          "12. Ezekiel",
          "13. Amos",
          "14. Obadiah",
          "15. Micah",
          "16. Nahum",
          "17. Habakkuk",
          "18. Zephaniah",
          "19. Haggai",
          "20. Zechariah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 28,
    "front_text": "20 Plants of the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-28",
      "contentItemId": "game-bible-groups",
      "sortOrder": 28,
      "pairs": [
        {
          "left": "20 Plants of the Bible",
          "right": ""
        },
        {
          "left": "1. Almond",
          "right": ""
        },
        {
          "left": "2. Amber",
          "right": ""
        },
        {
          "left": "3. Cedar",
          "right": ""
        },
        {
          "left": "4. Barley",
          "right": ""
        },
        {
          "left": "5. Beans",
          "right": ""
        },
        {
          "left": "6. Oak",
          "right": ""
        },
        {
          "left": "7. Cinnamon",
          "right": ""
        },
        {
          "left": "8. Palm",
          "right": ""
        },
        {
          "left": "9. Cypress",
          "right": ""
        },
        {
          "left": "10. Ebony",
          "right": ""
        },
        {
          "left": "11. Fig",
          "right": ""
        },
        {
          "left": "12. Hyssop",
          "right": ""
        },
        {
          "left": "13. Grain",
          "right": ""
        },
        {
          "left": "14. Mint",
          "right": ""
        },
        {
          "left": "15. Lily",
          "right": ""
        },
        {
          "left": "16. Pine",
          "right": ""
        },
        {
          "left": "17. Mulberry",
          "right": ""
        },
        {
          "left": "18. Olive",
          "right": ""
        },
        {
          "left": "19. Acacia",
          "right": ""
        },
        {
          "left": "20. Apple",
          "right": ""
        }
      ],
      "source_card": {
        "id": 28,
        "category": "20 Plants of the Bible",
        "items": [
          "1. Almond",
          "2. Amber",
          "3. Cedar",
          "4. Barley",
          "5. Beans",
          "6. Oak",
          "7. Cinnamon",
          "8. Palm",
          "9. Cypress",
          "10. Ebony",
          "11. Fig",
          "12. Hyssop",
          "13. Grain",
          "14. Mint",
          "15. Lily",
          "16. Pine",
          "17. Mulberry",
          "18. Olive",
          "19. Acacia",
          "20. Apple"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 29,
    "front_text": "20 Names for Christ",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-29",
      "contentItemId": "game-bible-groups",
      "sortOrder": 29,
      "pairs": [
        {
          "left": "20 Names for Christ",
          "right": ""
        },
        {
          "left": "1. The True Vine",
          "right": ""
        },
        {
          "left": "2. Bright and Morning Star",
          "right": ""
        },
        {
          "left": "3. The Messiah",
          "right": ""
        },
        {
          "left": "4. Bread of Life",
          "right": ""
        },
        {
          "left": "5. The Alpha and the Omega",
          "right": ""
        },
        {
          "left": "6. Lord of Lords",
          "right": ""
        },
        {
          "left": "7. Emmanuel",
          "right": ""
        },
        {
          "left": "8. Wonderful Counselor",
          "right": ""
        },
        {
          "left": "9. Only Begotten Son",
          "right": ""
        },
        {
          "left": "10. Friend of Sinners",
          "right": ""
        },
        {
          "left": "11. Son of God",
          "right": ""
        },
        {
          "left": "12. Good Shepherd",
          "right": ""
        },
        {
          "left": "13. The Way, the Truth and the Life",
          "right": ""
        },
        {
          "left": "14. Savior of the World",
          "right": ""
        },
        {
          "left": "15. Lily of the Valley",
          "right": ""
        },
        {
          "left": "16. King of Kings",
          "right": ""
        },
        {
          "left": "17. Lamb of God",
          "right": ""
        },
        {
          "left": "18. Light of the World",
          "right": ""
        },
        {
          "left": "19. Prince of Peace",
          "right": ""
        },
        {
          "left": "20. Living Water",
          "right": ""
        }
      ],
      "source_card": {
        "id": 29,
        "category": "20 Names for Christ",
        "items": [
          "1. The True Vine",
          "2. Bright and Morning Star",
          "3. The Messiah",
          "4. Bread of Life",
          "5. The Alpha and the Omega",
          "6. Lord of Lords",
          "7. Emmanuel",
          "8. Wonderful Counselor",
          "9. Only Begotten Son",
          "10. Friend of Sinners",
          "11. Son of God",
          "12. Good Shepherd",
          "13. The Way, the Truth and the Life",
          "14. Savior of the World",
          "15. Lily of the Valley",
          "16. King of Kings",
          "17. Lamb of God",
          "18. Light of the World",
          "19. Prince of Peace",
          "20. Living Water"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 30,
    "front_text": "20 Food in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-30",
      "contentItemId": "game-bible-groups",
      "sortOrder": 30,
      "pairs": [
        {
          "left": "20 Food in the Bible",
          "right": ""
        },
        {
          "left": "1. Barley",
          "right": ""
        },
        {
          "left": "2. Corn",
          "right": ""
        },
        {
          "left": "3. Bread",
          "right": ""
        },
        {
          "left": "4. Cheese",
          "right": ""
        },
        {
          "left": "5. Cinnamon",
          "right": ""
        },
        {
          "left": "6. Corn",
          "right": ""
        },
        {
          "left": "7. Eggs",
          "right": ""
        },
        {
          "left": "8. Fish",
          "right": ""
        },
        {
          "left": "9. Melons",
          "right": ""
        },
        {
          "left": "10. Flour",
          "right": ""
        },
        {
          "left": "11. Grapes",
          "right": ""
        },
        {
          "left": "12. Honey",
          "right": ""
        },
        {
          "left": "13. Lamb",
          "right": ""
        },
        {
          "left": "14. Milk",
          "right": ""
        },
        {
          "left": "15. Mustard",
          "right": ""
        },
        {
          "left": "16. Olives",
          "right": ""
        },
        {
          "left": "17. Raisins",
          "right": ""
        },
        {
          "left": "18. Wheat",
          "right": ""
        },
        {
          "left": "19. Unleavened Bread",
          "right": ""
        },
        {
          "left": "20. Cucumber",
          "right": ""
        }
      ],
      "source_card": {
        "id": 30,
        "category": "20 Food in the Bible",
        "items": [
          "1. Barley",
          "2. Corn",
          "3. Bread",
          "4. Cheese",
          "5. Cinnamon",
          "6. Corn",
          "7. Eggs",
          "8. Fish",
          "9. Melons",
          "10. Flour",
          "11. Grapes",
          "12. Honey",
          "13. Lamb",
          "14. Milk",
          "15. Mustard",
          "16. Olives",
          "17. Raisins",
          "18. Wheat",
          "19. Unleavened Bread",
          "20. Cucumber"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 31,
    "front_text": "10 Kings of the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-31",
      "contentItemId": "game-bible-groups",
      "sortOrder": 31,
      "pairs": [
        {
          "left": "10 Kings of the Bible",
          "right": ""
        },
        {
          "left": "1. Melchizedek",
          "right": ""
        },
        {
          "left": "2. Saul",
          "right": ""
        },
        {
          "left": "3. David",
          "right": ""
        },
        {
          "left": "4. Solomon",
          "right": ""
        },
        {
          "left": "5. Rehoboam",
          "right": ""
        },
        {
          "left": "6. Darius",
          "right": ""
        },
        {
          "left": "7. Nebuchadnezzar",
          "right": ""
        },
        {
          "left": "8. Herod",
          "right": ""
        },
        {
          "left": "9. Agrippa",
          "right": ""
        },
        {
          "left": "10. Jesus Christ",
          "right": ""
        }
      ],
      "source_card": {
        "id": 31,
        "category": "10 Kings of the Bible",
        "items": [
          "1. Melchizedek",
          "2. Saul",
          "3. David",
          "4. Solomon",
          "5. Rehoboam",
          "6. Darius",
          "7. Nebuchadnezzar",
          "8. Herod",
          "9. Agrippa",
          "10. Jesus Christ"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 32,
    "front_text": "10 Things About the Devil",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-32",
      "contentItemId": "game-bible-groups",
      "sortOrder": 32,
      "pairs": [
        {
          "left": "10 Things About the Devil",
          "right": ""
        },
        {
          "left": "1. Liar",
          "right": ""
        },
        {
          "left": "2. Father of Lies",
          "right": ""
        },
        {
          "left": "3. Accuser of the Brothers",
          "right": ""
        },
        {
          "left": "4. A Lion Seeking Whom He May Devour",
          "right": ""
        },
        {
          "left": "5. Lucifer/Satan",
          "right": ""
        },
        {
          "left": "6. Son of the Morning",
          "right": ""
        },
        {
          "left": "7. Of Perfect Beauty",
          "right": ""
        },
        {
          "left": "8. Prince of This World",
          "right": ""
        },
        {
          "left": "9. God of This World",
          "right": ""
        },
        {
          "left": "10. Murderer from the Beginning",
          "right": ""
        }
      ],
      "source_card": {
        "id": 32,
        "category": "10 Things About the Devil",
        "items": [
          "1. Liar",
          "2. Father of Lies",
          "3. Accuser of the Brothers",
          "4. A Lion Seeking Whom He May Devour",
          "5. Lucifer/Satan",
          "6. Son of the Morning",
          "7. Of Perfect Beauty",
          "8. Prince of This World",
          "9. God of This World",
          "10. Murderer from the Beginning"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 33,
    "front_text": "10 Commandments",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-33",
      "contentItemId": "game-bible-groups",
      "sortOrder": 33,
      "pairs": [
        {
          "left": "10 Commandments",
          "right": ""
        },
        {
          "left": "1. Thou shalt have no other gods before me.",
          "right": ""
        },
        {
          "left": "2. Thou shalt not make unto thee any graven image, or any likeness of anything that is in heaven above, or that is in the earth beneath, or that is in the water under the earth.",
          "right": ""
        },
        {
          "left": "3. Thou shalt not take the name of the Lord thy God in vain.",
          "right": ""
        },
        {
          "left": "4. Remember the Sabbath Day to keep it holy.",
          "right": ""
        },
        {
          "left": "5. Honor thy father and thy mother.",
          "right": ""
        },
        {
          "left": "6. Thou shalt not kill.",
          "right": ""
        },
        {
          "left": "7. Thou shalt not commit adultery.",
          "right": ""
        },
        {
          "left": "8. Thou shalt not steal.",
          "right": ""
        },
        {
          "left": "9. Thou shalt not bear false witness against thy neighbor.",
          "right": ""
        },
        {
          "left": "10. Thou shalt not covet thy neighbor's house/wife.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 33,
        "category": "10 Commandments",
        "items": [
          "1. Thou shalt have no other gods before me.",
          "2. Thou shalt not make unto thee any graven image, or any likeness of anything that is in heaven above, or that is in the earth beneath, or that is in the water under the earth.",
          "3. Thou shalt not take the name of the Lord thy God in vain.",
          "4. Remember the Sabbath Day to keep it holy.",
          "5. Honor thy father and thy mother.",
          "6. Thou shalt not kill.",
          "7. Thou shalt not commit adultery.",
          "8. Thou shalt not steal.",
          "9. Thou shalt not bear false witness against thy neighbor.",
          "10. Thou shalt not covet thy neighbor's house/wife."
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 34,
    "front_text": "10 Acts of Sinful Nature (Gal. 5:19-21 NIV)",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-34",
      "contentItemId": "game-bible-groups",
      "sortOrder": 34,
      "pairs": [
        {
          "left": "10 Acts of Sinful Nature (Gal. 5:19-21 NIV)",
          "right": ""
        },
        {
          "left": "1. Sexual Immorality",
          "right": ""
        },
        {
          "left": "2. Idolatry",
          "right": ""
        },
        {
          "left": "3. Sorcery",
          "right": ""
        },
        {
          "left": "4. Quarreling",
          "right": ""
        },
        {
          "left": "5. Jealousy",
          "right": ""
        },
        {
          "left": "6. Anger",
          "right": ""
        },
        {
          "left": "7. Selfish Ambition",
          "right": ""
        },
        {
          "left": "8. Division",
          "right": ""
        },
        {
          "left": "9. Envy",
          "right": ""
        },
        {
          "left": "10. Drunkenness",
          "right": ""
        }
      ],
      "source_card": {
        "id": 34,
        "category": "10 Acts of Sinful Nature (Gal. 5:19-21 NIV)",
        "items": [
          "1. Sexual Immorality",
          "2. Idolatry",
          "3. Sorcery",
          "4. Quarreling",
          "5. Jealousy",
          "6. Anger",
          "7. Selfish Ambition",
          "8. Division",
          "9. Envy",
          "10. Drunkenness"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 35,
    "front_text": "10 Spiritual Gifts",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-35",
      "contentItemId": "game-bible-groups",
      "sortOrder": 35,
      "pairs": [
        {
          "left": "10 Spiritual Gifts",
          "right": ""
        },
        {
          "left": "1. Apostle",
          "right": ""
        },
        {
          "left": "2. Teacher",
          "right": ""
        },
        {
          "left": "3. Prophet",
          "right": ""
        },
        {
          "left": "4. Pastor-Teacher",
          "right": ""
        },
        {
          "left": "5. Miracles",
          "right": ""
        },
        {
          "left": "6. Speaking in Tongues",
          "right": ""
        },
        {
          "left": "7. Interpretation of Tongues",
          "right": ""
        },
        {
          "left": "8. Word of Wisdom",
          "right": ""
        },
        {
          "left": "9. Word of Knowledge",
          "right": ""
        },
        {
          "left": "10. Giving",
          "right": ""
        }
      ],
      "source_card": {
        "id": 35,
        "category": "10 Spiritual Gifts",
        "items": [
          "1. Apostle",
          "2. Teacher",
          "3. Prophet",
          "4. Pastor-Teacher",
          "5. Miracles",
          "6. Speaking in Tongues",
          "7. Interpretation of Tongues",
          "8. Word of Wisdom",
          "9. Word of Knowledge",
          "10. Giving"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 36,
    "front_text": "10 Parables in the N.T.",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-36",
      "contentItemId": "game-bible-groups",
      "sortOrder": 36,
      "pairs": [
        {
          "left": "10 Parables in the N.T.",
          "right": ""
        },
        {
          "left": "1. Prodigal Son",
          "right": ""
        },
        {
          "left": "2. Unmerciful Servant",
          "right": ""
        },
        {
          "left": "3. Lost Sheep",
          "right": ""
        },
        {
          "left": "4. Parable of the Talents",
          "right": ""
        },
        {
          "left": "5. The Rich Man and Lazarus",
          "right": ""
        },
        {
          "left": "6. Lost Coin",
          "right": ""
        },
        {
          "left": "7. Ten Virgins",
          "right": ""
        },
        {
          "left": "8. The Good Samaritan",
          "right": ""
        },
        {
          "left": "9. Parable of the Sower",
          "right": ""
        },
        {
          "left": "10. Pearl of Great Price",
          "right": ""
        }
      ],
      "source_card": {
        "id": 36,
        "category": "10 Parables in the N.T.",
        "items": [
          "1. Prodigal Son",
          "2. Unmerciful Servant",
          "3. Lost Sheep",
          "4. Parable of the Talents",
          "5. The Rich Man and Lazarus",
          "6. Lost Coin",
          "7. Ten Virgins",
          "8. The Good Samaritan",
          "9. Parable of the Sower",
          "10. Pearl of Great Price"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 37,
    "front_text": "10 Insects in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-37",
      "contentItemId": "game-bible-groups",
      "sortOrder": 37,
      "pairs": [
        {
          "left": "10 Insects in the Bible",
          "right": ""
        },
        {
          "left": "1. Ant",
          "right": ""
        },
        {
          "left": "2. Bee",
          "right": ""
        },
        {
          "left": "3. Earthworm",
          "right": ""
        },
        {
          "left": "4. Caterpillar",
          "right": ""
        },
        {
          "left": "5. Flea",
          "right": ""
        },
        {
          "left": "6. Fly",
          "right": ""
        },
        {
          "left": "7. Spider",
          "right": ""
        },
        {
          "left": "8. Lice",
          "right": ""
        },
        {
          "left": "9. Locust",
          "right": ""
        },
        {
          "left": "10. Moth",
          "right": ""
        }
      ],
      "source_card": {
        "id": 37,
        "category": "10 Insects in the Bible",
        "items": [
          "1. Ant",
          "2. Bee",
          "3. Earthworm",
          "4. Caterpillar",
          "5. Flea",
          "6. Fly",
          "7. Spider",
          "8. Lice",
          "9. Locust",
          "10. Moth"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 38,
    "front_text": "10 Minor O.T. Prophets",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-38",
      "contentItemId": "game-bible-groups",
      "sortOrder": 38,
      "pairs": [
        {
          "left": "10 Minor O.T. Prophets",
          "right": ""
        },
        {
          "left": "1. Hosea",
          "right": ""
        },
        {
          "left": "2. Joel",
          "right": ""
        },
        {
          "left": "3. Amos",
          "right": ""
        },
        {
          "left": "4. Obadiah",
          "right": ""
        },
        {
          "left": "5. Jonah",
          "right": ""
        },
        {
          "left": "6. Micah",
          "right": ""
        },
        {
          "left": "7. Habakkuk",
          "right": ""
        },
        {
          "left": "8. Zephaniah",
          "right": ""
        },
        {
          "left": "9. Haggai",
          "right": ""
        },
        {
          "left": "10. Malachi",
          "right": ""
        }
      ],
      "source_card": {
        "id": 38,
        "category": "10 Minor O.T. Prophets",
        "items": [
          "1. Hosea",
          "2. Joel",
          "3. Amos",
          "4. Obadiah",
          "5. Jonah",
          "6. Micah",
          "7. Habakkuk",
          "8. Zephaniah",
          "9. Haggai",
          "10. Malachi"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 39,
    "front_text": "10 Birds in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-39",
      "contentItemId": "game-bible-groups",
      "sortOrder": 39,
      "pairs": [
        {
          "left": "10 Birds in the Bible",
          "right": ""
        },
        {
          "left": "1. Eagle",
          "right": ""
        },
        {
          "left": "2. Vulture",
          "right": ""
        },
        {
          "left": "3. Owl",
          "right": ""
        },
        {
          "left": "4. Hawk",
          "right": ""
        },
        {
          "left": "5. Hen",
          "right": ""
        },
        {
          "left": "6. Heron",
          "right": ""
        },
        {
          "left": "7. Partridge",
          "right": ""
        },
        {
          "left": "8. Dove",
          "right": ""
        },
        {
          "left": "9. Pigeon",
          "right": ""
        },
        {
          "left": "10. Sparrow",
          "right": ""
        }
      ],
      "source_card": {
        "id": 39,
        "category": "10 Birds in the Bible",
        "items": [
          "1. Eagle",
          "2. Vulture",
          "3. Owl",
          "4. Hawk",
          "5. Hen",
          "6. Heron",
          "7. Partridge",
          "8. Dove",
          "9. Pigeon",
          "10. Sparrow"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 40,
    "front_text": "10 Judges in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-40",
      "contentItemId": "game-bible-groups",
      "sortOrder": 40,
      "pairs": [
        {
          "left": "10 Judges in the Bible",
          "right": ""
        },
        {
          "left": "1. Othniel",
          "right": ""
        },
        {
          "left": "2. Ehud",
          "right": ""
        },
        {
          "left": "3. Deborah",
          "right": ""
        },
        {
          "left": "4. Gideon",
          "right": ""
        },
        {
          "left": "5. Abimelech",
          "right": ""
        },
        {
          "left": "6. Tola",
          "right": ""
        },
        {
          "left": "7. Jair",
          "right": ""
        },
        {
          "left": "8. Elon",
          "right": ""
        },
        {
          "left": "9. Deborah",
          "right": ""
        },
        {
          "left": "10. Samson",
          "right": ""
        }
      ],
      "source_card": {
        "id": 40,
        "category": "10 Judges in the Bible",
        "items": [
          "1. Othniel",
          "2. Ehud",
          "3. Deborah",
          "4. Gideon",
          "5. Abimelech",
          "6. Tola",
          "7. Jair",
          "8. Elon",
          "9. Deborah",
          "10. Samson"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 41,
    "front_text": "10 Mountains",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-41",
      "contentItemId": "game-bible-groups",
      "sortOrder": 41,
      "pairs": [
        {
          "left": "10 Mountains",
          "right": ""
        },
        {
          "left": "1. Carmel",
          "right": ""
        },
        {
          "left": "2. Ararat",
          "right": ""
        },
        {
          "left": "3. Sinai/Horeb",
          "right": ""
        },
        {
          "left": "4. Gilboa",
          "right": ""
        },
        {
          "left": "5. Gerizim",
          "right": ""
        },
        {
          "left": "6. Hermon",
          "right": ""
        },
        {
          "left": "7. Zion",
          "right": ""
        },
        {
          "left": "8. Ebal",
          "right": ""
        },
        {
          "left": "9. Moriah",
          "right": ""
        },
        {
          "left": "10. Olives",
          "right": ""
        }
      ],
      "source_card": {
        "id": 41,
        "category": "10 Mountains",
        "items": [
          "1. Carmel",
          "2. Ararat",
          "3. Sinai/Horeb",
          "4. Gilboa",
          "5. Gerizim",
          "6. Hermon",
          "7. Zion",
          "8. Ebal",
          "9. Moriah",
          "10. Olives"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 42,
    "front_text": "20 Occupations",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-42",
      "contentItemId": "game-bible-groups",
      "sortOrder": 42,
      "pairs": [
        {
          "left": "20 Occupations",
          "right": ""
        },
        {
          "left": "1. Judge",
          "right": ""
        },
        {
          "left": "2. Lawyer",
          "right": ""
        },
        {
          "left": "3. Magician",
          "right": ""
        },
        {
          "left": "4. Musician",
          "right": ""
        },
        {
          "left": "5. Potter",
          "right": ""
        },
        {
          "left": "6. Preacher",
          "right": ""
        },
        {
          "left": "7. Priest",
          "right": ""
        },
        {
          "left": "8. Gardener",
          "right": ""
        },
        {
          "left": "9. Farmer",
          "right": ""
        },
        {
          "left": "10. Sailor",
          "right": ""
        },
        {
          "left": "11. Servant",
          "right": ""
        },
        {
          "left": "12. Carpenter",
          "right": ""
        },
        {
          "left": "13. Shepherd",
          "right": ""
        },
        {
          "left": "14. Silversmith",
          "right": ""
        },
        {
          "left": "15. Astrologer",
          "right": ""
        },
        {
          "left": "16. Soldier",
          "right": ""
        },
        {
          "left": "17. Blacksmith",
          "right": ""
        },
        {
          "left": "18. Tax Collector",
          "right": ""
        },
        {
          "left": "19. Cupbearer",
          "right": ""
        },
        {
          "left": "20. Baker",
          "right": ""
        }
      ],
      "source_card": {
        "id": 42,
        "category": "20 Occupations",
        "items": [
          "1. Judge",
          "2. Lawyer",
          "3. Magician",
          "4. Musician",
          "5. Potter",
          "6. Preacher",
          "7. Priest",
          "8. Gardener",
          "9. Farmer",
          "10. Sailor",
          "11. Servant",
          "12. Carpenter",
          "13. Shepherd",
          "14. Silversmith",
          "15. Astrologer",
          "16. Soldier",
          "17. Blacksmith",
          "18. Tax Collector",
          "19. Cupbearer",
          "20. Baker"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 43,
    "front_text": "20 New Testament Books",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-43",
      "contentItemId": "game-bible-groups",
      "sortOrder": 43,
      "pairs": [
        {
          "left": "20 New Testament Books",
          "right": ""
        },
        {
          "left": "1. Matthew",
          "right": ""
        },
        {
          "left": "2. Mark",
          "right": ""
        },
        {
          "left": "3. Luke",
          "right": ""
        },
        {
          "left": "4. John",
          "right": ""
        },
        {
          "left": "5. Acts",
          "right": ""
        },
        {
          "left": "6. Romans",
          "right": ""
        },
        {
          "left": "7. 1/2 Corinthians",
          "right": ""
        },
        {
          "left": "8. Galatians",
          "right": ""
        },
        {
          "left": "9. Ephesians",
          "right": ""
        },
        {
          "left": "10. Philippians",
          "right": ""
        },
        {
          "left": "11. Colossians",
          "right": ""
        },
        {
          "left": "12. 1/2 Thessalonians",
          "right": ""
        },
        {
          "left": "13. 1/2 Timothy",
          "right": ""
        },
        {
          "left": "14. Titus",
          "right": ""
        },
        {
          "left": "15. Philemon",
          "right": ""
        },
        {
          "left": "16. Hebrews",
          "right": ""
        },
        {
          "left": "17. James",
          "right": ""
        },
        {
          "left": "18. 1/2 Peter",
          "right": ""
        },
        {
          "left": "19. 1/2/3 John",
          "right": ""
        },
        {
          "left": "20. Revelation",
          "right": ""
        }
      ],
      "source_card": {
        "id": 43,
        "category": "20 New Testament Books",
        "items": [
          "1. Matthew",
          "2. Mark",
          "3. Luke",
          "4. John",
          "5. Acts",
          "6. Romans",
          "7. 1/2 Corinthians",
          "8. Galatians",
          "9. Ephesians",
          "10. Philippians",
          "11. Colossians",
          "12. 1/2 Thessalonians",
          "13. 1/2 Timothy",
          "14. Titus",
          "15. Philemon",
          "16. Hebrews",
          "17. James",
          "18. 1/2 Peter",
          "19. 1/2/3 John",
          "20. Revelation"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 44,
    "front_text": "20 Animals in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-44",
      "contentItemId": "game-bible-groups",
      "sortOrder": 44,
      "pairs": [
        {
          "left": "20 Animals in the Bible",
          "right": ""
        },
        {
          "left": "1. Ant",
          "right": ""
        },
        {
          "left": "2. Sheep",
          "right": ""
        },
        {
          "left": "3. Locust",
          "right": ""
        },
        {
          "left": "4. Bird",
          "right": ""
        },
        {
          "left": "5. Raven",
          "right": ""
        },
        {
          "left": "6. Calf",
          "right": ""
        },
        {
          "left": "7. Camel",
          "right": ""
        },
        {
          "left": "8. Serpent",
          "right": ""
        },
        {
          "left": "9. Fox",
          "right": ""
        },
        {
          "left": "10. Sparrow",
          "right": ""
        },
        {
          "left": "11. Lion",
          "right": ""
        },
        {
          "left": "12. Deer",
          "right": ""
        },
        {
          "left": "13. Dove",
          "right": ""
        },
        {
          "left": "14. Eagle",
          "right": ""
        },
        {
          "left": "15. Ram",
          "right": ""
        },
        {
          "left": "16. Fish",
          "right": ""
        },
        {
          "left": "17. Wolf",
          "right": ""
        },
        {
          "left": "18. Ape",
          "right": ""
        },
        {
          "left": "19. Oxen",
          "right": ""
        },
        {
          "left": "20. Pigeon",
          "right": ""
        }
      ],
      "source_card": {
        "id": 44,
        "category": "20 Animals in the Bible",
        "items": [
          "1. Ant",
          "2. Sheep",
          "3. Locust",
          "4. Bird",
          "5. Raven",
          "6. Calf",
          "7. Camel",
          "8. Serpent",
          "9. Fox",
          "10. Sparrow",
          "11. Lion",
          "12. Deer",
          "13. Dove",
          "14. Eagle",
          "15. Ram",
          "16. Fish",
          "17. Wolf",
          "18. Ape",
          "19. Oxen",
          "20. Pigeon"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 45,
    "front_text": "20 Things About Creation",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-45",
      "contentItemId": "game-bible-groups",
      "sortOrder": 45,
      "pairs": [
        {
          "left": "20 Things About Creation",
          "right": ""
        },
        {
          "left": "1. God",
          "right": ""
        },
        {
          "left": "2. Light",
          "right": ""
        },
        {
          "left": "3. Heaven",
          "right": ""
        },
        {
          "left": "4. Earth",
          "right": ""
        },
        {
          "left": "5. Day",
          "right": ""
        },
        {
          "left": "6. Night",
          "right": ""
        },
        {
          "left": "7. Sky",
          "right": ""
        },
        {
          "left": "8. Land",
          "right": ""
        },
        {
          "left": "9. Seas",
          "right": ""
        },
        {
          "left": "10. Plants",
          "right": ""
        },
        {
          "left": "11. Trees",
          "right": ""
        },
        {
          "left": "12. Sun",
          "right": ""
        },
        {
          "left": "13. Moon",
          "right": ""
        },
        {
          "left": "14. Stars",
          "right": ""
        },
        {
          "left": "15. Water Creatures",
          "right": ""
        },
        {
          "left": "16. Birds",
          "right": ""
        },
        {
          "left": "17. Land Animals",
          "right": ""
        },
        {
          "left": "18. Man",
          "right": ""
        },
        {
          "left": "19. Creation in Six Days",
          "right": ""
        },
        {
          "left": "20. God Rested on the 7th Day",
          "right": ""
        }
      ],
      "source_card": {
        "id": 45,
        "category": "20 Things About Creation",
        "items": [
          "1. God",
          "2. Light",
          "3. Heaven",
          "4. Earth",
          "5. Day",
          "6. Night",
          "7. Sky",
          "8. Land",
          "9. Seas",
          "10. Plants",
          "11. Trees",
          "12. Sun",
          "13. Moon",
          "14. Stars",
          "15. Water Creatures",
          "16. Birds",
          "17. Land Animals",
          "18. Man",
          "19. Creation in Six Days",
          "20. God Rested on the 7th Day"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 46,
    "front_text": "20 Musical Instruments in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-46",
      "contentItemId": "game-bible-groups",
      "sortOrder": 46,
      "pairs": [
        {
          "left": "20 Musical Instruments in the Bible",
          "right": ""
        },
        {
          "left": "1. Timbrel",
          "right": ""
        },
        {
          "left": "2. Tambourine",
          "right": ""
        },
        {
          "left": "3. Trumpet",
          "right": ""
        },
        {
          "left": "4. Harp",
          "right": ""
        },
        {
          "left": "5. Oboe",
          "right": ""
        },
        {
          "left": "6. Viols",
          "right": ""
        },
        {
          "left": "7. Psaltery",
          "right": ""
        },
        {
          "left": "8. Lyre",
          "right": ""
        },
        {
          "left": "9. Dulcimer",
          "right": ""
        },
        {
          "left": "10. Horn",
          "right": ""
        },
        {
          "left": "11. Cornet",
          "right": ""
        },
        {
          "left": "12. Flute",
          "right": ""
        },
        {
          "left": "13. Trombone",
          "right": ""
        },
        {
          "left": "14. Cymbals",
          "right": ""
        },
        {
          "left": "15. Bells",
          "right": ""
        },
        {
          "left": "16. Rattle",
          "right": ""
        },
        {
          "left": "17. Triangle",
          "right": ""
        },
        {
          "left": "18. Castanets",
          "right": ""
        },
        {
          "left": "19. Pipe",
          "right": ""
        },
        {
          "left": "20. Zither",
          "right": ""
        }
      ],
      "source_card": {
        "id": 46,
        "category": "20 Musical Instruments in the Bible",
        "items": [
          "1. Timbrel",
          "2. Tambourine",
          "3. Trumpet",
          "4. Harp",
          "5. Oboe",
          "6. Viols",
          "7. Psaltery",
          "8. Lyre",
          "9. Dulcimer",
          "10. Horn",
          "11. Cornet",
          "12. Flute",
          "13. Trombone",
          "14. Cymbals",
          "15. Bells",
          "16. Rattle",
          "17. Triangle",
          "18. Castanets",
          "19. Pipe",
          "20. Zither"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 47,
    "front_text": "20 Women in the Bible",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-47",
      "contentItemId": "game-bible-groups",
      "sortOrder": 47,
      "pairs": [
        {
          "left": "20 Women in the Bible",
          "right": ""
        },
        {
          "left": "1. Eve",
          "right": ""
        },
        {
          "left": "2. Sarah",
          "right": ""
        },
        {
          "left": "3. Bathsheba",
          "right": ""
        },
        {
          "left": "4. Naomi",
          "right": ""
        },
        {
          "left": "5. Delilah",
          "right": ""
        },
        {
          "left": "6. Esther",
          "right": ""
        },
        {
          "left": "7. Ruth",
          "right": ""
        },
        {
          "left": "8. Deborah",
          "right": ""
        },
        {
          "left": "9. Potiphar's Wife",
          "right": ""
        },
        {
          "left": "10. Rebekah",
          "right": ""
        },
        {
          "left": "11. Mary, Mother of Jesus",
          "right": ""
        },
        {
          "left": "12. Elizabeth",
          "right": ""
        },
        {
          "left": "13. Martha",
          "right": ""
        },
        {
          "left": "14. Mary, Sister of Martha",
          "right": ""
        },
        {
          "left": "15. Mary Magdalene",
          "right": ""
        },
        {
          "left": "16. Samaritan Woman",
          "right": ""
        },
        {
          "left": "17. Sapphira",
          "right": ""
        },
        {
          "left": "18. Dorcas",
          "right": ""
        },
        {
          "left": "19. Eunice",
          "right": ""
        },
        {
          "left": "20. Lois",
          "right": ""
        }
      ],
      "source_card": {
        "id": 47,
        "category": "20 Women in the Bible",
        "items": [
          "1. Eve",
          "2. Sarah",
          "3. Bathsheba",
          "4. Naomi",
          "5. Delilah",
          "6. Esther",
          "7. Ruth",
          "8. Deborah",
          "9. Potiphar's Wife",
          "10. Rebekah",
          "11. Mary, Mother of Jesus",
          "12. Elizabeth",
          "13. Martha",
          "14. Mary, Sister of Martha",
          "15. Mary Magdalene",
          "16. Samaritan Woman",
          "17. Sapphira",
          "18. Dorcas",
          "19. Eunice",
          "20. Lois"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 48,
    "front_text": "20 Healing/Miracles by Jesus",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-48",
      "contentItemId": "game-bible-groups",
      "sortOrder": 48,
      "pairs": [
        {
          "left": "20 Healing/Miracles by Jesus",
          "right": ""
        },
        {
          "left": "1. Water Turned into Wine",
          "right": ""
        },
        {
          "left": "2. Man with Leprosy",
          "right": ""
        },
        {
          "left": "3. Roman Centurion's Servant",
          "right": ""
        },
        {
          "left": "4. Peter's Mother-in-Law",
          "right": ""
        },
        {
          "left": "5. Calming of the Storm",
          "right": ""
        },
        {
          "left": "6. Feeding of 5,000",
          "right": ""
        },
        {
          "left": "7. Boy with Epilepsy",
          "right": ""
        },
        {
          "left": "8. Two Blind Men",
          "right": ""
        },
        {
          "left": "9. Man with Evil Spirit",
          "right": ""
        },
        {
          "left": "10. Woman with Bleeding",
          "right": ""
        },
        {
          "left": "11. Deaf-Mute",
          "right": ""
        },
        {
          "left": "12. Crippled Woman",
          "right": ""
        },
        {
          "left": "13. Royal Official's Son",
          "right": ""
        },
        {
          "left": "14. Jairus' Daughter Raised to Life",
          "right": ""
        },
        {
          "left": "15. Lazarus Raised to Life",
          "right": ""
        },
        {
          "left": "16. Fig Tree Withers",
          "right": ""
        },
        {
          "left": "17. Huge Catch of Fish",
          "right": ""
        },
        {
          "left": "18. Walking on Water",
          "right": ""
        },
        {
          "left": "19. Returned Cut Ear of a Soldier",
          "right": ""
        },
        {
          "left": "20. Fish with Coin",
          "right": ""
        }
      ],
      "source_card": {
        "id": 48,
        "category": "20 Healing/Miracles by Jesus",
        "items": [
          "1. Water Turned into Wine",
          "2. Man with Leprosy",
          "3. Roman Centurion's Servant",
          "4. Peter's Mother-in-Law",
          "5. Calming of the Storm",
          "6. Feeding of 5,000",
          "7. Boy with Epilepsy",
          "8. Two Blind Men",
          "9. Man with Evil Spirit",
          "10. Woman with Bleeding",
          "11. Deaf-Mute",
          "12. Crippled Woman",
          "13. Royal Official's Son",
          "14. Jairus' Daughter Raised to Life",
          "15. Lazarus Raised to Life",
          "16. Fig Tree Withers",
          "17. Huge Catch of Fish",
          "18. Walking on Water",
          "19. Returned Cut Ear of a Soldier",
          "20. Fish with Coin"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 49,
    "front_text": "20 Well-Known Events in the N.T.",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-49",
      "contentItemId": "game-bible-groups",
      "sortOrder": 49,
      "pairs": [
        {
          "left": "20 Well-Known Events in the N.T.",
          "right": ""
        },
        {
          "left": "1. Birth of Jesus",
          "right": ""
        },
        {
          "left": "2. Baptism of Jesus",
          "right": ""
        },
        {
          "left": "3. Temptation of Jesus",
          "right": ""
        },
        {
          "left": "4. Miracles by Jesus",
          "right": ""
        },
        {
          "left": "5. Transfiguration",
          "right": ""
        },
        {
          "left": "6. Lazarus Raised from the Dead",
          "right": ""
        },
        {
          "left": "7. Sermon on the Mount",
          "right": ""
        },
        {
          "left": "8. Jesus' Triumphal Entry to Jerusalem",
          "right": ""
        },
        {
          "left": "9. The Last Supper",
          "right": ""
        },
        {
          "left": "10. Jesus Washed Disciples' Feet",
          "right": ""
        },
        {
          "left": "11. Jesus at Gethsemane",
          "right": ""
        },
        {
          "left": "12. Judas Betrays Jesus",
          "right": ""
        },
        {
          "left": "13. Peter's Denial",
          "right": ""
        },
        {
          "left": "14. The Passion of Jesus",
          "right": ""
        },
        {
          "left": "15. The Crucifixion of Jesus",
          "right": ""
        },
        {
          "left": "16. Resurrection of Jesus",
          "right": ""
        },
        {
          "left": "17. Ascension of Jesus",
          "right": ""
        },
        {
          "left": "18. Holy Spirit at Pentecost",
          "right": ""
        },
        {
          "left": "19. Stephen Stoned",
          "right": ""
        },
        {
          "left": "20. Paul's Conversion",
          "right": ""
        }
      ],
      "source_card": {
        "id": 49,
        "category": "20 Well-Known Events in the N.T.",
        "items": [
          "1. Birth of Jesus",
          "2. Baptism of Jesus",
          "3. Temptation of Jesus",
          "4. Miracles by Jesus",
          "5. Transfiguration",
          "6. Lazarus Raised from the Dead",
          "7. Sermon on the Mount",
          "8. Jesus' Triumphal Entry to Jerusalem",
          "9. The Last Supper",
          "10. Jesus Washed Disciples' Feet",
          "11. Jesus at Gethsemane",
          "12. Judas Betrays Jesus",
          "13. Peter's Denial",
          "14. The Passion of Jesus",
          "15. The Crucifixion of Jesus",
          "16. Resurrection of Jesus",
          "17. Ascension of Jesus",
          "18. Holy Spirit at Pentecost",
          "19. Stephen Stoned",
          "20. Paul's Conversion"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-groups",
    "sort_order": 50,
    "front_text": "20 Things/People Connected with David",
    "back_text": "",
    "metadata": {
      "id": "game-bible-groups-card-50",
      "contentItemId": "game-bible-groups",
      "sortOrder": 50,
      "pairs": [
        {
          "left": "20 Things/People Connected with David",
          "right": ""
        },
        {
          "left": "1. Man After God's Own Heart",
          "right": ""
        },
        {
          "left": "2. Jesse",
          "right": ""
        },
        {
          "left": "3. Nathan",
          "right": ""
        },
        {
          "left": "4. Bathsheba",
          "right": ""
        },
        {
          "left": "5. Solomon",
          "right": ""
        },
        {
          "left": "6. Absalom",
          "right": ""
        },
        {
          "left": "7. Goliath",
          "right": ""
        },
        {
          "left": "8. Philistines",
          "right": ""
        },
        {
          "left": "9. Shepherd",
          "right": ""
        },
        {
          "left": "10. Sling/Stones",
          "right": ""
        },
        {
          "left": "11. Saul",
          "right": ""
        },
        {
          "left": "12. Jonathan",
          "right": ""
        },
        {
          "left": "13. Samuel",
          "right": ""
        },
        {
          "left": "14. King",
          "right": ""
        },
        {
          "left": "15. Israel",
          "right": ""
        },
        {
          "left": "16. Adulterer",
          "right": ""
        },
        {
          "left": "17. Murderer",
          "right": ""
        },
        {
          "left": "18. Abigail",
          "right": ""
        },
        {
          "left": "19. Amnon",
          "right": ""
        },
        {
          "left": "20. Tamar",
          "right": ""
        }
      ],
      "source_card": {
        "id": 50,
        "category": "20 Things/People Connected with David",
        "items": [
          "1. Man After God's Own Heart",
          "2. Jesse",
          "3. Nathan",
          "4. Bathsheba",
          "5. Solomon",
          "6. Absalom",
          "7. Goliath",
          "8. Philistines",
          "9. Shepherd",
          "10. Sling/Stones",
          "11. Saul",
          "12. Jonathan",
          "13. Samuel",
          "14. King",
          "15. Israel",
          "16. Adulterer",
          "17. Murderer",
          "18. Abigail",
          "19. Amnon",
          "20. Tamar"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 1,
    "front_text": "“The fear of the Lord is the beginning of knowledge” - 1:7 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-1",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 1,
      "pairs": [
        {
          "left": "“The fear of the Lord is the beginning of knowledge” - 1:7 NIV",
          "right": "",
          "underlined": [
            "fear",
            "Lord",
            "beginning",
            "knowledge"
          ]
        },
        {
          "left": "“Whoever listens to me will live in safety.” - 1:33c NIV",
          "right": "",
          "underlined": [
            "listens",
            "me",
            "live"
          ]
        }
      ],
      "source_card": {
        "id": 1,
        "verses": [
          {
            "verse": "The fear of the Lord is the beginning of knowledge",
            "reference": "1:7 NIV",
            "underlined": [
              "fear",
              "Lord",
              "beginning",
              "knowledge"
            ]
          },
          {
            "verse": "Whoever listens to me will live in safety.",
            "reference": "1:33c NIV",
            "underlined": [
              "listens",
              "me",
              "live"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 2,
    "front_text": "“Yes, beg for knowledge; plead for insight.” - 2:3 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-2",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 2,
      "pairs": [
        {
          "left": "“Yes, beg for knowledge; plead for insight.” - 2:3 TEV",
          "right": "",
          "underlined": [
            "beg",
            "knowledge",
            "plead"
          ]
        },
        {
          "left": "“Trust in the Lord with all your heart.” - 3:5 NLT",
          "right": "",
          "underlined": [
            "Trust",
            "Lord",
            "all",
            "heart"
          ]
        }
      ],
      "source_card": {
        "id": 2,
        "verses": [
          {
            "verse": "Yes, beg for knowledge; plead for insight.",
            "reference": "2:3 TEV",
            "underlined": [
              "beg",
              "knowledge",
              "plead"
            ]
          },
          {
            "verse": "Trust in the Lord with all your heart.",
            "reference": "3:5 NLT",
            "underlined": [
              "Trust",
              "Lord",
              "all",
              "heart"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 3,
    "front_text": "“My fruit is better than fine gold.” - 8:19 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-3",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 3,
      "pairs": [
        {
          "left": "“My fruit is better than fine gold.” - 8:19 NIV",
          "right": "",
          "underlined": [
            "fruit",
            "better",
            "gold"
          ]
        },
        {
          "left": "“The Lord hates everyone who is arrogant.” - 16:5 TEV",
          "right": "",
          "underlined": [
            "Lord",
            "hates",
            "everyone",
            "arrogant"
          ]
        }
      ],
      "source_card": {
        "id": 3,
        "verses": [
          {
            "verse": "My fruit is better than fine gold.",
            "reference": "8:19 NIV",
            "underlined": [
              "fruit",
              "better",
              "gold"
            ]
          },
          {
            "verse": "The Lord hates everyone who is arrogant.",
            "reference": "16:5 TEV",
            "underlined": [
              "Lord",
              "hates",
              "everyone",
              "arrogant"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 4,
    "front_text": "“Whoever trusts in his riches will fall.” - 11:28 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-4",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 4,
      "pairs": [
        {
          "left": "“Whoever trusts in his riches will fall.” - 11:28 NIV",
          "right": "",
          "underlined": [
            "trusts",
            "riches",
            "fall"
          ]
        },
        {
          "left": "“Love covers all wrongs.” - 10:12 NIV",
          "right": "",
          "underlined": [
            "Love",
            "covers",
            "wrongs"
          ]
        }
      ],
      "source_card": {
        "id": 4,
        "verses": [
          {
            "verse": "Whoever trusts in his riches will fall.",
            "reference": "11:28 NIV",
            "underlined": [
              "trusts",
              "riches",
              "fall"
            ]
          },
          {
            "verse": "Love covers all wrongs.",
            "reference": "10:12 NIV",
            "underlined": [
              "Love",
              "covers",
              "wrongs"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 5,
    "front_text": "“A man of understanding holds his tongue.” - 11:12 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-5",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 5,
      "pairs": [
        {
          "left": "“A man of understanding holds his tongue.” - 11:12 NIV",
          "right": "",
          "underlined": [
            "man",
            "holds",
            "tongue"
          ]
        },
        {
          "left": "“For lack of guidance a nation falls.” - 11:14 NIV",
          "right": "",
          "underlined": [
            "guidance",
            "nation",
            "falls"
          ]
        }
      ],
      "source_card": {
        "id": 5,
        "verses": [
          {
            "verse": "A man of understanding holds his tongue.",
            "reference": "11:12 NIV",
            "underlined": [
              "man",
              "holds",
              "tongue"
            ]
          },
          {
            "verse": "For lack of guidance a nation falls.",
            "reference": "11:14 NIV",
            "underlined": [
              "guidance",
              "nation",
              "falls"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 6,
    "front_text": "“Honor the Lord with all your wealth.” - 3:9 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-6",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 6,
      "pairs": [
        {
          "left": "“Honor the Lord with all your wealth.” - 3:9 NLT",
          "right": "",
          "underlined": [
            "Honor",
            "Lord",
            "all",
            "wealth"
          ]
        },
        {
          "left": "“The Lord corrects those He loves.” - 3:12 TEV",
          "right": "",
          "underlined": [
            "Lord",
            "corrects",
            "He",
            "loves"
          ]
        }
      ],
      "source_card": {
        "id": 6,
        "verses": [
          {
            "verse": "Honor the Lord with all your wealth.",
            "reference": "3:9 NLT",
            "underlined": [
              "Honor",
              "Lord",
              "all",
              "wealth"
            ]
          },
          {
            "verse": "The Lord corrects those He loves.",
            "reference": "3:12 TEV",
            "underlined": [
              "Lord",
              "corrects",
              "He",
              "loves"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 7,
    "front_text": "“Do not envy a violent man.” - 3:31 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-7",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 7,
      "pairs": [
        {
          "left": "“Do not envy a violent man.” - 3:31 NIV",
          "right": "",
          "underlined": [
            "Do",
            "not",
            "violent",
            "man"
          ]
        },
        {
          "left": "“Being cheerful keeps you healthy.” - 17:22 NIV",
          "right": "",
          "underlined": [
            "cheerful",
            "you",
            "healthy"
          ]
        }
      ],
      "source_card": {
        "id": 7,
        "verses": [
          {
            "verse": "Do not envy a violent man.",
            "reference": "3:31 NIV",
            "underlined": [
              "Do",
              "not",
              "violent",
              "man"
            ]
          },
          {
            "verse": "Being cheerful keeps you healthy.",
            "reference": "17:22 NIV",
            "underlined": [
              "cheerful",
              "you",
              "healthy"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 8,
    "front_text": "“Those who listen to me will be happy.” - 8:34 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-8",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 8,
      "pairs": [
        {
          "left": "“Those who listen to me will be happy.” - 8:34 TEV",
          "right": "",
          "underlined": [
            "listen",
            "me",
            "happy"
          ]
        },
        {
          "left": "“Whoever finds me finds life.” - 8:35 NLT",
          "right": "",
          "underlined": [
            "Whoever",
            {
              "text": "finds",
              "occurrence": 2
            },
            "life"
          ]
        }
      ],
      "source_card": {
        "id": 8,
        "verses": [
          {
            "verse": "Those who listen to me will be happy.",
            "reference": "8:34 TEV",
            "underlined": [
              "listen",
              "me",
              "happy"
            ]
          },
          {
            "verse": "Whoever finds me finds life.",
            "reference": "8:35 NLT",
            "underlined": [
              "Whoever",
              {
                "text": "finds",
                "occurrence": 2
              },
              "life"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 9,
    "front_text": "“Lazy people irritate their employees.” - 10:26 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-9",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 9,
      "pairs": [
        {
          "left": "“Lazy people irritate their employees.” - 10:26 NLT",
          "right": "",
          "underlined": [
            "Lazy",
            "irritate",
            "employees"
          ]
        },
        {
          "left": "“Good people will receive blessings.” - 10:6 TEV",
          "right": "",
          "underlined": [
            "people",
            "receive",
            "blessings"
          ]
        }
      ],
      "source_card": {
        "id": 9,
        "verses": [
          {
            "verse": "Lazy people irritate their employees.",
            "reference": "10:26 NLT",
            "underlined": [
              "Lazy",
              "irritate",
              "employees"
            ]
          },
          {
            "verse": "Good people will receive blessings.",
            "reference": "10:6 TEV",
            "underlined": [
              "people",
              "receive",
              "blessings"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 10,
    "front_text": "“The fear of the Lord adds length to life.” - 10:27 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-10",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 10,
      "pairs": [
        {
          "left": "“The fear of the Lord adds length to life.” - 10:27 NIV",
          "right": "",
          "underlined": [
            "fear",
            "adds",
            "life"
          ]
        },
        {
          "left": "“Instruct the wise and they will be even wiser.” - 9:9 NLT",
          "right": "",
          "underlined": [
            "Instruct",
            "wise",
            "wiser"
          ]
        }
      ],
      "source_card": {
        "id": 10,
        "verses": [
          {
            "verse": "The fear of the Lord adds length to life.",
            "reference": "10:27 NIV",
            "underlined": [
              "fear",
              "adds",
              "life"
            ]
          },
          {
            "verse": "Instruct the wise and they will be even wiser.",
            "reference": "9:9 NLT",
            "underlined": [
              "Instruct",
              "wise",
              "wiser"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 11,
    "front_text": "“Without wise leadership, a nation falls.” - 11:14 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-11",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 11,
      "pairs": [
        {
          "left": "“Without wise leadership, a nation falls.” - 11:14 NLT",
          "right": "",
          "underlined": [
            "wise leadership",
            "nation falls."
          ]
        },
        {
          "left": "“Wherever you go, He is watching.” - 5:21b TEV",
          "right": "",
          "underlined": [
            "Wherever",
            "He",
            "watching"
          ]
        }
      ],
      "source_card": {
        "id": 11,
        "verses": [
          {
            "verse": "Without wise leadership, a nation falls.",
            "reference": "11:14 NLT",
            "underlined": [
              "wise leadership",
              "nation falls."
            ]
          },
          {
            "verse": "Wherever you go, He is watching.",
            "reference": "5:21b TEV",
            "underlined": [
              "Wherever",
              "He",
              "watching"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 12,
    "front_text": "“Find a wife and you find a good thing.” - 18:22 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-12",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 12,
      "pairs": [
        {
          "left": "“Find a wife and you find a good thing.” - 18:22 TEV",
          "right": "",
          "underlined": [
            "Find",
            "wife",
            "you",
            "find",
            "good",
            "thing"
          ]
        },
        {
          "left": "“To fear the Lord is to hate evil.” - 8:13 NIV",
          "right": "",
          "underlined": [
            "fear",
            "Lord",
            "hate",
            "evil"
          ]
        }
      ],
      "source_card": {
        "id": 12,
        "verses": [
          {
            "verse": "Find a wife and you find a good thing.",
            "reference": "18:22 TEV",
            "underlined": [
              "Find",
              "wife",
              "you",
              "find",
              "good",
              "thing"
            ]
          },
          {
            "verse": "To fear the Lord is to hate evil.",
            "reference": "8:13 NIV",
            "underlined": [
              "fear",
              "Lord",
              "hate",
              "evil"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 13,
    "front_text": "“Correct the wise and they will love you.” - 9:8 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-13",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 13,
      "pairs": [
        {
          "left": "“Correct the wise and they will love you.” - 9:8 NLT",
          "right": "",
          "underlined": [
            "Correct",
            "wise",
            "love"
          ]
        },
        {
          "left": "“Hatred stirs up quarrels.” - 10:12 NLT",
          "right": "",
          "underlined": [
            "Hatred",
            "up",
            "quarrels"
          ]
        }
      ],
      "source_card": {
        "id": 13,
        "verses": [
          {
            "verse": "Correct the wise and they will love you.",
            "reference": "9:8 NLT",
            "underlined": [
              "Correct",
              "wise",
              "love"
            ]
          },
          {
            "verse": "Hatred stirs up quarrels.",
            "reference": "10:12 NLT",
            "underlined": [
              "Hatred",
              "up",
              "quarrels"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 14,
    "front_text": "“Honest people are safe and secure.” - 10:9",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-14",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 14,
      "pairs": [
        {
          "left": "“Honest people are safe and secure.” - 10:9",
          "right": "",
          "underlined": [
            "Honest",
            "people",
            "secure"
          ]
        },
        {
          "left": "“Too much talk leads to sin.” - 10:19 NLT",
          "right": "",
          "underlined": [
            "talk",
            "leads",
            "sin"
          ]
        }
      ],
      "source_card": {
        "id": 14,
        "verses": [
          {
            "verse": "Honest people are safe and secure.",
            "reference": "10:9",
            "underlined": [
              "Honest",
              "people",
              "secure"
            ]
          },
          {
            "verse": "Too much talk leads to sin.",
            "reference": "10:19 NLT",
            "underlined": [
              "talk",
              "leads",
              "sin"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 15,
    "front_text": "“To learn, you must love discipline.” - 12:1 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-15",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 15,
      "pairs": [
        {
          "left": "“To learn, you must love discipline.” - 12:1 NLT",
          "right": "",
          "underlined": [
            "learn",
            "you",
            "love",
            "discipline"
          ]
        },
        {
          "left": "“Help others and you will be helped.” - 11:25 TEV",
          "right": "",
          "underlined": [
            "Help",
            "others",
            "helped"
          ]
        }
      ],
      "source_card": {
        "id": 15,
        "verses": [
          {
            "verse": "To learn, you must love discipline.",
            "reference": "12:1 NLT",
            "underlined": [
              "learn",
              "you",
              "love",
              "discipline"
            ]
          },
          {
            "verse": "Help others and you will be helped.",
            "reference": "11:25 TEV",
            "underlined": [
              "Help",
              "others",
              "helped"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 16,
    "front_text": "“Commit to the Lord whatever you do, and your plans will succeed.” - 16:3 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-16",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 16,
      "pairs": [
        {
          "left": "“Commit to the Lord whatever you do, and your plans will succeed.” - 16:3 NIV",
          "right": "",
          "underlined": [
            "Commit",
            "Lord",
            "do",
            "succeed"
          ]
        },
        {
          "left": "“Happy are those who keep God's law.” - 29:18b TEV",
          "right": "",
          "underlined": [
            "Happy",
            "God's",
            "law"
          ]
        }
      ],
      "source_card": {
        "id": 16,
        "verses": [
          {
            "verse": "Commit to the Lord whatever you do, and your plans will succeed.",
            "reference": "16:3 NIV",
            "underlined": [
              "Commit",
              "Lord",
              "do",
              "succeed"
            ]
          },
          {
            "verse": "Happy are those who keep God's law.",
            "reference": "29:18b TEV",
            "underlined": [
              "Happy",
              "God's",
              "law"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 17,
    "front_text": "“A friend loves at all times.” - 17:17 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-17",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 17,
      "pairs": [
        {
          "left": "“A friend loves at all times.” - 17:17 NIV",
          "right": "",
          "underlined": [
            "friend",
            "loves",
            "times"
          ]
        },
        {
          "left": "“Wiser people remain calm.” - 14:17b TEV",
          "right": "",
          "underlined": [
            "Wiser",
            "people",
            "calm"
          ]
        }
      ],
      "source_card": {
        "id": 17,
        "verses": [
          {
            "verse": "A friend loves at all times.",
            "reference": "17:17 NIV",
            "underlined": [
              "friend",
              "loves",
              "times"
            ]
          },
          {
            "verse": "Wiser people remain calm.",
            "reference": "14:17b TEV",
            "underlined": [
              "Wiser",
              "people",
              "calm"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 18,
    "front_text": "“Good understanding wins favor.” - 13:15 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-18",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 18,
      "pairs": [
        {
          "left": "“Good understanding wins favor.” - 13:15 NIV",
          "right": "",
          "underlined": [
            "understanding",
            "wins",
            "favor"
          ]
        },
        {
          "left": "“A wise person wins friends.” - 11:30 NIV",
          "right": "",
          "underlined": [
            "wise",
            "person",
            "friends"
          ]
        }
      ],
      "source_card": {
        "id": 18,
        "verses": [
          {
            "verse": "Good understanding wins favor.",
            "reference": "13:15 NIV",
            "underlined": [
              "understanding",
              "wins",
              "favor"
            ]
          },
          {
            "verse": "A wise person wins friends.",
            "reference": "11:30 NIV",
            "underlined": [
              "wise",
              "person",
              "friends"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 19,
    "front_text": "“A person's heart is tested by the Lord.” - 17:3 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-19",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 19,
      "pairs": [
        {
          "left": "“A person's heart is tested by the Lord.” - 17:3 TEV",
          "right": "",
          "underlined": [
            "heart",
            "tested",
            "Lord"
          ]
        },
        {
          "left": "“A wise man listens to advice.” - 12:15b NIV",
          "right": "",
          "underlined": [
            "wise",
            "listens",
            "advice"
          ]
        }
      ],
      "source_card": {
        "id": 19,
        "verses": [
          {
            "verse": "A person's heart is tested by the Lord.",
            "reference": "17:3 TEV",
            "underlined": [
              "heart",
              "tested",
              "Lord"
            ]
          },
          {
            "verse": "A wise man listens to advice.",
            "reference": "12:15b NIV",
            "underlined": [
              "wise",
              "listens",
              "advice"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 20,
    "front_text": "“The righteous hates what is false.” - 13:5 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-20",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 20,
      "pairs": [
        {
          "left": "“The righteous hates what is false.” - 13:5 NIV",
          "right": "",
          "underlined": [
            "righteous",
            "hates",
            "false"
          ]
        },
        {
          "left": "“The godliness of good people rescues them.” - 11:6 NIV",
          "right": "",
          "underlined": [
            "good",
            "people",
            "rescues"
          ]
        }
      ],
      "source_card": {
        "id": 20,
        "verses": [
          {
            "verse": "The righteous hates what is false.",
            "reference": "13:5 NIV",
            "underlined": [
              "righteous",
              "hates",
              "false"
            ]
          },
          {
            "verse": "The godliness of good people rescues them.",
            "reference": "11:6 NIV",
            "underlined": [
              "good",
              "people",
              "rescues"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 21,
    "front_text": "“Avoiding a fight is a mark of honor.” - 20:3 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-21",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 21,
      "pairs": [
        {
          "left": "“Avoiding a fight is a mark of honor.” - 20:3 NLT",
          "right": "",
          "underlined": [
            "fight",
            "mark",
            "honor"
          ]
        },
        {
          "left": "“Humility brings honor.” - 29:23b NLT",
          "right": "",
          "underlined": [
            "Humility",
            "brings",
            "honor"
          ]
        }
      ],
      "source_card": {
        "id": 21,
        "verses": [
          {
            "verse": "Avoiding a fight is a mark of honor.",
            "reference": "20:3 NLT",
            "underlined": [
              "fight",
              "mark",
              "honor"
            ]
          },
          {
            "verse": "Humility brings honor.",
            "reference": "29:23b NLT",
            "underlined": [
              "Humility",
              "brings",
              "honor"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 22,
    "front_text": "“Respected people do not tell lies.” - 17:7 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-22",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 22,
      "pairs": [
        {
          "left": "“Respected people do not tell lies.” - 17:7 TEV",
          "right": "",
          "underlined": [
            "Respected",
            "do",
            "not",
            "lies"
          ]
        },
        {
          "left": "“Pride goes before destruction.” - 16:18 NIV",
          "right": "",
          "underlined": [
            "Pride",
            "goes",
            "destruction"
          ]
        }
      ],
      "source_card": {
        "id": 22,
        "verses": [
          {
            "verse": "Respected people do not tell lies.",
            "reference": "17:7 TEV",
            "underlined": [
              "Respected",
              "do",
              "not",
              "lies"
            ]
          },
          {
            "verse": "Pride goes before destruction.",
            "reference": "16:18 NIV",
            "underlined": [
              "Pride",
              "goes",
              "destruction"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 23,
    "front_text": "“A good wife is her husband's pride and joy.” - 12:4 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-23",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 23,
      "pairs": [
        {
          "left": "“A good wife is her husband's pride and joy.” - 12:4 TEV",
          "right": "",
          "underlined": [
            "wife",
            "husband's",
            "pride",
            "joy"
          ]
        },
        {
          "left": "“Listen before you answer.” - 18:13",
          "right": "",
          "underlined": [
            "Listen",
            "you",
            "answer"
          ]
        }
      ],
      "source_card": {
        "id": 23,
        "verses": [
          {
            "verse": "A good wife is her husband's pride and joy.",
            "reference": "12:4 TEV",
            "underlined": [
              "wife",
              "husband's",
              "pride",
              "joy"
            ]
          },
          {
            "verse": "Listen before you answer.",
            "reference": "18:13",
            "underlined": [
              "Listen",
              "you",
              "answer"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 24,
    "front_text": "“Trust in the money and down you go.” - 11:28 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-24",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 24,
      "pairs": [
        {
          "left": "“Trust in the money and down you go.” - 11:28 NLT",
          "right": "",
          "underlined": [
            "Trust",
            "money",
            "down",
            "go"
          ]
        },
        {
          "left": "“Smart people will ignore an insult.” - 12:16 TEV",
          "right": "",
          "underlined": [
            "Smart",
            "people",
            "insult"
          ]
        }
      ],
      "source_card": {
        "id": 24,
        "verses": [
          {
            "verse": "Trust in the money and down you go.",
            "reference": "11:28 NLT",
            "underlined": [
              "Trust",
              "money",
              "down",
              "go"
            ]
          },
          {
            "verse": "Smart people will ignore an insult.",
            "reference": "12:16 TEV",
            "underlined": [
              "Smart",
              "people",
              "insult"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 25,
    "front_text": "“He that is slow to anger is better than the mighty.” - 16:32 KJV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-25",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 25,
      "pairs": [
        {
          "left": "“He that is slow to anger is better than the mighty.” - 16:32 KJV",
          "right": "",
          "underlined": [
            "slow",
            "anger",
            "mighty"
          ]
        },
        {
          "left": "“Pride leads to conflict.” - 13:10 NLT",
          "right": "",
          "underlined": [
            "Pride",
            "leads",
            "conflict"
          ]
        }
      ],
      "source_card": {
        "id": 25,
        "verses": [
          {
            "verse": "He that is slow to anger is better than the mighty.",
            "reference": "16:32 KJV",
            "underlined": [
              "slow",
              "anger",
              "mighty"
            ]
          },
          {
            "verse": "Pride leads to conflict.",
            "reference": "13:10 NLT",
            "underlined": [
              "Pride",
              "leads",
              "conflict"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 26,
    "front_text": "“They that seek the Lord understand all things.” - 28:5b KJV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-26",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 26,
      "pairs": [
        {
          "left": "“They that seek the Lord understand all things.” - 28:5b KJV",
          "right": "",
          "underlined": [
            "seek",
            "Lord",
            "understand"
          ]
        },
        {
          "left": "“A faithful man will be richly blessed.” - 28:20 NIV",
          "right": "",
          "underlined": [
            "faithful",
            "man",
            "blessed"
          ]
        }
      ],
      "source_card": {
        "id": 26,
        "verses": [
          {
            "verse": "They that seek the Lord understand all things.",
            "reference": "28:5b KJV",
            "underlined": [
              "seek",
              "Lord",
              "understand"
            ]
          },
          {
            "verse": "A faithful man will be richly blessed.",
            "reference": "28:20 NIV",
            "underlined": [
              "faithful",
              "man",
              "blessed"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 27,
    "front_text": "“A heart at peace gives life to the body.” - 14:30 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-27",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 27,
      "pairs": [
        {
          "left": "“A heart at peace gives life to the body.” - 14:30 NIV",
          "right": "",
          "underlined": [
            "heart",
            "peace",
            "body"
          ]
        },
        {
          "left": "“He who walks with the wise grows wise.” - 13:20 NIV",
          "right": "",
          "underlined": [
            "He",
            "walks",
            "wise"
          ]
        }
      ],
      "source_card": {
        "id": 27,
        "verses": [
          {
            "verse": "A heart at peace gives life to the body.",
            "reference": "14:30 NIV",
            "underlined": [
              "heart",
              "peace",
              "body"
            ]
          },
          {
            "verse": "He who walks with the wise grows wise.",
            "reference": "13:20 NIV",
            "underlined": [
              "He",
              "walks",
              "wise"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 28,
    "front_text": "“Kind words bring life, but cruel words crush your spirit.” - 15:4 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-28",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 28,
      "pairs": [
        {
          "left": "“Kind words bring life, but cruel words crush your spirit.” - 15:4 TEV",
          "right": "",
          "underlined": [
            "words",
            "life",
            "crush"
          ]
        },
        {
          "left": "“We make our plans but God has the last word.” - 16:1 TEV",
          "right": "",
          "underlined": [
            "We",
            "plans",
            "last"
          ]
        }
      ],
      "source_card": {
        "id": 28,
        "verses": [
          {
            "verse": "Kind words bring life, but cruel words crush your spirit.",
            "reference": "15:4 TEV",
            "underlined": [
              "words",
              "life",
              "crush"
            ]
          },
          {
            "verse": "We make our plans but God has the last word.",
            "reference": "16:1 TEV",
            "underlined": [
              "We",
              "plans",
              "last"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 29,
    "front_text": "“Arrogance will bring you down.” - 23:29a TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-29",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 29,
      "pairs": [
        {
          "left": "“Arrogance will bring you down.” - 23:29a TEV",
          "right": "",
          "underlined": [
            "Arrogance",
            "you",
            "down"
          ]
        },
        {
          "left": "“Every word of God is pure.” - 30:5 KJV",
          "right": "",
          "underlined": [
            "Every",
            "word",
            "pure"
          ]
        }
      ],
      "source_card": {
        "id": 29,
        "verses": [
          {
            "verse": "Arrogance will bring you down.",
            "reference": "23:29a TEV",
            "underlined": [
              "Arrogance",
              "you",
              "down"
            ]
          },
          {
            "verse": "Every word of God is pure.",
            "reference": "30:5 KJV",
            "underlined": [
              "Every",
              "word",
              "pure"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 30,
    "front_text": "“Death and life are in the power of the tongue.” - 18:21 KJV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-30",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 30,
      "pairs": [
        {
          "left": "“Death and life are in the power of the tongue.” - 18:21 KJV",
          "right": "",
          "underlined": [
            "Death",
            "power",
            "tongue"
          ]
        },
        {
          "left": "“He hears the prayers of the righteous.” - 15:29 NLT",
          "right": "",
          "underlined": [
            "He",
            "hears",
            "prayers",
            "righteous"
          ]
        }
      ],
      "source_card": {
        "id": 30,
        "verses": [
          {
            "verse": "Death and life are in the power of the tongue.",
            "reference": "18:21 KJV",
            "underlined": [
              "Death",
              "power",
              "tongue"
            ]
          },
          {
            "verse": "He hears the prayers of the righteous.",
            "reference": "15:29 NLT",
            "underlined": [
              "He",
              "hears",
              "prayers",
              "righteous"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 31,
    "front_text": "“A wise person wins friends.” - 11:30 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-31",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 31,
      "pairs": [
        {
          "left": "“A wise person wins friends.” - 11:30 NLT",
          "right": "",
          "underlined": [
            "wise",
            "wins",
            "friends"
          ]
        },
        {
          "left": "“The Lord is pleased when good people pray.” - 15:7 TEV",
          "right": "",
          "underlined": [
            "Lord",
            "pleased",
            "pray"
          ]
        }
      ],
      "source_card": {
        "id": 31,
        "verses": [
          {
            "verse": "A wise person wins friends.",
            "reference": "11:30 NLT",
            "underlined": [
              "wise",
              "wins",
              "friends"
            ]
          },
          {
            "verse": "The Lord is pleased when good people pray.",
            "reference": "15:7 TEV",
            "underlined": [
              "Lord",
              "pleased",
              "pray"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 32,
    "front_text": "“Let someone praise you, not your own mouth.” - 27:2 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-32",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 32,
      "pairs": [
        {
          "left": "“Let someone praise you, not your own mouth.” - 27:2 NLT",
          "right": "",
          "underlined": [
            "praise",
            "not",
            "mouth"
          ]
        },
        {
          "left": "“Open rebuke is better than secret love.” - 27:5 NLT",
          "right": "",
          "underlined": [
            "Open",
            "better",
            "secret"
          ]
        }
      ],
      "source_card": {
        "id": 32,
        "verses": [
          {
            "verse": "Let someone praise you, not your own mouth.",
            "reference": "27:2 NLT",
            "underlined": [
              "praise",
              "not",
              "mouth"
            ]
          },
          {
            "verse": "Open rebuke is better than secret love.",
            "reference": "27:5 NLT",
            "underlined": [
              "Open",
              "better",
              "secret"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 33,
    "front_text": "“A cheerful heart is good medicine.” - 17:22",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-33",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 33,
      "pairs": [
        {
          "left": "“A cheerful heart is good medicine.” - 17:22",
          "right": "",
          "underlined": [
            "cheerful",
            "heart",
            "medicine"
          ]
        },
        {
          "left": "“Always obey the Lord and you will be happy.” - 28:14 TEV",
          "right": "",
          "underlined": [
            "obey",
            "Lord",
            "happy"
          ]
        }
      ],
      "source_card": {
        "id": 33,
        "verses": [
          {
            "verse": "A cheerful heart is good medicine.",
            "reference": "17:22",
            "underlined": [
              "cheerful",
              "heart",
              "medicine"
            ]
          },
          {
            "verse": "Always obey the Lord and you will be happy.",
            "reference": "28:14 TEV",
            "underlined": [
              "obey",
              "Lord",
              "happy"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 34,
    "front_text": "“A cheerful look brings joy to the heart.” - 15:30 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-34",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 34,
      "pairs": [
        {
          "left": "“A cheerful look brings joy to the heart.” - 15:30 NLT",
          "right": "",
          "underlined": [
            "cheerful",
            "look",
            "joy"
          ]
        },
        {
          "left": "“The Lord approves those who are good.” - 12:2 NLT",
          "right": "",
          "underlined": [
            "Lord",
            "approves",
            "good"
          ]
        }
      ],
      "source_card": {
        "id": 34,
        "verses": [
          {
            "verse": "A cheerful look brings joy to the heart.",
            "reference": "15:30 NLT",
            "underlined": [
              "cheerful",
              "look",
              "joy"
            ]
          },
          {
            "verse": "The Lord approves those who are good.",
            "reference": "12:2 NLT",
            "underlined": [
              "Lord",
              "approves",
              "good"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 35,
    "front_text": "“A gentle answer turns away wrath.” - 15:1 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-35",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 35,
      "pairs": [
        {
          "left": "“A gentle answer turns away wrath.” - 15:1 NIV",
          "right": "",
          "underlined": [
            "answer",
            "turns",
            "wrath"
          ]
        },
        {
          "left": "“The name of the Lord is a strong tower.” - 18:10 NIV",
          "right": "",
          "underlined": [
            "name",
            "Lord",
            "strong",
            "tower"
          ]
        }
      ],
      "source_card": {
        "id": 35,
        "verses": [
          {
            "verse": "A gentle answer turns away wrath.",
            "reference": "15:1 NIV",
            "underlined": [
              "answer",
              "turns",
              "wrath"
            ]
          },
          {
            "verse": "The name of the Lord is a strong tower.",
            "reference": "18:10 NIV",
            "underlined": [
              "name",
              "Lord",
              "strong",
              "tower"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 36,
    "front_text": "“A hot-tempered person starts fight; a cool-tempered person stops them.” - 15:18",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-36",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 36,
      "pairs": [
        {
          "left": "“A hot-tempered person starts fight; a cool-tempered person stops them.” - 15:18",
          "right": "",
          "underlined": [
            "person",
            "fight",
            "stops"
          ]
        },
        {
          "left": "“My teaching will give you a long and prosperous life” - 3:2 TEV",
          "right": "",
          "underlined": [
            "give",
            "long",
            "life"
          ]
        }
      ],
      "source_card": {
        "id": 36,
        "verses": [
          {
            "verse": "A hot-tempered person starts fight; a cool-tempered person stops them.",
            "reference": "15:18",
            "underlined": [
              "person",
              "fight",
              "stops"
            ]
          },
          {
            "verse": "My teaching will give you a long and prosperous life",
            "reference": "3:2 TEV",
            "underlined": [
              "give",
              "long",
              "life"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 37,
    "front_text": "“You will never succeed in life if you try to hide your sins.” - 28:13 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-37",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 37,
      "pairs": [
        {
          "left": "“You will never succeed in life if you try to hide your sins.” - 28:13 TEV",
          "right": "",
          "underlined": [
            "You",
            "succeed",
            "hide"
          ]
        },
        {
          "left": "“The Lord does not let the righteous go hungry.” - 10:3 NIV",
          "right": "",
          "underlined": [
            "Lord",
            "righteous",
            "hungry"
          ]
        }
      ],
      "source_card": {
        "id": 37,
        "verses": [
          {
            "verse": "You will never succeed in life if you try to hide your sins.",
            "reference": "28:13 TEV",
            "underlined": [
              "You",
              "succeed",
              "hide"
            ]
          },
          {
            "verse": "The Lord does not let the righteous go hungry.",
            "reference": "10:3 NIV",
            "underlined": [
              "Lord",
              "righteous",
              "hungry"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 38,
    "front_text": "“The mouth of the righteous is a fountain of life.” - 10:11 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-38",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 38,
      "pairs": [
        {
          "left": "“The mouth of the righteous is a fountain of life.” - 10:11 NIV",
          "right": "",
          "underlined": [
            "mouth",
            "fountain",
            "life"
          ]
        },
        {
          "left": "“To do what is right and just is more acceptable to the Lord than sacrifice.” - 21:3 NIV",
          "right": "",
          "underlined": [
            "right",
            "more",
            "sacrifice"
          ]
        }
      ],
      "source_card": {
        "id": 38,
        "verses": [
          {
            "verse": "The mouth of the righteous is a fountain of life.",
            "reference": "10:11 NIV",
            "underlined": [
              "mouth",
              "fountain",
              "life"
            ]
          },
          {
            "verse": "To do what is right and just is more acceptable to the Lord than sacrifice.",
            "reference": "21:3 NIV",
            "underlined": [
              "right",
              "more",
              "sacrifice"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 39,
    "front_text": "“Give freely and become more wealthy; be stingy and lose everything.” - 11:24 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-39",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 39,
      "pairs": [
        {
          "left": "“Give freely and become more wealthy; be stingy and lose everything.” - 11:24 NLT",
          "right": "",
          "underlined": [
            "Give",
            "wealthy",
            "stingy"
          ]
        },
        {
          "left": "“Your kindness will reward you, but your cruelty will destroy you.” - 11:17 NLT",
          "right": "",
          "underlined": [
            "kindness",
            "you",
            "cruelty"
          ]
        }
      ],
      "source_card": {
        "id": 39,
        "verses": [
          {
            "verse": "Give freely and become more wealthy; be stingy and lose everything.",
            "reference": "11:24 NLT",
            "underlined": [
              "Give",
              "wealthy",
              "stingy"
            ]
          },
          {
            "verse": "Your kindness will reward you, but your cruelty will destroy you.",
            "reference": "11:17 NLT",
            "underlined": [
              "kindness",
              "you",
              "cruelty"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 40,
    "front_text": "“Better to be poor and fear the Lord than to be rich and in trouble.” - 15:16 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-40",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 40,
      "pairs": [
        {
          "left": "“Better to be poor and fear the Lord than to be rich and in trouble.” - 15:16 TEV",
          "right": "",
          "underlined": [
            "Better",
            "fear",
            "rich"
          ]
        },
        {
          "left": "“Kind words are like honey-sweet to the taste and good for the health.” - 16:24 TEV",
          "right": "",
          "underlined": [
            "honey",
            "taste",
            "health"
          ]
        }
      ],
      "source_card": {
        "id": 40,
        "verses": [
          {
            "verse": "Better to be poor and fear the Lord than to be rich and in trouble.",
            "reference": "15:16 TEV",
            "underlined": [
              "Better",
              "fear",
              "rich"
            ]
          },
          {
            "verse": "Kind words are like honey-sweet to the taste and good for the health.",
            "reference": "16:24 TEV",
            "underlined": [
              "honey",
              "taste",
              "health"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 41,
    "front_text": "“If you repay good with evil, you will never get evil out of your house.” - 17:13 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-41",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 41,
      "pairs": [
        {
          "left": "“If you repay good with evil, you will never get evil out of your house.” - 17:13 TEV",
          "right": "",
          "underlined": [
            "evil",
            "never",
            "house"
          ]
        },
        {
          "left": "“Laughter may hide sadness. When happiness is gone, sorrow is always there.” - 14:13 NLT",
          "right": "",
          "underlined": [
            "Laughter",
            "sadness",
            "happiness",
            "sorrow"
          ]
        }
      ],
      "source_card": {
        "id": 41,
        "verses": [
          {
            "verse": "If you repay good with evil, you will never get evil out of your house.",
            "reference": "17:13 TEV",
            "underlined": [
              "evil",
              "never",
              "house"
            ]
          },
          {
            "verse": "Laughter may hide sadness. When happiness is gone, sorrow is always there.",
            "reference": "14:13 NLT",
            "underlined": [
              "Laughter",
              "sadness",
              "happiness",
              "sorrow"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 42,
    "front_text": "“The tongue that brings healing is a tree of life.” - 15:4 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-42",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 42,
      "pairs": [
        {
          "left": "“The tongue that brings healing is a tree of life.” - 15:4 NIV",
          "right": "",
          "underlined": [
            "tongue",
            "healing",
            "tree"
          ]
        },
        {
          "left": "“If you make fun of poor people, you insult the God who made them.” - 17:5 TEV",
          "right": "",
          "underlined": [
            "fun",
            "people",
            "who"
          ]
        }
      ],
      "source_card": {
        "id": 42,
        "verses": [
          {
            "verse": "The tongue that brings healing is a tree of life.",
            "reference": "15:4 NIV",
            "underlined": [
              "tongue",
              "healing",
              "tree"
            ]
          },
          {
            "verse": "If you make fun of poor people, you insult the God who made them.",
            "reference": "17:5 TEV",
            "underlined": [
              "fun",
              "people",
              "who"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 43,
    "front_text": "“When you please the Lord, you can make enemies into friends.” - 16:7 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-43",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 43,
      "pairs": [
        {
          "left": "“When you please the Lord, you can make enemies into friends.” - 16:7 TEV",
          "right": "",
          "underlined": [
            "please",
            "enemies",
            "friends"
          ]
        },
        {
          "left": "“A bowl of vegetable with someone you love is better than steak with someone you hate.” - 15:17 NLT",
          "right": "",
          "underlined": [
            "bowl",
            "someone",
            "steak"
          ]
        }
      ],
      "source_card": {
        "id": 43,
        "verses": [
          {
            "verse": "When you please the Lord, you can make enemies into friends.",
            "reference": "16:7 TEV",
            "underlined": [
              "please",
              "enemies",
              "friends"
            ]
          },
          {
            "verse": "A bowl of vegetable with someone you love is better than steak with someone you hate.",
            "reference": "15:17 NLT",
            "underlined": [
              "bowl",
              "someone",
              "steak"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 44,
    "front_text": "“The heart of the godly thinks carefully before speaking.” - 15:28 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-44",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 44,
      "pairs": [
        {
          "left": "“The heart of the godly thinks carefully before speaking.” - 15:28 NLT",
          "right": "",
          "underlined": [
            "heart",
            "thinks",
            "speaking"
          ]
        },
        {
          "left": "“Go ahead and be lazy, sleep on, but you will be hungry.” - 19:15 TEV",
          "right": "",
          "underlined": [
            "Go",
            "sleep",
            "hungry"
          ]
        }
      ],
      "source_card": {
        "id": 44,
        "verses": [
          {
            "verse": "The heart of the godly thinks carefully before speaking.",
            "reference": "15:28 NLT",
            "underlined": [
              "heart",
              "thinks",
              "speaking"
            ]
          },
          {
            "verse": "Go ahead and be lazy, sleep on, but you will be hungry.",
            "reference": "19:15 TEV",
            "underlined": [
              "Go",
              "sleep",
              "hungry"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 45,
    "front_text": "“Don't try to talk sense to a fool: he can't appreciate it.” - 23:9 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-45",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 45,
      "pairs": [
        {
          "left": "“Don't try to talk sense to a fool: he can't appreciate it.” - 23:9 TEV",
          "right": "",
          "underlined": [
            "Don't",
            "talk",
            "fool"
          ]
        },
        {
          "left": "“A good name is rather to be chosen than great riches.” - 22:1 KJV",
          "right": "",
          "underlined": [
            "name",
            "chosen",
            "riches"
          ]
        }
      ],
      "source_card": {
        "id": 45,
        "verses": [
          {
            "verse": "Don't try to talk sense to a fool: he can't appreciate it.",
            "reference": "23:9 TEV",
            "underlined": [
              "Don't",
              "talk",
              "fool"
            ]
          },
          {
            "verse": "A good name is rather to be chosen than great riches.",
            "reference": "22:1 KJV",
            "underlined": [
              "name",
              "chosen",
              "riches"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 46,
    "front_text": "“Humility and the fear of the Lord brings wealth, honor and life.” - 22:4 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-46",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 46,
      "pairs": [
        {
          "left": "“Humility and the fear of the Lord brings wealth, honor and life.” - 22:4 NIV",
          "right": "",
          "underlined": [
            "Humility",
            "fear",
            "honor"
          ]
        },
        {
          "left": "“Train a child in the way that he should go and he will not depart from it.” - 22:6 NIV",
          "right": "",
          "underlined": [
            "Train",
            "child",
            "way",
            "depart"
          ]
        }
      ],
      "source_card": {
        "id": 46,
        "verses": [
          {
            "verse": "Humility and the fear of the Lord brings wealth, honor and life.",
            "reference": "22:4 NIV",
            "underlined": [
              "Humility",
              "fear",
              "honor"
            ]
          },
          {
            "verse": "Train a child in the way that he should go and he will not depart from it.",
            "reference": "22:6 NIV",
            "underlined": [
              "Train",
              "child",
              "way",
              "depart"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 47,
    "front_text": "“If you are weak in crisis, you are weak indeed.” - 24:24 TEV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-47",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 47,
      "pairs": [
        {
          "left": "“If you are weak in crisis, you are weak indeed.” - 24:24 TEV",
          "right": "",
          "underlined": [
            "weak",
            "crisis",
            {
              "text": "you",
              "occurrence": 2
            }
          ]
        },
        {
          "left": "“Do not boast about tomorrow, for you do not know what a day may bring forth.” - 27:1 NIV",
          "right": "",
          "underlined": [
            "tomorrow",
            "day",
            "forth"
          ]
        }
      ],
      "source_card": {
        "id": 47,
        "verses": [
          {
            "verse": "If you are weak in crisis, you are weak indeed.",
            "reference": "24:24 TEV",
            "underlined": [
              "weak",
              "crisis",
              {
                "text": "you",
                "occurrence": 2
              }
            ]
          },
          {
            "verse": "Do not boast about tomorrow, for you do not know what a day may bring forth.",
            "reference": "27:1 NIV",
            "underlined": [
              "tomorrow",
              "day",
              "forth"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 48,
    "front_text": "“There is surely a future hope for you, and your hope will not be cut off.” - 23:18 NIV",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-48",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 48,
      "pairs": [
        {
          "left": "“There is surely a future hope for you, and your hope will not be cut off.” - 23:18 NIV",
          "right": "",
          "underlined": [
            "future",
            {
              "text": "hope",
              "occurrence": 2
            },
            "cut"
          ]
        },
        {
          "left": "“Punish him with the rod and save his soul from death.” - 23:14 NIV",
          "right": "",
          "underlined": [
            "Punish",
            "rod",
            "soul"
          ]
        }
      ],
      "source_card": {
        "id": 48,
        "verses": [
          {
            "verse": "There is surely a future hope for you, and your hope will not be cut off.",
            "reference": "23:18 NIV",
            "underlined": [
              "future",
              {
                "text": "hope",
                "occurrence": 2
              },
              "cut"
            ]
          },
          {
            "verse": "Punish him with the rod and save his soul from death.",
            "reference": "23:14 NIV",
            "underlined": [
              "Punish",
              "rod",
              "soul"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 49,
    "front_text": "“As a dog returns to his vomit, so a fool repeats his foolishness.” - 26:11 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-49",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 49,
      "pairs": [
        {
          "left": "“As a dog returns to his vomit, so a fool repeats his foolishness.” - 26:11 NLT",
          "right": "",
          "underlined": [
            "vomit",
            "fool",
            "foolishness"
          ]
        },
        {
          "left": "“Watch your tongue and keep your mouth shut and you will stay out of trouble.” - 21:23 NLT",
          "right": "",
          "underlined": [
            "Watch",
            "tongue",
            "shut"
          ]
        }
      ],
      "source_card": {
        "id": 49,
        "verses": [
          {
            "verse": "As a dog returns to his vomit, so a fool repeats his foolishness.",
            "reference": "26:11 NLT",
            "underlined": [
              "vomit",
              "fool",
              "foolishness"
            ]
          },
          {
            "verse": "Watch your tongue and keep your mouth shut and you will stay out of trouble.",
            "reference": "21:23 NLT",
            "underlined": [
              "Watch",
              "tongue",
              "shut"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-proverbs",
    "sort_order": 50,
    "front_text": "“Good planning and hard work lead to prosperity.” - 21:5 NLT",
    "back_text": "",
    "metadata": {
      "id": "game-bible-proverbs-card-50",
      "contentItemId": "game-bible-proverbs",
      "sortOrder": 50,
      "pairs": [
        {
          "left": "“Good planning and hard work lead to prosperity.” - 21:5 NLT",
          "right": "",
          "underlined": [
            "planning",
            "hard",
            "prosperity"
          ]
        },
        {
          "left": "“There is no wisdom, no insight, no plan that can succeed against the Lord.” - 21:30 NIV",
          "right": "",
          "underlined": [
            "wisdom",
            "plan",
            "succeed"
          ]
        }
      ],
      "source_card": {
        "id": 50,
        "verses": [
          {
            "verse": "Good planning and hard work lead to prosperity.",
            "reference": "21:5 NLT",
            "underlined": [
              "planning",
              "hard",
              "prosperity"
            ]
          },
          {
            "verse": "There is no wisdom, no insight, no plan that can succeed against the Lord.",
            "reference": "21:30 NIV",
            "underlined": [
              "wisdom",
              "plan",
              "succeed"
            ]
          }
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 1,
    "front_text": "Aaron - Exodus 4",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-1",
      "contentItemId": "game-bible-question",
      "sortOrder": 1,
      "category": "People",
      "pairs": [
        {
          "left": "Aaron - Exodus 4",
          "right": ""
        },
        {
          "left": "Abel - Genesis 4",
          "right": ""
        },
        {
          "left": "Abraham - Genesis 17",
          "right": ""
        },
        {
          "left": "Adam - Genesis 2",
          "right": ""
        }
      ],
      "source_card": {
        "id": 1,
        "category": "People",
        "items": [
          "Aaron - Exodus 4",
          "Abel - Genesis 4",
          "Abraham - Genesis 17",
          "Adam - Genesis 2"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 2,
    "front_text": "Benjamin - Genesis 35",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-2",
      "contentItemId": "game-bible-question",
      "sortOrder": 2,
      "category": "People",
      "pairs": [
        {
          "left": "Benjamin - Genesis 35",
          "right": ""
        },
        {
          "left": "Boaz - Ruth 2",
          "right": ""
        },
        {
          "left": "Bathsheba - 2 Sam 11-12",
          "right": ""
        },
        {
          "left": "Cain - Genesis 4",
          "right": ""
        }
      ],
      "source_card": {
        "id": 2,
        "category": "People",
        "items": [
          "Benjamin - Genesis 35",
          "Boaz - Ruth 2",
          "Bathsheba - 2 Sam 11-12",
          "Cain - Genesis 4"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 3,
    "front_text": "Caleb - Numbers 14",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-3",
      "contentItemId": "game-bible-question",
      "sortOrder": 3,
      "category": "People",
      "pairs": [
        {
          "left": "Caleb - Numbers 14",
          "right": ""
        },
        {
          "left": "David - 1 Samuel 16",
          "right": ""
        },
        {
          "left": "Delilah - Judges 16",
          "right": ""
        },
        {
          "left": "Elijah - 1 Kings 17",
          "right": ""
        }
      ],
      "source_card": {
        "id": 3,
        "category": "People",
        "items": [
          "Caleb - Numbers 14",
          "David - 1 Samuel 16",
          "Delilah - Judges 16",
          "Elijah - 1 Kings 17"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 4,
    "front_text": "Elizabeth - Luke 1",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-4",
      "contentItemId": "game-bible-question",
      "sortOrder": 4,
      "category": "People",
      "pairs": [
        {
          "left": "Elizabeth - Luke 1",
          "right": ""
        },
        {
          "left": "Emmanuel - Matthew 1:23",
          "right": ""
        },
        {
          "left": "Enoch - Genesis 5",
          "right": ""
        },
        {
          "left": "Esau - Genesis 25",
          "right": ""
        }
      ],
      "source_card": {
        "id": 4,
        "category": "People",
        "items": [
          "Elizabeth - Luke 1",
          "Emmanuel - Matthew 1:23",
          "Enoch - Genesis 5",
          "Esau - Genesis 25"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 5,
    "front_text": "Eve - Genesis 3",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-5",
      "contentItemId": "game-bible-question",
      "sortOrder": 5,
      "category": "People",
      "pairs": [
        {
          "left": "Eve - Genesis 3",
          "right": ""
        },
        {
          "left": "Gabriel - Luke 1",
          "right": ""
        },
        {
          "left": "Goliath - 1 Samuel 17",
          "right": ""
        },
        {
          "left": "Herod - Matthew 2",
          "right": ""
        }
      ],
      "source_card": {
        "id": 5,
        "category": "People",
        "items": [
          "Eve - Genesis 3",
          "Gabriel - Luke 1",
          "Goliath - 1 Samuel 17",
          "Herod - Matthew 2"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 6,
    "front_text": "Isaac - Genesis 21",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-6",
      "contentItemId": "game-bible-question",
      "sortOrder": 6,
      "category": "People",
      "pairs": [
        {
          "left": "Isaac - Genesis 21",
          "right": ""
        },
        {
          "left": "Jacob - Genesis 25",
          "right": ""
        },
        {
          "left": "James - Matthew 4",
          "right": ""
        },
        {
          "left": "Jeremiah - 2 Chronicles 36",
          "right": ""
        }
      ],
      "source_card": {
        "id": 6,
        "category": "People",
        "items": [
          "Isaac - Genesis 21",
          "Jacob - Genesis 25",
          "James - Matthew 4",
          "Jeremiah - 2 Chronicles 36"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 7,
    "front_text": "Jesus - Matthew 1",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-7",
      "contentItemId": "game-bible-question",
      "sortOrder": 7,
      "category": "People",
      "pairs": [
        {
          "left": "Jesus - Matthew 1",
          "right": ""
        },
        {
          "left": "Jonah - Jonah 1",
          "right": ""
        },
        {
          "left": "Jonathan - 1 Samuel 13",
          "right": ""
        },
        {
          "left": "Joseph - Genesis 37",
          "right": ""
        }
      ],
      "source_card": {
        "id": 7,
        "category": "People",
        "items": [
          "Jesus - Matthew 1",
          "Jonah - Jonah 1",
          "Jonathan - 1 Samuel 13",
          "Joseph - Genesis 37"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 8,
    "front_text": "Judas - Mark 10",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-8",
      "contentItemId": "game-bible-question",
      "sortOrder": 8,
      "category": "People",
      "pairs": [
        {
          "left": "Judas - Mark 10",
          "right": ""
        },
        {
          "left": "Lazarus - John 11",
          "right": ""
        },
        {
          "left": "Lot - Genesis 13",
          "right": ""
        },
        {
          "left": "Martha - Luke 10",
          "right": ""
        }
      ],
      "source_card": {
        "id": 8,
        "category": "People",
        "items": [
          "Judas - Mark 10",
          "Lazarus - John 11",
          "Lot - Genesis 13",
          "Martha - Luke 10"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 9,
    "front_text": "Moses - Exodus 2",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-9",
      "contentItemId": "game-bible-question",
      "sortOrder": 9,
      "category": "People",
      "pairs": [
        {
          "left": "Moses - Exodus 2",
          "right": ""
        },
        {
          "left": "Nicodemus - John 3",
          "right": ""
        },
        {
          "left": "Noah - Genesis 6",
          "right": ""
        },
        {
          "left": "Paul - Acts 13-14",
          "right": ""
        }
      ],
      "source_card": {
        "id": 9,
        "category": "People",
        "items": [
          "Moses - Exodus 2",
          "Nicodemus - John 3",
          "Noah - Genesis 6",
          "Paul - Acts 13-14"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 10,
    "front_text": "Samaritan - Luke 10",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-10",
      "contentItemId": "game-bible-question",
      "sortOrder": 10,
      "category": "People",
      "pairs": [
        {
          "left": "Samaritan - Luke 10",
          "right": ""
        },
        {
          "left": "Samson - Judges 13",
          "right": ""
        },
        {
          "left": "Sarah - Genesis 17",
          "right": ""
        },
        {
          "left": "Saul - 1 Samuel 9",
          "right": ""
        }
      ],
      "source_card": {
        "id": 10,
        "category": "People",
        "items": [
          "Samaritan - Luke 10",
          "Samson - Judges 13",
          "Sarah - Genesis 17",
          "Saul - 1 Samuel 9"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 11,
    "front_text": "Ark - Genesis 6:14",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-11",
      "contentItemId": "game-bible-question",
      "sortOrder": 11,
      "category": "Things",
      "pairs": [
        {
          "left": "Ark - Genesis 6:14",
          "right": ""
        },
        {
          "left": "Blood - Genesis 9:6",
          "right": ""
        },
        {
          "left": "Cross - 1 Peter 2:24",
          "right": ""
        },
        {
          "left": "Crown - 1 Chronicles 20:2",
          "right": ""
        }
      ],
      "source_card": {
        "id": 11,
        "category": "Things",
        "items": [
          "Ark - Genesis 6:14",
          "Blood - Genesis 9:6",
          "Cross - 1 Peter 2:24",
          "Crown - 1 Chronicles 20:2"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 12,
    "front_text": "Gold - Genesis 13:2",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-12",
      "contentItemId": "game-bible-question",
      "sortOrder": 12,
      "category": "Things",
      "pairs": [
        {
          "left": "Gold - Genesis 13:2",
          "right": ""
        },
        {
          "left": "Light - Genesis 1:3",
          "right": ""
        },
        {
          "left": "Moon - Joshua 10:13",
          "right": ""
        },
        {
          "left": "Cup - Luke 22:20",
          "right": ""
        }
      ],
      "source_card": {
        "id": 12,
        "category": "Things",
        "items": [
          "Gold - Genesis 13:2",
          "Light - Genesis 1:3",
          "Moon - Joshua 10:13",
          "Cup - Luke 22:20"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 13,
    "front_text": "Oil - Exodus 40:9",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-13",
      "contentItemId": "game-bible-question",
      "sortOrder": 13,
      "category": "Things",
      "pairs": [
        {
          "left": "Oil - Exodus 40:9",
          "right": ""
        },
        {
          "left": "Rock - Exodus 17:6",
          "right": ""
        },
        {
          "left": "Stone tablet - Exodus 34:4",
          "right": ""
        },
        {
          "left": "Ship - Isaiah 33:21",
          "right": ""
        }
      ],
      "source_card": {
        "id": 13,
        "category": "Things",
        "items": [
          "Oil - Exodus 40:9",
          "Rock - Exodus 17:6",
          "Stone tablet - Exodus 34:4",
          "Ship - Isaiah 33:21"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 14,
    "front_text": "Stars - Genesis 1:16",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-14",
      "contentItemId": "game-bible-question",
      "sortOrder": 14,
      "category": "Things",
      "pairs": [
        {
          "left": "Stars - Genesis 1:16",
          "right": ""
        },
        {
          "left": "Sword - Job 5:15",
          "right": ""
        },
        {
          "left": "Throne - Genesis 41:40",
          "right": ""
        },
        {
          "left": "Perfume - Song of Solomon 1:3",
          "right": ""
        }
      ],
      "source_card": {
        "id": 14,
        "category": "Things",
        "items": [
          "Stars - Genesis 1:16",
          "Sword - Job 5:15",
          "Throne - Genesis 41:40",
          "Perfume - Song of Solomon 1:3"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 15,
    "front_text": "Money - 1 Timothy 6:10",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-15",
      "contentItemId": "game-bible-question",
      "sortOrder": 15,
      "category": "Things",
      "pairs": [
        {
          "left": "Money - 1 Timothy 6:10",
          "right": ""
        },
        {
          "left": "Money - 1 Timothy 6:10",
          "right": ""
        },
        {
          "left": "Jar - Mark 14:3",
          "right": ""
        },
        {
          "left": "Belt - Jeremiah 13:1",
          "right": ""
        }
      ],
      "source_card": {
        "id": 15,
        "category": "Things",
        "items": [
          "Money - 1 Timothy 6:10",
          "Money - 1 Timothy 6:10",
          "Jar - Mark 14:3",
          "Belt - Jeremiah 13:1"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 16,
    "front_text": "Ant - Proverbs 6:6",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-16",
      "contentItemId": "game-bible-question",
      "sortOrder": 16,
      "category": "Animals",
      "pairs": [
        {
          "left": "Ant - Proverbs 6:6",
          "right": ""
        },
        {
          "left": "Bat - Leviticus 11:19",
          "right": ""
        },
        {
          "left": "Bear - 1 Samuel 17:34-37",
          "right": ""
        },
        {
          "left": "Bee - Judges 14:8",
          "right": ""
        }
      ],
      "source_card": {
        "id": 16,
        "category": "Animals",
        "items": [
          "Ant - Proverbs 6:6",
          "Bat - Leviticus 11:19",
          "Bear - 1 Samuel 17:34-37",
          "Bee - Judges 14:8"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 17,
    "front_text": "Camel - Genesis 24:10",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-17",
      "contentItemId": "game-bible-question",
      "sortOrder": 17,
      "category": "Animals",
      "pairs": [
        {
          "left": "Camel - Genesis 24:10",
          "right": ""
        },
        {
          "left": "Cobra - Isaiah 11:8",
          "right": ""
        },
        {
          "left": "Cow - Isaiah 11:7",
          "right": ""
        },
        {
          "left": "Deer - Deuteronomy 12:15",
          "right": ""
        }
      ],
      "source_card": {
        "id": 17,
        "category": "Animals",
        "items": [
          "Camel - Genesis 24:10",
          "Cobra - Isaiah 11:8",
          "Cow - Isaiah 11:7",
          "Deer - Deuteronomy 12:15"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 18,
    "front_text": "Dog - Judges 7:5",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-18",
      "contentItemId": "game-bible-question",
      "sortOrder": 18,
      "category": "Animals",
      "pairs": [
        {
          "left": "Dog - Judges 7:5",
          "right": ""
        },
        {
          "left": "Donkey - Isaiah 1:3",
          "right": ""
        },
        {
          "left": "Dove - Matthew 3:16",
          "right": ""
        },
        {
          "left": "Eagle - Isaiah 40:31",
          "right": ""
        }
      ],
      "source_card": {
        "id": 18,
        "category": "Animals",
        "items": [
          "Dog - Judges 7:5",
          "Donkey - Isaiah 1:3",
          "Dove - Matthew 3:16",
          "Eagle - Isaiah 40:31"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 19,
    "front_text": "Fish - Jonah 1:17",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-19",
      "contentItemId": "game-bible-question",
      "sortOrder": 19,
      "category": "Animals",
      "pairs": [
        {
          "left": "Fish - Jonah 1:17",
          "right": ""
        },
        {
          "left": "Frog - Exodus 8:2",
          "right": ""
        },
        {
          "left": "Goat - Genesis 15:9",
          "right": ""
        },
        {
          "left": "Grasshopper - Leviticus 11:22",
          "right": ""
        }
      ],
      "source_card": {
        "id": 19,
        "category": "Animals",
        "items": [
          "Fish - Jonah 1:17",
          "Frog - Exodus 8:2",
          "Goat - Genesis 15:9",
          "Grasshopper - Leviticus 11:22"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 20,
    "front_text": "Horse - 1 Kings 4:26",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-20",
      "contentItemId": "game-bible-question",
      "sortOrder": 20,
      "category": "Animals",
      "pairs": [
        {
          "left": "Horse - 1 Kings 4:26",
          "right": ""
        },
        {
          "left": "Lamb - 1 Samuel 17:34 (NLT)",
          "right": ""
        },
        {
          "left": "Leopard - Isaiah 11:6",
          "right": ""
        },
        {
          "left": "Lion - Judges 14:8",
          "right": ""
        }
      ],
      "source_card": {
        "id": 20,
        "category": "Animals",
        "items": [
          "Horse - 1 Kings 4:26",
          "Lamb - 1 Samuel 17:34 (NLT)",
          "Leopard - Isaiah 11:6",
          "Lion - Judges 14:8"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 21,
    "front_text": "Snake - Proverbs 23:32",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-21",
      "contentItemId": "game-bible-question",
      "sortOrder": 21,
      "category": "Animals",
      "pairs": [
        {
          "left": "Snake - Proverbs 23:32",
          "right": ""
        },
        {
          "left": "Spider - Isaiah 59:5",
          "right": ""
        },
        {
          "left": "Whale - Jonah 1:17",
          "right": ""
        },
        {
          "left": "Wolf - Matthew 7:15",
          "right": ""
        }
      ],
      "source_card": {
        "id": 21,
        "category": "Animals",
        "items": [
          "Snake - Proverbs 23:32",
          "Spider - Isaiah 59:5",
          "Whale - Jonah 1:17",
          "Wolf - Matthew 7:15"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 22,
    "front_text": "Quail - Exodus 16:13",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-22",
      "contentItemId": "game-bible-question",
      "sortOrder": 22,
      "category": "Animals",
      "pairs": [
        {
          "left": "Quail - Exodus 16:13",
          "right": ""
        },
        {
          "left": "Rat - Leviticus 11:29",
          "right": ""
        },
        {
          "left": "Rooster - Matthew 26:34",
          "right": ""
        },
        {
          "left": "Sheep - Luke 15:4",
          "right": ""
        }
      ],
      "source_card": {
        "id": 22,
        "category": "Animals",
        "items": [
          "Quail - Exodus 16:13",
          "Rat - Leviticus 11:29",
          "Rooster - Matthew 26:34",
          "Sheep - Luke 15:4"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 23,
    "front_text": "Lizard - Leviticus 11:30",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-23",
      "contentItemId": "game-bible-question",
      "sortOrder": 23,
      "category": "Animals",
      "pairs": [
        {
          "left": "Lizard - Leviticus 11:30",
          "right": ""
        },
        {
          "left": "Owl - Psalm 102:6",
          "right": ""
        },
        {
          "left": "Pig - Leviticus 11:7",
          "right": ""
        },
        {
          "left": "Pigeon - Genesis 15:9",
          "right": ""
        }
      ],
      "source_card": {
        "id": 23,
        "category": "Animals",
        "items": [
          "Lizard - Leviticus 11:30",
          "Owl - Psalm 102:6",
          "Pig - Leviticus 11:7",
          "Pigeon - Genesis 15:9"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 24,
    "front_text": "Egypt - Isaiah 19:1",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-24",
      "contentItemId": "game-bible-question",
      "sortOrder": 24,
      "category": "Places",
      "pairs": [
        {
          "left": "Egypt - Isaiah 19:1",
          "right": ""
        },
        {
          "left": "Galilee - Matthew 26:32",
          "right": ""
        },
        {
          "left": "Garden of Eden - Genesis 2:15",
          "right": ""
        },
        {
          "left": "Gethsemane - Mark 14:32",
          "right": ""
        }
      ],
      "source_card": {
        "id": 24,
        "category": "Places",
        "items": [
          "Egypt - Isaiah 19:1",
          "Galilee - Matthew 26:32",
          "Garden of Eden - Genesis 2:15",
          "Gethsemane - Mark 14:32"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 25,
    "front_text": "Altar - Leviticus 1:15",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-25",
      "contentItemId": "game-bible-question",
      "sortOrder": 25,
      "category": "Places",
      "pairs": [
        {
          "left": "Altar - Leviticus 1:15",
          "right": ""
        },
        {
          "left": "Bethlehem - Matthew 2:8",
          "right": ""
        },
        {
          "left": "Desert - Exodus 13:18",
          "right": ""
        },
        {
          "left": "Dead Sea - Ezekiel 47:8",
          "right": ""
        }
      ],
      "source_card": {
        "id": 25,
        "category": "Places",
        "items": [
          "Altar - Leviticus 1:15",
          "Bethlehem - Matthew 2:8",
          "Desert - Exodus 13:18",
          "Dead Sea - Ezekiel 47:8"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 26,
    "front_text": "Red Sea - Exodus 15:4",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-26",
      "contentItemId": "game-bible-question",
      "sortOrder": 26,
      "category": "Places",
      "pairs": [
        {
          "left": "Red Sea - Exodus 15:4",
          "right": ""
        },
        {
          "left": "Heaven - Matthew 16:19",
          "right": ""
        },
        {
          "left": "Hell - Matthew 16:19",
          "right": ""
        },
        {
          "left": "Israel - 1 Samuel 7:14",
          "right": ""
        }
      ],
      "source_card": {
        "id": 26,
        "category": "Places",
        "items": [
          "Red Sea - Exodus 15:4",
          "Heaven - Matthew 16:19",
          "Hell - Matthew 16:19",
          "Israel - 1 Samuel 7:14"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 27,
    "front_text": "Jericho - 2 Kings 2:4",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-27",
      "contentItemId": "game-bible-question",
      "sortOrder": 27,
      "category": "Places",
      "pairs": [
        {
          "left": "Jericho - 2 Kings 2:4",
          "right": ""
        },
        {
          "left": "Jerusalem - Acts 21:17",
          "right": ""
        },
        {
          "left": "Nazareth - Matthew 21:11",
          "right": ""
        },
        {
          "left": "Paradise - Luke 23:43",
          "right": ""
        }
      ],
      "source_card": {
        "id": 27,
        "category": "Places",
        "items": [
          "Jericho - 2 Kings 2:4",
          "Jerusalem - Acts 21:17",
          "Nazareth - Matthew 21:11",
          "Paradise - Luke 23:43"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 28,
    "front_text": "Sodom - Genesis 19:1",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-28",
      "contentItemId": "game-bible-question",
      "sortOrder": 28,
      "category": "Places",
      "pairs": [
        {
          "left": "Sodom - Genesis 19:1",
          "right": ""
        },
        {
          "left": "Mt. Sinai - Leviticus 27:34",
          "right": ""
        },
        {
          "left": "Mt. Ararat - Genesis 8:4",
          "right": ""
        },
        {
          "left": "Mt. Carmel - 1 Kings 18:19",
          "right": ""
        }
      ],
      "source_card": {
        "id": 28,
        "category": "Places",
        "items": [
          "Sodom - Genesis 19:1",
          "Mt. Sinai - Leviticus 27:34",
          "Mt. Ararat - Genesis 8:4",
          "Mt. Carmel - 1 Kings 18:19"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 29,
    "front_text": "Mt. Horeb - Exodus 3:1",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-29",
      "contentItemId": "game-bible-question",
      "sortOrder": 29,
      "category": "Places",
      "pairs": [
        {
          "left": "Mt. Horeb - Exodus 3:1",
          "right": ""
        },
        {
          "left": "Samaria - Acts 1:8",
          "right": ""
        },
        {
          "left": "Mt. Olives - Luke 22:39",
          "right": ""
        },
        {
          "left": "Tabernacle - Exodus 39:32",
          "right": ""
        }
      ],
      "source_card": {
        "id": 29,
        "category": "Places",
        "items": [
          "Mt. Horeb - Exodus 3:1",
          "Samaria - Acts 1:8",
          "Mt. Olives - Luke 22:39",
          "Tabernacle - Exodus 39:32"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 30,
    "front_text": "Jesus' Baptism - Matt. 3:13-17",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-30",
      "contentItemId": "game-bible-question",
      "sortOrder": 30,
      "category": "Events",
      "pairs": [
        {
          "left": "Jesus' Baptism - Matt. 3:13-17",
          "right": ""
        },
        {
          "left": "The Creation - Genesis 1",
          "right": ""
        },
        {
          "left": "The Temptation - Matt. 4:1-11",
          "right": ""
        },
        {
          "left": "Fall of Man - Genesis 3",
          "right": ""
        }
      ],
      "source_card": {
        "id": 30,
        "category": "Events",
        "items": [
          "Jesus' Baptism - Matt. 3:13-17",
          "The Creation - Genesis 1",
          "The Temptation - Matt. 4:1-11",
          "Fall of Man - Genesis 3"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 31,
    "front_text": "Resurrection - John 20",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-31",
      "contentItemId": "game-bible-question",
      "sortOrder": 31,
      "category": "Events",
      "pairs": [
        {
          "left": "Resurrection - John 20",
          "right": ""
        },
        {
          "left": "Salvation - Romans 1:16",
          "right": ""
        },
        {
          "left": "War - Deuteronomy 20:1",
          "right": ""
        },
        {
          "left": "The Transfiguration - Matthew 17",
          "right": ""
        }
      ],
      "source_card": {
        "id": 31,
        "category": "Events",
        "items": [
          "Resurrection - John 20",
          "Salvation - Romans 1:16",
          "War - Deuteronomy 20:1",
          "The Transfiguration - Matthew 17"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 32,
    "front_text": "Exodus from Egypt - Exodus 12-15",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-32",
      "contentItemId": "game-bible-question",
      "sortOrder": 32,
      "category": "Events",
      "pairs": [
        {
          "left": "Exodus from Egypt - Exodus 12-15",
          "right": ""
        },
        {
          "left": "Fasting - Matthew 6:16",
          "right": ""
        },
        {
          "left": "Flood - Genesis 9:11",
          "right": ""
        },
        {
          "left": "Birth of Christ - Luke 2:1-19",
          "right": ""
        }
      ],
      "source_card": {
        "id": 32,
        "category": "Events",
        "items": [
          "Exodus from Egypt - Exodus 12-15",
          "Fasting - Matthew 6:16",
          "Flood - Genesis 9:11",
          "Birth of Christ - Luke 2:1-19"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 33,
    "front_text": "Apples - Song of Solomon 2:5",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-33",
      "contentItemId": "game-bible-question",
      "sortOrder": 33,
      "category": "Food",
      "pairs": [
        {
          "left": "Apples - Song of Solomon 2:5",
          "right": ""
        },
        {
          "left": "Almonds - Numbers 17:8",
          "right": ""
        },
        {
          "left": "Grapes - Leviticus 19:10",
          "right": ""
        },
        {
          "left": "Melons - Numbers 11:5",
          "right": ""
        }
      ],
      "source_card": {
        "id": 33,
        "category": "Food",
        "items": [
          "Apples - Song of Solomon 2:5",
          "Almonds - Numbers 17:8",
          "Grapes - Leviticus 19:10",
          "Melons - Numbers 11:5"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 34,
    "front_text": "Bread - Mark 8:14",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-34",
      "contentItemId": "game-bible-question",
      "sortOrder": 34,
      "category": "Food",
      "pairs": [
        {
          "left": "Bread - Mark 8:14",
          "right": ""
        },
        {
          "left": "Grain - Matthew 12:1",
          "right": ""
        },
        {
          "left": "Wheat - 2 Samuel 17:28",
          "right": ""
        },
        {
          "left": "Stew - Genesis 25:30",
          "right": ""
        }
      ],
      "source_card": {
        "id": 34,
        "category": "Food",
        "items": [
          "Bread - Mark 8:14",
          "Grain - Matthew 12:1",
          "Wheat - 2 Samuel 17:28",
          "Stew - Genesis 25:30"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 35,
    "front_text": "Butter - Proverbs 30:33",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-35",
      "contentItemId": "game-bible-question",
      "sortOrder": 35,
      "category": "Food",
      "pairs": [
        {
          "left": "Butter - Proverbs 30:33",
          "right": ""
        },
        {
          "left": "Cheese - Job 10:10",
          "right": ""
        },
        {
          "left": "Milk - Exodus 33:3",
          "right": ""
        },
        {
          "left": "Eggs - Luke 11:12",
          "right": ""
        }
      ],
      "source_card": {
        "id": 35,
        "category": "Food",
        "items": [
          "Butter - Proverbs 30:33",
          "Cheese - Job 10:10",
          "Milk - Exodus 33:3",
          "Eggs - Luke 11:12"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 36,
    "front_text": "Self-control - 1 Corinthians 7:5",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-36",
      "contentItemId": "game-bible-question",
      "sortOrder": 36,
      "category": "Christian Virtues/Values",
      "pairs": [
        {
          "left": "Self-control - 1 Corinthians 7:5",
          "right": ""
        },
        {
          "left": "Forgiveness - Ephesians 1:7",
          "right": ""
        },
        {
          "left": "Humility - Philippians 2:3",
          "right": ""
        },
        {
          "left": "Thankful - Colossians 4",
          "right": ""
        }
      ],
      "source_card": {
        "id": 36,
        "category": "Christian Virtues/Values",
        "items": [
          "Self-control - 1 Corinthians 7:5",
          "Forgiveness - Ephesians 1:7",
          "Humility - Philippians 2:3",
          "Thankful - Colossians 4"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 37,
    "front_text": "Kindness - Romans 11:22",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-37",
      "contentItemId": "game-bible-question",
      "sortOrder": 37,
      "category": "Christian Virtues/Values",
      "pairs": [
        {
          "left": "Kindness - Romans 11:22",
          "right": ""
        },
        {
          "left": "Goodness - Psalm 27:13",
          "right": ""
        },
        {
          "left": "Faithfulness - Psalm 85:10",
          "right": ""
        },
        {
          "left": "Gentleness - Philippians 4:5",
          "right": ""
        }
      ],
      "source_card": {
        "id": 37,
        "category": "Christian Virtues/Values",
        "items": [
          "Kindness - Romans 11:22",
          "Goodness - Psalm 27:13",
          "Faithfulness - Psalm 85:10",
          "Gentleness - Philippians 4:5"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 38,
    "front_text": "Love - 1 Corinthians 13",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-38",
      "contentItemId": "game-bible-question",
      "sortOrder": 38,
      "category": "Christian Virtues/Values",
      "pairs": [
        {
          "left": "Love - 1 Corinthians 13",
          "right": ""
        },
        {
          "left": "Joy - John 15:11",
          "right": ""
        },
        {
          "left": "Peace - Colossians 3:15",
          "right": ""
        },
        {
          "left": "Patience - Proverbs 19:11",
          "right": ""
        }
      ],
      "source_card": {
        "id": 38,
        "category": "Christian Virtues/Values",
        "items": [
          "Love - 1 Corinthians 13",
          "Joy - John 15:11",
          "Peace - Colossians 3:15",
          "Patience - Proverbs 19:11"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 39,
    "front_text": "Carpenter - Isaiah 44:13",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-39",
      "contentItemId": "game-bible-question",
      "sortOrder": 39,
      "category": "Occupation",
      "pairs": [
        {
          "left": "Carpenter - Isaiah 44:13",
          "right": ""
        },
        {
          "left": "Soldier - 2 Timothy 2:4",
          "right": ""
        },
        {
          "left": "Hunter - Jeremiah 16:16",
          "right": ""
        },
        {
          "left": "Teacher - Luke 6:40",
          "right": ""
        }
      ],
      "source_card": {
        "id": 39,
        "category": "Occupation",
        "items": [
          "Carpenter - Isaiah 44:13",
          "Soldier - 2 Timothy 2:4",
          "Hunter - Jeremiah 16:16",
          "Teacher - Luke 6:40"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 40,
    "front_text": "Evangelist - 2 Timothy 4:5",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-40",
      "contentItemId": "game-bible-question",
      "sortOrder": 40,
      "category": "Occupation",
      "pairs": [
        {
          "left": "Evangelist - 2 Timothy 4:5",
          "right": ""
        },
        {
          "left": "Farmer - 2 Timothy 2:6",
          "right": ""
        },
        {
          "left": "Fisherman - Matthew 4:18",
          "right": ""
        },
        {
          "left": "King - 2 Kings 6:26",
          "right": ""
        }
      ],
      "source_card": {
        "id": 40,
        "category": "Occupation",
        "items": [
          "Evangelist - 2 Timothy 4:5",
          "Farmer - 2 Timothy 2:6",
          "Fisherman - Matthew 4:18",
          "King - 2 Kings 6:26"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 41,
    "front_text": "Musician - 2 Chronicles 5:13",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-41",
      "contentItemId": "game-bible-question",
      "sortOrder": 41,
      "category": "Occupation",
      "pairs": [
        {
          "left": "Musician - 2 Chronicles 5:13",
          "right": ""
        },
        {
          "left": "Pastor - Ephesians 4:11",
          "right": ""
        },
        {
          "left": "Pharaoh - Genesis 12:17",
          "right": ""
        },
        {
          "left": "Prophet - Exodus 7:1",
          "right": ""
        }
      ],
      "source_card": {
        "id": 41,
        "category": "Occupation",
        "items": [
          "Musician - 2 Chronicles 5:13",
          "Pastor - Ephesians 4:11",
          "Pharaoh - Genesis 12:17",
          "Prophet - Exodus 7:1"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 42,
    "front_text": "Philippians",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-42",
      "contentItemId": "game-bible-question",
      "sortOrder": 42,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Philippians",
          "right": ""
        },
        {
          "left": "Peter",
          "right": ""
        },
        {
          "left": "Revelation",
          "right": ""
        },
        {
          "left": "Romans",
          "right": ""
        }
      ],
      "source_card": {
        "id": 42,
        "category": "Bible Books",
        "items": [
          "Philippians",
          "Peter",
          "Revelation",
          "Romans"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 43,
    "front_text": "Jude",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-43",
      "contentItemId": "game-bible-question",
      "sortOrder": 43,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Jude",
          "right": ""
        },
        {
          "left": "Luke",
          "right": ""
        },
        {
          "left": "Mark",
          "right": ""
        },
        {
          "left": "Matthew",
          "right": ""
        }
      ],
      "source_card": {
        "id": 43,
        "category": "Bible Books",
        "items": [
          "Jude",
          "Luke",
          "Mark",
          "Matthew"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 44,
    "front_text": "Ephesians",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-44",
      "contentItemId": "game-bible-question",
      "sortOrder": 44,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Ephesians",
          "right": ""
        },
        {
          "left": "Galatians",
          "right": ""
        },
        {
          "left": "Hebrews",
          "right": ""
        },
        {
          "left": "John",
          "right": ""
        }
      ],
      "source_card": {
        "id": 44,
        "category": "Bible Books",
        "items": [
          "Ephesians",
          "Galatians",
          "Hebrews",
          "John"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 45,
    "front_text": "Samuel",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-45",
      "contentItemId": "game-bible-question",
      "sortOrder": 45,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Samuel",
          "right": ""
        },
        {
          "left": "Acts",
          "right": ""
        },
        {
          "left": "Colossians",
          "right": ""
        },
        {
          "left": "Corinthians",
          "right": ""
        }
      ],
      "source_card": {
        "id": 45,
        "category": "Bible Books",
        "items": [
          "Samuel",
          "Acts",
          "Colossians",
          "Corinthians"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 46,
    "front_text": "Numbers",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-46",
      "contentItemId": "game-bible-question",
      "sortOrder": 46,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Numbers",
          "right": ""
        },
        {
          "left": "Proverbs",
          "right": ""
        },
        {
          "left": "Psalms",
          "right": ""
        },
        {
          "left": "Ruth",
          "right": ""
        }
      ],
      "source_card": {
        "id": 46,
        "category": "Bible Books",
        "items": [
          "Numbers",
          "Proverbs",
          "Psalms",
          "Ruth"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 47,
    "front_text": "Kings",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-47",
      "contentItemId": "game-bible-question",
      "sortOrder": 47,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Kings",
          "right": ""
        },
        {
          "left": "Kings",
          "right": ""
        },
        {
          "left": "Malachi",
          "right": ""
        },
        {
          "left": "Nehemiah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 47,
        "category": "Bible Books",
        "items": [
          "Kings",
          "Kings",
          "Malachi",
          "Nehemiah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 48,
    "front_text": "Isaiah",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-48",
      "contentItemId": "game-bible-question",
      "sortOrder": 48,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Isaiah",
          "right": ""
        },
        {
          "left": "Job",
          "right": ""
        },
        {
          "left": "Joshua",
          "right": ""
        },
        {
          "left": "Judges",
          "right": ""
        }
      ],
      "source_card": {
        "id": 48,
        "category": "Bible Books",
        "items": [
          "Isaiah",
          "Job",
          "Joshua",
          "Judges"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 49,
    "front_text": "Exodus",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-49",
      "contentItemId": "game-bible-question",
      "sortOrder": 49,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Exodus",
          "right": ""
        },
        {
          "left": "Ezekiel",
          "right": ""
        },
        {
          "left": "Genesis",
          "right": ""
        },
        {
          "left": "Habakkuk",
          "right": ""
        }
      ],
      "source_card": {
        "id": 49,
        "category": "Bible Books",
        "items": [
          "Exodus",
          "Ezekiel",
          "Genesis",
          "Habakkuk"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-question",
    "sort_order": 50,
    "front_text": "Chronicles",
    "back_text": "",
    "metadata": {
      "id": "game-bible-question-card-50",
      "contentItemId": "game-bible-question",
      "sortOrder": 50,
      "category": "Bible Books",
      "pairs": [
        {
          "left": "Chronicles",
          "right": ""
        },
        {
          "left": "Daniel",
          "right": ""
        },
        {
          "left": "Deuteronomy",
          "right": ""
        },
        {
          "left": "Ecclesiastes",
          "right": ""
        }
      ],
      "source_card": {
        "id": 50,
        "category": "Bible Books",
        "items": [
          "Chronicles",
          "Daniel",
          "Deuteronomy",
          "Ecclesiastes"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 1,
    "front_text": "Noah",
    "back_text": "",
    "metadata": {
      "id": 1,
      "contentItemId": "game-bible-talk",
      "sortOrder": 1,
      "pairs": [
        {
          "left": "Noah",
          "right": ""
        },
        {
          "left": "Ark",
          "right": ""
        },
        {
          "left": "Flood",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Forty",
          "right": ""
        },
        {
          "left": "Boat",
          "right": ""
        }
      ],
      "source_card": {
        "id": 1,
        "term": "Noah",
        "clues": [
          "Ark",
          "Flood",
          "Animals",
          "Forty",
          "Boat"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 2,
    "front_text": "Samson",
    "back_text": "",
    "metadata": {
      "id": 2,
      "contentItemId": "game-bible-talk",
      "sortOrder": 2,
      "pairs": [
        {
          "left": "Samson",
          "right": ""
        },
        {
          "left": "Delilah",
          "right": ""
        },
        {
          "left": "Hair",
          "right": ""
        },
        {
          "left": "Strong",
          "right": ""
        },
        {
          "left": "Temple",
          "right": ""
        },
        {
          "left": "Cut",
          "right": ""
        }
      ],
      "source_card": {
        "id": 2,
        "term": "Samson",
        "clues": [
          "Delilah",
          "Hair",
          "Strong",
          "Temple",
          "Cut"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 3,
    "front_text": "Love",
    "back_text": "",
    "metadata": {
      "id": 3,
      "contentItemId": "game-bible-talk",
      "sortOrder": 3,
      "pairs": [
        {
          "left": "Love",
          "right": ""
        },
        {
          "left": "Neighbor",
          "right": ""
        },
        {
          "left": "Heart",
          "right": ""
        },
        {
          "left": "Care",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Hate",
          "right": ""
        }
      ],
      "source_card": {
        "id": 3,
        "term": "Love",
        "clues": [
          "Neighbor",
          "Heart",
          "Care",
          "Jesus",
          "Hate"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 4,
    "front_text": "Prayer",
    "back_text": "",
    "metadata": {
      "id": 4,
      "contentItemId": "game-bible-talk",
      "sortOrder": 4,
      "pairs": [
        {
          "left": "Prayer",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Talk",
          "right": ""
        },
        {
          "left": "Ask",
          "right": ""
        },
        {
          "left": "Thank",
          "right": ""
        },
        {
          "left": "Hands",
          "right": ""
        }
      ],
      "source_card": {
        "id": 4,
        "term": "Prayer",
        "clues": [
          "God",
          "Talk",
          "Ask",
          "Thank",
          "Hands"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 5,
    "front_text": "Egypt",
    "back_text": "",
    "metadata": {
      "id": 5,
      "contentItemId": "game-bible-talk",
      "sortOrder": 5,
      "pairs": [
        {
          "left": "Egypt",
          "right": ""
        },
        {
          "left": "Slaves",
          "right": ""
        },
        {
          "left": "Pyramids",
          "right": ""
        },
        {
          "left": "Nile",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        },
        {
          "left": "Pharaoh",
          "right": ""
        }
      ],
      "source_card": {
        "id": 5,
        "term": "Egypt",
        "clues": [
          "Slaves",
          "Pyramids",
          "Nile",
          "Israelites",
          "Pharaoh"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 6,
    "front_text": "Forgiveness",
    "back_text": "",
    "metadata": {
      "id": 6,
      "contentItemId": "game-bible-talk",
      "sortOrder": 6,
      "pairs": [
        {
          "left": "Forgiveness",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Cross",
          "right": ""
        },
        {
          "left": "Grace",
          "right": ""
        },
        {
          "left": "Resurrection",
          "right": ""
        }
      ],
      "source_card": {
        "id": 6,
        "term": "Forgiveness",
        "clues": [
          "Sin",
          "Jesus",
          "Cross",
          "Grace",
          "Resurrection"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 7,
    "front_text": "Creation",
    "back_text": "",
    "metadata": {
      "id": 7,
      "contentItemId": "game-bible-talk",
      "sortOrder": 7,
      "pairs": [
        {
          "left": "Creation",
          "right": ""
        },
        {
          "left": "World",
          "right": ""
        },
        {
          "left": "Seven",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Adam",
          "right": ""
        },
        {
          "left": "Eve",
          "right": ""
        }
      ],
      "source_card": {
        "id": 7,
        "term": "Creation",
        "clues": [
          "World",
          "Seven",
          "Animals",
          "Adam",
          "Eve"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 8,
    "front_text": "Jesus",
    "back_text": "",
    "metadata": {
      "id": 8,
      "contentItemId": "game-bible-talk",
      "sortOrder": 8,
      "pairs": [
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Son",
          "right": ""
        },
        {
          "left": "Saviour",
          "right": ""
        },
        {
          "left": "Cross",
          "right": ""
        },
        {
          "left": "Died",
          "right": ""
        }
      ],
      "source_card": {
        "id": 8,
        "term": "Jesus",
        "clues": [
          "God",
          "Son",
          "Saviour",
          "Cross",
          "Died"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 9,
    "front_text": "Paul",
    "back_text": "",
    "metadata": {
      "id": 9,
      "contentItemId": "game-bible-talk",
      "sortOrder": 9,
      "pairs": [
        {
          "left": "Paul",
          "right": ""
        },
        {
          "left": "Saul",
          "right": ""
        },
        {
          "left": "Apostle",
          "right": ""
        },
        {
          "left": "Persecution",
          "right": ""
        },
        {
          "left": "Gaol",
          "right": ""
        },
        {
          "left": "New Testament",
          "right": ""
        }
      ],
      "source_card": {
        "id": 9,
        "term": "Paul",
        "clues": [
          "Saul",
          "Apostle",
          "Persecution",
          "Gaol",
          "New Testament"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 10,
    "front_text": "Sin",
    "back_text": "",
    "metadata": {
      "id": 10,
      "contentItemId": "game-bible-talk",
      "sortOrder": 10,
      "pairs": [
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Bad",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Punishment",
          "right": ""
        },
        {
          "left": "Satan",
          "right": ""
        }
      ],
      "source_card": {
        "id": 10,
        "term": "Sin",
        "clues": [
          "God",
          "Bad",
          "Jesus",
          "Punishment",
          "Satan"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 11,
    "front_text": "Salt",
    "back_text": "",
    "metadata": {
      "id": 11,
      "contentItemId": "game-bible-talk",
      "sortOrder": 11,
      "pairs": [
        {
          "left": "Salt",
          "right": ""
        },
        {
          "left": "Youth",
          "right": ""
        },
        {
          "left": "Group",
          "right": ""
        },
        {
          "left": "All Saints",
          "right": ""
        },
        {
          "left": "Pepper",
          "right": ""
        },
        {
          "left": "Us",
          "right": ""
        }
      ],
      "source_card": {
        "id": 11,
        "term": "Salt",
        "clues": [
          "Youth",
          "Group",
          "All Saints",
          "Pepper",
          "Us"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 12,
    "front_text": "Disciples",
    "back_text": "",
    "metadata": {
      "id": 12,
      "contentItemId": "game-bible-talk",
      "sortOrder": 12,
      "pairs": [
        {
          "left": "Disciples",
          "right": ""
        },
        {
          "left": "Twelve",
          "right": ""
        },
        {
          "left": "Followers",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Peter",
          "right": ""
        },
        {
          "left": "James",
          "right": ""
        }
      ],
      "source_card": {
        "id": 12,
        "term": "Disciples",
        "clues": [
          "Twelve",
          "Followers",
          "Jesus",
          "Peter",
          "James"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 13,
    "front_text": "Cross",
    "back_text": "",
    "metadata": {
      "id": 13,
      "contentItemId": "game-bible-talk",
      "sortOrder": 13,
      "pairs": [
        {
          "left": "Cross",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Resurrection",
          "right": ""
        },
        {
          "left": "Punishment",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        }
      ],
      "source_card": {
        "id": 13,
        "term": "Cross",
        "clues": [
          "Jesus",
          "Death",
          "Resurrection",
          "Punishment",
          "Sin"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 14,
    "front_text": "Bible",
    "back_text": "",
    "metadata": {
      "id": 14,
      "contentItemId": "game-bible-talk",
      "sortOrder": 14,
      "pairs": [
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        },
        {
          "left": "New Testament",
          "right": ""
        },
        {
          "left": "Word",
          "right": ""
        }
      ],
      "source_card": {
        "id": 14,
        "term": "Bible",
        "clues": [
          "Book",
          "God",
          "Old Testament",
          "New Testament",
          "Word"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 15,
    "front_text": "John the Baptist",
    "back_text": "",
    "metadata": {
      "id": 15,
      "contentItemId": "game-bible-talk",
      "sortOrder": 15,
      "pairs": [
        {
          "left": "John the Baptist",
          "right": ""
        },
        {
          "left": "Beheaded",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Prepare",
          "right": ""
        },
        {
          "left": "Locusts",
          "right": ""
        },
        {
          "left": "Sackcloth",
          "right": ""
        }
      ],
      "source_card": {
        "id": 15,
        "term": "John the Baptist",
        "clues": [
          "Beheaded",
          "Jesus",
          "Prepare",
          "Locusts",
          "Sackcloth"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 16,
    "front_text": "Revelation",
    "back_text": "",
    "metadata": {
      "id": 16,
      "contentItemId": "game-bible-talk",
      "sortOrder": 16,
      "pairs": [
        {
          "left": "Revelation",
          "right": ""
        },
        {
          "left": "New Testament",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Last",
          "right": ""
        },
        {
          "left": "End",
          "right": ""
        },
        {
          "left": "Second Coming",
          "right": ""
        }
      ],
      "source_card": {
        "id": 16,
        "term": "Revelation",
        "clues": [
          "New Testament",
          "Book",
          "Last",
          "End",
          "Second Coming"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 17,
    "front_text": "Moses",
    "back_text": "",
    "metadata": {
      "id": 17,
      "contentItemId": "game-bible-talk",
      "sortOrder": 17,
      "pairs": [
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Egypt",
          "right": ""
        },
        {
          "left": "Basket",
          "right": ""
        },
        {
          "left": "Ten Commandments",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        },
        {
          "left": "Pharaoh",
          "right": ""
        }
      ],
      "source_card": {
        "id": 17,
        "term": "Moses",
        "clues": [
          "Egypt",
          "Basket",
          "Ten Commandments",
          "Israelites",
          "Pharaoh"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 18,
    "front_text": "Mary",
    "back_text": "",
    "metadata": {
      "id": 18,
      "contentItemId": "game-bible-talk",
      "sortOrder": 18,
      "pairs": [
        {
          "left": "Mary",
          "right": ""
        },
        {
          "left": "Mother",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Virgin",
          "right": ""
        },
        {
          "left": "Gabriel",
          "right": ""
        },
        {
          "left": "Pregnant",
          "right": ""
        }
      ],
      "source_card": {
        "id": 18,
        "term": "Mary",
        "clues": [
          "Mother",
          "Jesus",
          "Virgin",
          "Gabriel",
          "Pregnant"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 19,
    "front_text": "Miracle",
    "back_text": "",
    "metadata": {
      "id": 19,
      "contentItemId": "game-bible-talk",
      "sortOrder": 19,
      "pairs": [
        {
          "left": "Miracle",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Blind",
          "right": ""
        },
        {
          "left": "Lame",
          "right": ""
        },
        {
          "left": "Amazing",
          "right": ""
        },
        {
          "left": "Healing",
          "right": ""
        }
      ],
      "source_card": {
        "id": 19,
        "term": "Miracle",
        "clues": [
          "Jesus",
          "Blind",
          "Lame",
          "Amazing",
          "Healing"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 20,
    "front_text": "Exodus",
    "back_text": "",
    "metadata": {
      "id": 20,
      "contentItemId": "game-bible-talk",
      "sortOrder": 20,
      "pairs": [
        {
          "left": "Exodus",
          "right": ""
        },
        {
          "left": "Desert",
          "right": ""
        },
        {
          "left": "Wandering",
          "right": ""
        },
        {
          "left": "Manna",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Forty",
          "right": ""
        }
      ],
      "source_card": {
        "id": 20,
        "term": "Exodus",
        "clues": [
          "Desert",
          "Wandering",
          "Manna",
          "Moses",
          "Forty"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 21,
    "front_text": "Solomon",
    "back_text": "",
    "metadata": {
      "id": 21,
      "contentItemId": "game-bible-talk",
      "sortOrder": 21,
      "pairs": [
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Wise",
          "right": ""
        },
        {
          "left": "Concubines",
          "right": ""
        },
        {
          "left": "Rich",
          "right": ""
        },
        {
          "left": "Temple",
          "right": ""
        }
      ],
      "source_card": {
        "id": 21,
        "term": "Solomon",
        "clues": [
          "King",
          "Wise",
          "Concubines",
          "Rich",
          "Temple"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 22,
    "front_text": "Parable",
    "back_text": "",
    "metadata": {
      "id": 22,
      "contentItemId": "game-bible-talk",
      "sortOrder": 22,
      "pairs": [
        {
          "left": "Parable",
          "right": ""
        },
        {
          "left": "Story",
          "right": ""
        },
        {
          "left": "Explanation",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Gospels",
          "right": ""
        },
        {
          "left": "Understand",
          "right": ""
        }
      ],
      "source_card": {
        "id": 22,
        "term": "Parable",
        "clues": [
          "Story",
          "Explanation",
          "Jesus",
          "Gospels",
          "Understand"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 23,
    "front_text": "Daniel",
    "back_text": "",
    "metadata": {
      "id": 23,
      "contentItemId": "game-bible-talk",
      "sortOrder": 23,
      "pairs": [
        {
          "left": "Daniel",
          "right": ""
        },
        {
          "left": "Lion",
          "right": ""
        },
        {
          "left": "Den",
          "right": ""
        },
        {
          "left": "Dreams",
          "right": ""
        },
        {
          "left": "Higgins",
          "right": ""
        },
        {
          "left": "Pray",
          "right": ""
        }
      ],
      "source_card": {
        "id": 23,
        "term": "Daniel",
        "clues": [
          "Lion",
          "Den",
          "Dreams",
          "Higgins",
          "Pray"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 24,
    "front_text": "David",
    "back_text": "",
    "metadata": {
      "id": 24,
      "contentItemId": "game-bible-talk",
      "sortOrder": 24,
      "pairs": [
        {
          "left": "David",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Psalms",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Bathsheba",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 24,
        "term": "David",
        "clues": [
          "King",
          "Psalms",
          "God",
          "Bathsheba",
          "Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 25,
    "front_text": "Resurrection",
    "back_text": "",
    "metadata": {
      "id": 25,
      "contentItemId": "game-bible-talk",
      "sortOrder": 25,
      "pairs": [
        {
          "left": "Resurrection",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "Tomb",
          "right": ""
        },
        {
          "left": "Cross",
          "right": ""
        }
      ],
      "source_card": {
        "id": 25,
        "term": "Resurrection",
        "clues": [
          "Jesus",
          "Death",
          "Sin",
          "Tomb",
          "Cross"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 26,
    "front_text": "Plague",
    "back_text": "",
    "metadata": {
      "id": 26,
      "contentItemId": "game-bible-talk",
      "sortOrder": 26,
      "pairs": [
        {
          "left": "Plague",
          "right": ""
        },
        {
          "left": "Pharaoh",
          "right": ""
        },
        {
          "left": "Ten",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Locusts",
          "right": ""
        },
        {
          "left": "Egypt",
          "right": ""
        }
      ],
      "source_card": {
        "id": 26,
        "term": "Plague",
        "clues": [
          "Pharaoh",
          "Ten",
          "Moses",
          "Locusts",
          "Egypt"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 27,
    "front_text": "Missionary",
    "back_text": "",
    "metadata": {
      "id": 27,
      "contentItemId": "game-bible-talk",
      "sortOrder": 27,
      "pairs": [
        {
          "left": "Missionary",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "World",
          "right": ""
        },
        {
          "left": "Travel",
          "right": ""
        },
        {
          "left": "Gospel",
          "right": ""
        },
        {
          "left": "Christian",
          "right": ""
        }
      ],
      "source_card": {
        "id": 27,
        "term": "Missionary",
        "clues": [
          "Jesus",
          "World",
          "Travel",
          "Gospel",
          "Christian"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 28,
    "front_text": "Psalm",
    "back_text": "",
    "metadata": {
      "id": 28,
      "contentItemId": "game-bible-talk",
      "sortOrder": 28,
      "pairs": [
        {
          "left": "Psalm",
          "right": ""
        },
        {
          "left": "David",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        },
        {
          "left": "Songs",
          "right": ""
        },
        {
          "left": "150",
          "right": ""
        },
        {
          "left": "Praise",
          "right": ""
        }
      ],
      "source_card": {
        "id": 28,
        "term": "Psalm",
        "clues": [
          "David",
          "Old Testament",
          "Songs",
          "150",
          "Praise"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 29,
    "front_text": "Tomb",
    "back_text": "",
    "metadata": {
      "id": 29,
      "contentItemId": "game-bible-talk",
      "sortOrder": 29,
      "pairs": [
        {
          "left": "Tomb",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Stone",
          "right": ""
        },
        {
          "left": "Resurrection",
          "right": ""
        },
        {
          "left": "Three Days",
          "right": ""
        }
      ],
      "source_card": {
        "id": 29,
        "term": "Tomb",
        "clues": [
          "Jesus",
          "Death",
          "Stone",
          "Resurrection",
          "Three Days"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 30,
    "front_text": "Judgment",
    "back_text": "",
    "metadata": {
      "id": 30,
      "contentItemId": "game-bible-talk",
      "sortOrder": 30,
      "pairs": [
        {
          "left": "Judgment",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Punishment",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "Heaven",
          "right": ""
        },
        {
          "left": "End",
          "right": ""
        }
      ],
      "source_card": {
        "id": 30,
        "term": "Judgment",
        "clues": [
          "Jesus",
          "Punishment",
          "Sin",
          "Heaven",
          "End"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 31,
    "front_text": "King",
    "back_text": "",
    "metadata": {
      "id": 31,
      "contentItemId": "game-bible-talk",
      "sortOrder": 31,
      "pairs": [
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Crown",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "David",
          "right": ""
        },
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 31,
        "term": "King",
        "clues": [
          "Crown",
          "Jesus",
          "David",
          "Solomon",
          "Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 32,
    "front_text": "Sacrifice",
    "back_text": "",
    "metadata": {
      "id": 32,
      "contentItemId": "game-bible-talk",
      "sortOrder": 32,
      "pairs": [
        {
          "left": "Sacrifice",
          "right": ""
        },
        {
          "left": "Temple",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Atonement",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        }
      ],
      "source_card": {
        "id": 32,
        "term": "Sacrifice",
        "clues": [
          "Temple",
          "Animals",
          "Jesus",
          "Atonement",
          "Old Testament"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 33,
    "front_text": "Faith",
    "back_text": "",
    "metadata": {
      "id": 33,
      "contentItemId": "game-bible-talk",
      "sortOrder": 33,
      "pairs": [
        {
          "left": "Faith",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Believe",
          "right": ""
        },
        {
          "left": "Christian",
          "right": ""
        },
        {
          "left": "Saved",
          "right": ""
        }
      ],
      "source_card": {
        "id": 33,
        "term": "Faith",
        "clues": [
          "Jesus",
          "God",
          "Believe",
          "Christian",
          "Saved"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 34,
    "front_text": "Prophet",
    "back_text": "",
    "metadata": {
      "id": 34,
      "contentItemId": "game-bible-talk",
      "sortOrder": 34,
      "pairs": [
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Messenger",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Judges",
          "right": ""
        },
        {
          "left": "Elijah",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 34,
        "term": "Prophet",
        "clues": [
          "Messenger",
          "God",
          "Judges",
          "Elijah",
          "Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 35,
    "front_text": "Obey",
    "back_text": "",
    "metadata": {
      "id": 35,
      "contentItemId": "game-bible-talk",
      "sortOrder": 35,
      "pairs": [
        {
          "left": "Obey",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Parents",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Servant",
          "right": ""
        },
        {
          "left": "Christian",
          "right": ""
        }
      ],
      "source_card": {
        "id": 35,
        "term": "Obey",
        "clues": [
          "God",
          "Parents",
          "Jesus",
          "Servant",
          "Christian"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 36,
    "front_text": "Israel",
    "back_text": "",
    "metadata": {
      "id": 36,
      "contentItemId": "game-bible-talk",
      "sortOrder": 36,
      "pairs": [
        {
          "left": "Israel",
          "right": ""
        },
        {
          "left": "God’s People",
          "right": ""
        },
        {
          "left": "Nation",
          "right": ""
        },
        {
          "left": "Desert",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        },
        {
          "left": "Jacob",
          "right": ""
        }
      ],
      "source_card": {
        "id": 36,
        "term": "Israel",
        "clues": [
          "God’s People",
          "Nation",
          "Desert",
          "Old Testament",
          "Jacob"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 37,
    "front_text": "Esau",
    "back_text": "",
    "metadata": {
      "id": 37,
      "contentItemId": "game-bible-talk",
      "sortOrder": 37,
      "pairs": [
        {
          "left": "Esau",
          "right": ""
        },
        {
          "left": "Jacob",
          "right": ""
        },
        {
          "left": "Twin",
          "right": ""
        },
        {
          "left": "Hairy",
          "right": ""
        },
        {
          "left": "Birthright",
          "right": ""
        },
        {
          "left": "Brother",
          "right": ""
        }
      ],
      "source_card": {
        "id": 37,
        "term": "Esau",
        "clues": [
          "Jacob",
          "Twin",
          "Hairy",
          "Birthright",
          "Brother"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 38,
    "front_text": "Lazarus",
    "back_text": "",
    "metadata": {
      "id": 38,
      "contentItemId": "game-bible-talk",
      "sortOrder": 38,
      "pairs": [
        {
          "left": "Lazarus",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Raised",
          "right": ""
        },
        {
          "left": "Life",
          "right": ""
        },
        {
          "left": "Mary",
          "right": ""
        }
      ],
      "source_card": {
        "id": 38,
        "term": "Lazarus",
        "clues": [
          "Death",
          "Jesus",
          "Raised",
          "Life",
          "Mary"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 39,
    "front_text": "Herod",
    "back_text": "",
    "metadata": {
      "id": 39,
      "contentItemId": "game-bible-talk",
      "sortOrder": 39,
      "pairs": [
        {
          "left": "Herod",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Baby",
          "right": ""
        },
        {
          "left": "Kill",
          "right": ""
        },
        {
          "left": "Hate",
          "right": ""
        }
      ],
      "source_card": {
        "id": 39,
        "term": "Herod",
        "clues": [
          "King",
          "Jesus",
          "Baby",
          "Kill",
          "Hate"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 40,
    "front_text": "Promised Land",
    "back_text": "",
    "metadata": {
      "id": 40,
      "contentItemId": "game-bible-talk",
      "sortOrder": 40,
      "pairs": [
        {
          "left": "Promised Land",
          "right": ""
        },
        {
          "left": "Desert",
          "right": ""
        },
        {
          "left": "Canaan",
          "right": ""
        },
        {
          "left": "Egypt",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        }
      ],
      "source_card": {
        "id": 40,
        "term": "Promised Land",
        "clues": [
          "Desert",
          "Canaan",
          "Egypt",
          "Israelites",
          "Moses"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 41,
    "front_text": "Acts",
    "back_text": "",
    "metadata": {
      "id": 41,
      "contentItemId": "game-bible-talk",
      "sortOrder": 41,
      "pairs": [
        {
          "left": "Acts",
          "right": ""
        },
        {
          "left": "Gospel",
          "right": ""
        },
        {
          "left": "Message",
          "right": ""
        },
        {
          "left": "Paul",
          "right": ""
        },
        {
          "left": "Spread",
          "right": ""
        },
        {
          "left": "Missionary",
          "right": ""
        }
      ],
      "source_card": {
        "id": 41,
        "term": "Acts",
        "clues": [
          "Gospel",
          "Message",
          "Paul",
          "Spread",
          "Missionary"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 42,
    "front_text": "Barabbas",
    "back_text": "",
    "metadata": {
      "id": 42,
      "contentItemId": "game-bible-talk",
      "sortOrder": 42,
      "pairs": [
        {
          "left": "Barabbas",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Prisoner",
          "right": ""
        },
        {
          "left": "Released",
          "right": ""
        },
        {
          "left": "Passover",
          "right": ""
        },
        {
          "left": "Rebellion",
          "right": ""
        }
      ],
      "source_card": {
        "id": 42,
        "term": "Barabbas",
        "clues": [
          "Jesus",
          "Prisoner",
          "Released",
          "Passover",
          "Rebellion"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 43,
    "front_text": "Shepherd",
    "back_text": "",
    "metadata": {
      "id": 43,
      "contentItemId": "game-bible-talk",
      "sortOrder": 43,
      "pairs": [
        {
          "left": "Shepherd",
          "right": ""
        },
        {
          "left": "Sheep",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Follow",
          "right": ""
        },
        {
          "left": "Flock",
          "right": ""
        },
        {
          "left": "Lost",
          "right": ""
        }
      ],
      "source_card": {
        "id": 43,
        "term": "Shepherd",
        "clues": [
          "Sheep",
          "Jesus",
          "Follow",
          "Flock",
          "Lost"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 44,
    "front_text": "Proverbs",
    "back_text": "",
    "metadata": {
      "id": 44,
      "contentItemId": "game-bible-talk",
      "sortOrder": 44,
      "pairs": [
        {
          "left": "Proverbs",
          "right": ""
        },
        {
          "left": "Wise",
          "right": ""
        },
        {
          "left": "Sayings",
          "right": ""
        },
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        }
      ],
      "source_card": {
        "id": 44,
        "term": "Proverbs",
        "clues": [
          "Wise",
          "Sayings",
          "Solomon",
          "Old Testament",
          "Bible"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 45,
    "front_text": "Job",
    "back_text": "",
    "metadata": {
      "id": 45,
      "contentItemId": "game-bible-talk",
      "sortOrder": 45,
      "pairs": [
        {
          "left": "Job",
          "right": ""
        },
        {
          "left": "Righteous",
          "right": ""
        },
        {
          "left": "Satan",
          "right": ""
        },
        {
          "left": "Suffer",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Test",
          "right": ""
        }
      ],
      "source_card": {
        "id": 45,
        "term": "Job",
        "clues": [
          "Righteous",
          "Satan",
          "Suffer",
          "God",
          "Test"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 46,
    "front_text": "Jonah",
    "back_text": "",
    "metadata": {
      "id": 46,
      "contentItemId": "game-bible-talk",
      "sortOrder": 46,
      "pairs": [
        {
          "left": "Jonah",
          "right": ""
        },
        {
          "left": "Whale",
          "right": ""
        },
        {
          "left": "Nineveh",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Message",
          "right": ""
        },
        {
          "left": "Vomit",
          "right": ""
        }
      ],
      "source_card": {
        "id": 46,
        "term": "Jonah",
        "clues": [
          "Whale",
          "Nineveh",
          "God",
          "Message",
          "Vomit"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 47,
    "front_text": "Kyckstart",
    "back_text": "",
    "metadata": {
      "id": 47,
      "contentItemId": "game-bible-talk",
      "sortOrder": 47,
      "pairs": [
        {
          "left": "Kyckstart",
          "right": ""
        },
        {
          "left": "Salt",
          "right": ""
        },
        {
          "left": "Katoomba",
          "right": ""
        },
        {
          "left": "Camp",
          "right": ""
        },
        {
          "left": "Convention",
          "right": ""
        },
        {
          "left": "Talks",
          "right": ""
        }
      ],
      "source_card": {
        "id": 47,
        "term": "Kyckstart",
        "clues": [
          "Salt",
          "Katoomba",
          "Camp",
          "Convention",
          "Talks"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 48,
    "front_text": "Pharisee",
    "back_text": "",
    "metadata": {
      "id": 48,
      "contentItemId": "game-bible-talk",
      "sortOrder": 48,
      "pairs": [
        {
          "left": "Pharisee",
          "right": ""
        },
        {
          "left": "Religious",
          "right": ""
        },
        {
          "left": "Leader",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Hate",
          "right": ""
        },
        {
          "left": "Unbelieving",
          "right": ""
        }
      ],
      "source_card": {
        "id": 48,
        "term": "Pharisee",
        "clues": [
          "Religious",
          "Leader",
          "Jesus",
          "Hate",
          "Unbelieving"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 49,
    "front_text": "Easter",
    "back_text": "",
    "metadata": {
      "id": 49,
      "contentItemId": "game-bible-talk",
      "sortOrder": 49,
      "pairs": [
        {
          "left": "Easter",
          "right": ""
        },
        {
          "left": "The Cross",
          "right": ""
        },
        {
          "left": "Eggs",
          "right": ""
        },
        {
          "left": "Resurrection",
          "right": ""
        },
        {
          "left": "Chocolate",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 49,
        "term": "Easter",
        "clues": [
          "The Cross",
          "Eggs",
          "Resurrection",
          "Chocolate",
          "Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 50,
    "front_text": "Wisdom",
    "back_text": "",
    "metadata": {
      "id": 50,
      "contentItemId": "game-bible-talk",
      "sortOrder": 50,
      "pairs": [
        {
          "left": "Wisdom",
          "right": ""
        },
        {
          "left": "Knowledge",
          "right": ""
        },
        {
          "left": "Wise",
          "right": ""
        },
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Ask",
          "right": ""
        }
      ],
      "source_card": {
        "id": 50,
        "term": "Wisdom",
        "clues": [
          "Knowledge",
          "Wise",
          "Solomon",
          "King",
          "Ask"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 51,
    "front_text": "Family",
    "back_text": "",
    "metadata": {
      "id": 51,
      "contentItemId": "game-bible-talk",
      "sortOrder": 51,
      "pairs": [
        {
          "left": "Family",
          "right": ""
        },
        {
          "left": "Brothers",
          "right": ""
        },
        {
          "left": "Sisters",
          "right": ""
        },
        {
          "left": "Mum",
          "right": ""
        },
        {
          "left": "Dad",
          "right": ""
        },
        {
          "left": "Home",
          "right": ""
        }
      ],
      "source_card": {
        "id": 51,
        "term": "Family",
        "clues": [
          "Brothers",
          "Sisters",
          "Mum",
          "Dad",
          "Home"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 52,
    "front_text": "Christmas",
    "back_text": "",
    "metadata": {
      "id": 52,
      "contentItemId": "game-bible-talk",
      "sortOrder": 52,
      "pairs": [
        {
          "left": "Christmas",
          "right": ""
        },
        {
          "left": "Birth",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Manger",
          "right": ""
        },
        {
          "left": "Star",
          "right": ""
        },
        {
          "left": "Presents",
          "right": ""
        }
      ],
      "source_card": {
        "id": 52,
        "term": "Christmas",
        "clues": [
          "Birth",
          "Jesus",
          "Manger",
          "Star",
          "Presents"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 53,
    "front_text": "Garden of Eden",
    "back_text": "",
    "metadata": {
      "id": 53,
      "contentItemId": "game-bible-talk",
      "sortOrder": 53,
      "pairs": [
        {
          "left": "Garden of Eden",
          "right": ""
        },
        {
          "left": "Plants",
          "right": ""
        },
        {
          "left": "Flowers",
          "right": ""
        },
        {
          "left": "Adam and Eve",
          "right": ""
        },
        {
          "left": "Snake",
          "right": ""
        },
        {
          "left": "Genesis",
          "right": ""
        }
      ],
      "source_card": {
        "id": 53,
        "term": "Garden of Eden",
        "clues": [
          "Plants",
          "Flowers",
          "Adam and Eve",
          "Snake",
          "Genesis"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 54,
    "front_text": "Praise",
    "back_text": "",
    "metadata": {
      "id": 54,
      "contentItemId": "game-bible-talk",
      "sortOrder": 54,
      "pairs": [
        {
          "left": "Praise",
          "right": ""
        },
        {
          "left": "Worship",
          "right": ""
        },
        {
          "left": "Happy",
          "right": ""
        },
        {
          "left": "Joyful",
          "right": ""
        },
        {
          "left": "Sing",
          "right": ""
        },
        {
          "left": "Give",
          "right": ""
        }
      ],
      "source_card": {
        "id": 54,
        "term": "Praise",
        "clues": [
          "Worship",
          "Happy",
          "Joyful",
          "Sing",
          "Give"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 55,
    "front_text": "Temptation",
    "back_text": "",
    "metadata": {
      "id": 55,
      "contentItemId": "game-bible-talk",
      "sortOrder": 55,
      "pairs": [
        {
          "left": "Temptation",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "Evil",
          "right": ""
        },
        {
          "left": "Bad",
          "right": ""
        },
        {
          "left": "Wrong",
          "right": ""
        },
        {
          "left": "Attractive",
          "right": ""
        }
      ],
      "source_card": {
        "id": 55,
        "term": "Temptation",
        "clues": [
          "Sin",
          "Evil",
          "Bad",
          "Wrong",
          "Attractive"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 56,
    "front_text": "Grace",
    "back_text": "",
    "metadata": {
      "id": 56,
      "contentItemId": "game-bible-talk",
      "sortOrder": 56,
      "pairs": [
        {
          "left": "Grace",
          "right": ""
        },
        {
          "left": "Gift",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Cross",
          "right": ""
        },
        {
          "left": "Love",
          "right": ""
        }
      ],
      "source_card": {
        "id": 56,
        "term": "Grace",
        "clues": [
          "Gift",
          "Jesus",
          "God",
          "Cross",
          "Love"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 57,
    "front_text": "Submit",
    "back_text": "",
    "metadata": {
      "id": 57,
      "contentItemId": "game-bible-talk",
      "sortOrder": 57,
      "pairs": [
        {
          "left": "Submit",
          "right": ""
        },
        {
          "left": "Humble",
          "right": ""
        },
        {
          "left": "Accept",
          "right": ""
        },
        {
          "left": "Honor",
          "right": ""
        },
        {
          "left": "Obedient",
          "right": ""
        },
        {
          "left": "Give",
          "right": ""
        }
      ],
      "source_card": {
        "id": 57,
        "term": "Submit",
        "clues": [
          "Humble",
          "Accept",
          "Honor",
          "Obedient",
          "Give"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 58,
    "front_text": "Jericho",
    "back_text": "",
    "metadata": {
      "id": 58,
      "contentItemId": "game-bible-talk",
      "sortOrder": 58,
      "pairs": [
        {
          "left": "Jericho",
          "right": ""
        },
        {
          "left": "Walls",
          "right": ""
        },
        {
          "left": "City",
          "right": ""
        },
        {
          "left": "Destruction",
          "right": ""
        },
        {
          "left": "Marching",
          "right": ""
        },
        {
          "left": "Horns",
          "right": ""
        }
      ],
      "source_card": {
        "id": 58,
        "term": "Jericho",
        "clues": [
          "Walls",
          "City",
          "Destruction",
          "Marching",
          "Horns"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 59,
    "front_text": "Sing",
    "back_text": "",
    "metadata": {
      "id": 59,
      "contentItemId": "game-bible-talk",
      "sortOrder": 59,
      "pairs": [
        {
          "left": "Sing",
          "right": ""
        },
        {
          "left": "Voice",
          "right": ""
        },
        {
          "left": "Music",
          "right": ""
        },
        {
          "left": "Salt",
          "right": ""
        },
        {
          "left": "Words",
          "right": ""
        },
        {
          "left": "Lyrics",
          "right": ""
        }
      ],
      "source_card": {
        "id": 59,
        "term": "Sing",
        "clues": [
          "Voice",
          "Music",
          "Salt",
          "Words",
          "Lyrics"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 60,
    "front_text": "Represent",
    "back_text": "",
    "metadata": {
      "id": 60,
      "contentItemId": "game-bible-talk",
      "sortOrder": 60,
      "pairs": [
        {
          "left": "Represent",
          "right": ""
        },
        {
          "left": "Talk",
          "right": ""
        },
        {
          "left": "Show",
          "right": ""
        },
        {
          "left": "Friends",
          "right": ""
        },
        {
          "left": "Speak",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        }
      ],
      "source_card": {
        "id": 60,
        "term": "Represent",
        "clues": [
          "Talk",
          "Show",
          "Friends",
          "Speak",
          "Bible"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 61,
    "front_text": "Rainbow",
    "back_text": "",
    "metadata": {
      "id": 61,
      "contentItemId": "game-bible-talk",
      "sortOrder": 61,
      "pairs": [
        {
          "left": "Rainbow",
          "right": ""
        },
        {
          "left": "Colours",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Reminder",
          "right": ""
        },
        {
          "left": "Ark",
          "right": ""
        },
        {
          "left": "Rain",
          "right": ""
        }
      ],
      "source_card": {
        "id": 61,
        "term": "Rainbow",
        "clues": [
          "Colours",
          "Moses",
          "Reminder",
          "Ark",
          "Rain"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 62,
    "front_text": "God",
    "back_text": "",
    "metadata": {
      "id": 62,
      "contentItemId": "game-bible-talk",
      "sortOrder": 62,
      "pairs": [
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Creator",
          "right": ""
        },
        {
          "left": "Father",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Powerful",
          "right": ""
        },
        {
          "left": "Hands",
          "right": ""
        }
      ],
      "source_card": {
        "id": 62,
        "term": "God",
        "clues": [
          "Creator",
          "Father",
          "Jesus",
          "Powerful",
          "Hands"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 63,
    "front_text": "Romans",
    "back_text": "",
    "metadata": {
      "id": 63,
      "contentItemId": "game-bible-talk",
      "sortOrder": 63,
      "pairs": [
        {
          "left": "Romans",
          "right": ""
        },
        {
          "left": "New Testament",
          "right": ""
        },
        {
          "left": "Empire",
          "right": ""
        },
        {
          "left": "Caesar",
          "right": ""
        },
        {
          "left": "Paul",
          "right": ""
        },
        {
          "left": "Church",
          "right": ""
        }
      ],
      "source_card": {
        "id": 63,
        "term": "Romans",
        "clues": [
          "New Testament",
          "Empire",
          "Caesar",
          "Paul",
          "Church"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 64,
    "front_text": "Christian",
    "back_text": "",
    "metadata": {
      "id": 64,
      "contentItemId": "game-bible-talk",
      "sortOrder": 64,
      "pairs": [
        {
          "left": "Christian",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Christ",
          "right": ""
        },
        {
          "left": "Follower",
          "right": ""
        },
        {
          "left": "Name",
          "right": ""
        },
        {
          "left": "Religious",
          "right": ""
        }
      ],
      "source_card": {
        "id": 64,
        "term": "Christian",
        "clues": [
          "Jesus",
          "Christ",
          "Follower",
          "Name",
          "Religious"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 65,
    "front_text": "Genesis",
    "back_text": "",
    "metadata": {
      "id": 65,
      "contentItemId": "game-bible-talk",
      "sortOrder": 65,
      "pairs": [
        {
          "left": "Genesis",
          "right": ""
        },
        {
          "left": "Beginning",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Adam and Eve",
          "right": ""
        },
        {
          "left": "Creation",
          "right": ""
        },
        {
          "left": "First",
          "right": ""
        }
      ],
      "source_card": {
        "id": 65,
        "term": "Genesis",
        "clues": [
          "Beginning",
          "Bible",
          "Adam and Eve",
          "Creation",
          "First"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 66,
    "front_text": "Idols",
    "back_text": "",
    "metadata": {
      "id": 66,
      "contentItemId": "game-bible-talk",
      "sortOrder": 66,
      "pairs": [
        {
          "left": "Idols",
          "right": ""
        },
        {
          "left": "Gods",
          "right": ""
        },
        {
          "left": "False",
          "right": ""
        },
        {
          "left": "Gold",
          "right": ""
        },
        {
          "left": "Worship",
          "right": ""
        },
        {
          "left": "Calf",
          "right": ""
        }
      ],
      "source_card": {
        "id": 66,
        "term": "Idols",
        "clues": [
          "Gods",
          "False",
          "Gold",
          "Worship",
          "Calf"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 67,
    "front_text": "Seek",
    "back_text": "",
    "metadata": {
      "id": 67,
      "contentItemId": "game-bible-talk",
      "sortOrder": 67,
      "pairs": [
        {
          "left": "Seek",
          "right": ""
        },
        {
          "left": "Look",
          "right": ""
        },
        {
          "left": "Find",
          "right": ""
        },
        {
          "left": "Search",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Lost",
          "right": ""
        }
      ],
      "source_card": {
        "id": 67,
        "term": "Seek",
        "clues": [
          "Look",
          "Find",
          "Search",
          "God",
          "Lost"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 68,
    "front_text": "Abraham",
    "back_text": "",
    "metadata": {
      "id": 68,
      "contentItemId": "game-bible-talk",
      "sortOrder": 68,
      "pairs": [
        {
          "left": "Abraham",
          "right": ""
        },
        {
          "left": "Father",
          "right": ""
        },
        {
          "left": "Nations",
          "right": ""
        },
        {
          "left": "Covenant",
          "right": ""
        },
        {
          "left": "Abram",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        }
      ],
      "source_card": {
        "id": 68,
        "term": "Abraham",
        "clues": [
          "Father",
          "Nations",
          "Covenant",
          "Abram",
          "Old Testament"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 69,
    "front_text": "Visions",
    "back_text": "",
    "metadata": {
      "id": 69,
      "contentItemId": "game-bible-talk",
      "sortOrder": 69,
      "pairs": [
        {
          "left": "Visions",
          "right": ""
        },
        {
          "left": "Dreams",
          "right": ""
        },
        {
          "left": "Prophecy",
          "right": ""
        },
        {
          "left": "Messages",
          "right": ""
        },
        {
          "left": "Future",
          "right": ""
        },
        {
          "left": "Zechariah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 69,
        "term": "Visions",
        "clues": [
          "Dreams",
          "Prophecy",
          "Messages",
          "Future",
          "Zechariah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 70,
    "front_text": "Manna",
    "back_text": "",
    "metadata": {
      "id": 70,
      "contentItemId": "game-bible-talk",
      "sortOrder": 70,
      "pairs": [
        {
          "left": "Manna",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        },
        {
          "left": "Promised Land",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Bread",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        }
      ],
      "source_card": {
        "id": 70,
        "term": "Manna",
        "clues": [
          "Old Testament",
          "Promised Land",
          "Moses",
          "Bread",
          "Israelites"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 71,
    "front_text": "Matthew",
    "back_text": "",
    "metadata": {
      "id": 71,
      "contentItemId": "game-bible-talk",
      "sortOrder": 71,
      "pairs": [
        {
          "left": "Matthew",
          "right": ""
        },
        {
          "left": "Tax Collector",
          "right": ""
        },
        {
          "left": "Disciple",
          "right": ""
        },
        {
          "left": "New Testament",
          "right": ""
        },
        {
          "left": "Gospel",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        }
      ],
      "source_card": {
        "id": 71,
        "term": "Matthew",
        "clues": [
          "Tax Collector",
          "Disciple",
          "New Testament",
          "Gospel",
          "Bible"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 72,
    "front_text": "Desert",
    "back_text": "",
    "metadata": {
      "id": 72,
      "contentItemId": "game-bible-talk",
      "sortOrder": 72,
      "pairs": [
        {
          "left": "Desert",
          "right": ""
        },
        {
          "left": "Hot",
          "right": ""
        },
        {
          "left": "Sand",
          "right": ""
        },
        {
          "left": "Water",
          "right": ""
        },
        {
          "left": "Egypt",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        }
      ],
      "source_card": {
        "id": 72,
        "term": "Desert",
        "clues": [
          "Hot",
          "Sand",
          "Water",
          "Egypt",
          "Israelites"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 73,
    "front_text": "Sacrifice",
    "back_text": "",
    "metadata": {
      "id": 73,
      "contentItemId": "game-bible-talk",
      "sortOrder": 73,
      "pairs": [
        {
          "left": "Sacrifice",
          "right": ""
        },
        {
          "left": "Atonement",
          "right": ""
        },
        {
          "left": "Cleansed",
          "right": ""
        },
        {
          "left": "Blood",
          "right": ""
        },
        {
          "left": "Cross",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 73,
        "term": "Sacrifice",
        "clues": [
          "Atonement",
          "Cleansed",
          "Blood",
          "Cross",
          "Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 74,
    "front_text": "Church",
    "back_text": "",
    "metadata": {
      "id": 74,
      "contentItemId": "game-bible-talk",
      "sortOrder": 74,
      "pairs": [
        {
          "left": "Church",
          "right": ""
        },
        {
          "left": "Building",
          "right": ""
        },
        {
          "left": "People",
          "right": ""
        },
        {
          "left": "Service",
          "right": ""
        },
        {
          "left": "Christians",
          "right": ""
        },
        {
          "left": "Sermon",
          "right": ""
        }
      ],
      "source_card": {
        "id": 74,
        "term": "Church",
        "clues": [
          "Building",
          "People",
          "Service",
          "Christians",
          "Sermon"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 75,
    "front_text": "Manger",
    "back_text": "",
    "metadata": {
      "id": 75,
      "contentItemId": "game-bible-talk",
      "sortOrder": 75,
      "pairs": [
        {
          "left": "Manger",
          "right": ""
        },
        {
          "left": "Baby",
          "right": ""
        },
        {
          "left": "Bethlehem",
          "right": ""
        },
        {
          "left": "Christmas",
          "right": ""
        },
        {
          "left": "Kings",
          "right": ""
        },
        {
          "left": "Savior",
          "right": ""
        }
      ],
      "source_card": {
        "id": 75,
        "term": "Manger",
        "clues": [
          "Baby",
          "Bethlehem",
          "Christmas",
          "Kings",
          "Savior"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 76,
    "front_text": "Covenant",
    "back_text": "",
    "metadata": {
      "id": 76,
      "contentItemId": "game-bible-talk",
      "sortOrder": 76,
      "pairs": [
        {
          "left": "Covenant",
          "right": ""
        },
        {
          "left": "Promise",
          "right": ""
        },
        {
          "left": "Abraham",
          "right": ""
        },
        {
          "left": "Commitment",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Agreement",
          "right": ""
        }
      ],
      "source_card": {
        "id": 76,
        "term": "Covenant",
        "clues": [
          "Promise",
          "Abraham",
          "Commitment",
          "God",
          "Agreement"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 77,
    "front_text": "Memory Verse",
    "back_text": "",
    "metadata": {
      "id": 77,
      "contentItemId": "game-bible-talk",
      "sortOrder": 77,
      "pairs": [
        {
          "left": "Memory Verse",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Salt",
          "right": ""
        },
        {
          "left": "Learn",
          "right": ""
        },
        {
          "left": "Reminder",
          "right": ""
        },
        {
          "left": "Help",
          "right": ""
        }
      ],
      "source_card": {
        "id": 77,
        "term": "Memory Verse",
        "clues": [
          "Bible",
          "Salt",
          "Learn",
          "Reminder",
          "Help"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 78,
    "front_text": "Noah's Arc",
    "back_text": "",
    "metadata": {
      "id": 78,
      "contentItemId": "game-bible-talk",
      "sortOrder": 78,
      "pairs": [
        {
          "left": "Noah's Arc",
          "right": ""
        },
        {
          "left": "Noah",
          "right": ""
        },
        {
          "left": "Flood",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Wood",
          "right": ""
        },
        {
          "left": "Transportation",
          "right": ""
        }
      ],
      "source_card": {
        "id": 78,
        "term": "Noah's Arc",
        "clues": [
          "Noah",
          "Flood",
          "Animals",
          "Wood",
          "Transportation"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 79,
    "front_text": "Jacob",
    "back_text": "",
    "metadata": {
      "id": 79,
      "contentItemId": "game-bible-talk",
      "sortOrder": 79,
      "pairs": [
        {
          "left": "Jacob",
          "right": ""
        },
        {
          "left": "Esau",
          "right": ""
        },
        {
          "left": "Abraham",
          "right": ""
        },
        {
          "left": "Old Testament",
          "right": ""
        },
        {
          "left": "Rachel",
          "right": ""
        },
        {
          "left": "7 Years",
          "right": ""
        }
      ],
      "source_card": {
        "id": 79,
        "term": "Jacob",
        "clues": [
          "Esau",
          "Abraham",
          "Old Testament",
          "Rachel",
          "7 Years"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 80,
    "front_text": "Prayer Book",
    "back_text": "",
    "metadata": {
      "id": 80,
      "contentItemId": "game-bible-talk",
      "sortOrder": 80,
      "pairs": [
        {
          "left": "Prayer Book",
          "right": ""
        },
        {
          "left": "Church",
          "right": ""
        },
        {
          "left": "Example",
          "right": ""
        },
        {
          "left": "Minister",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Traditional",
          "right": ""
        }
      ],
      "source_card": {
        "id": 80,
        "term": "Prayer Book",
        "clues": [
          "Church",
          "Example",
          "Minister",
          "Book",
          "Traditional"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 81,
    "front_text": "Judah",
    "back_text": "",
    "metadata": {
      "id": 81,
      "contentItemId": "game-bible-talk",
      "sortOrder": 81,
      "pairs": [
        {
          "left": "Judah",
          "right": ""
        },
        {
          "left": "Place",
          "right": ""
        },
        {
          "left": "Jacob",
          "right": ""
        },
        {
          "left": "Lion",
          "right": ""
        },
        {
          "left": "Tribe",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 81,
        "term": "Judah",
        "clues": [
          "Place",
          "Jacob",
          "Lion",
          "Tribe",
          "Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 82,
    "front_text": "Wedding",
    "back_text": "",
    "metadata": {
      "id": 82,
      "contentItemId": "game-bible-talk",
      "sortOrder": 82,
      "pairs": [
        {
          "left": "Wedding",
          "right": ""
        },
        {
          "left": "Marriage",
          "right": ""
        },
        {
          "left": "Husband",
          "right": ""
        },
        {
          "left": "Wife",
          "right": ""
        },
        {
          "left": "Dress",
          "right": ""
        },
        {
          "left": "Wine",
          "right": ""
        }
      ],
      "source_card": {
        "id": 82,
        "term": "Wedding",
        "clues": [
          "Marriage",
          "Husband",
          "Wife",
          "Dress",
          "Wine"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 83,
    "front_text": "Salt October",
    "back_text": "",
    "metadata": {
      "id": 83,
      "contentItemId": "game-bible-talk",
      "sortOrder": 83,
      "pairs": [
        {
          "left": "Salt October",
          "right": ""
        },
        {
          "left": "Camp",
          "right": ""
        },
        {
          "left": "Away",
          "right": ""
        },
        {
          "left": "Together",
          "right": ""
        },
        {
          "left": "Fun",
          "right": ""
        },
        {
          "left": "Talks",
          "right": ""
        },
        {
          "left": "Socks",
          "right": ""
        }
      ],
      "source_card": {
        "id": 83,
        "term": "Salt October",
        "clues": [
          "Camp",
          "Away",
          "Together",
          "Fun",
          "Talks",
          "Socks"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 84,
    "front_text": "Pharaoh",
    "back_text": "",
    "metadata": {
      "id": 84,
      "contentItemId": "game-bible-talk",
      "sortOrder": 84,
      "pairs": [
        {
          "left": "Pharaoh",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Ruler",
          "right": ""
        },
        {
          "left": "Joseph",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Leader",
          "right": ""
        }
      ],
      "source_card": {
        "id": 84,
        "term": "Pharaoh",
        "clues": [
          "King",
          "Ruler",
          "Joseph",
          "Moses",
          "Leader"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 85,
    "front_text": "Sarah",
    "back_text": "",
    "metadata": {
      "id": 85,
      "contentItemId": "game-bible-talk",
      "sortOrder": 85,
      "pairs": [
        {
          "left": "Sarah",
          "right": ""
        },
        {
          "left": "Mother",
          "right": ""
        },
        {
          "left": "Genesis",
          "right": ""
        },
        {
          "left": "Abraham",
          "right": ""
        },
        {
          "left": "Barren",
          "right": ""
        },
        {
          "left": "Isaac",
          "right": ""
        }
      ],
      "source_card": {
        "id": 85,
        "term": "Sarah",
        "clues": [
          "Mother",
          "Genesis",
          "Abraham",
          "Barren",
          "Isaac"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 86,
    "front_text": "Temple",
    "back_text": "",
    "metadata": {
      "id": 86,
      "contentItemId": "game-bible-talk",
      "sortOrder": 86,
      "pairs": [
        {
          "left": "Temple",
          "right": ""
        },
        {
          "left": "Worship",
          "right": ""
        },
        {
          "left": "Building",
          "right": ""
        },
        {
          "left": "Body",
          "right": ""
        },
        {
          "left": "House of God.",
          "right": ""
        },
        {
          "left": "Prayer",
          "right": ""
        }
      ],
      "source_card": {
        "id": 86,
        "term": "Temple",
        "clues": [
          "Worship",
          "Building",
          "Body",
          "House of God.",
          "Prayer"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 87,
    "front_text": "Gabriel",
    "back_text": "",
    "metadata": {
      "id": 87,
      "contentItemId": "game-bible-talk",
      "sortOrder": 87,
      "pairs": [
        {
          "left": "Gabriel",
          "right": ""
        },
        {
          "left": "Messenger",
          "right": ""
        },
        {
          "left": "Angel",
          "right": ""
        },
        {
          "left": "Mary",
          "right": ""
        },
        {
          "left": "Daniel",
          "right": ""
        },
        {
          "left": "Wings",
          "right": ""
        }
      ],
      "source_card": {
        "id": 87,
        "term": "Gabriel",
        "clues": [
          "Messenger",
          "Angel",
          "Mary",
          "Daniel",
          "Wings"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 88,
    "front_text": "Joshua",
    "back_text": "",
    "metadata": {
      "id": 88,
      "contentItemId": "game-bible-talk",
      "sortOrder": 88,
      "pairs": [
        {
          "left": "Joshua",
          "right": ""
        },
        {
          "left": "Leader",
          "right": ""
        },
        {
          "left": "Promise Land",
          "right": ""
        },
        {
          "left": "Son of Nun",
          "right": ""
        },
        {
          "left": "Aid of Moses",
          "right": ""
        },
        {
          "left": "Jericho walls",
          "right": ""
        }
      ],
      "source_card": {
        "id": 88,
        "term": "Joshua",
        "clues": [
          "Leader",
          "Promise Land",
          "Son of Nun",
          "Aid of Moses",
          "Jericho walls"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 89,
    "front_text": "Ten Commandments",
    "back_text": "",
    "metadata": {
      "id": 89,
      "contentItemId": "game-bible-talk",
      "sortOrder": 89,
      "pairs": [
        {
          "left": "Ten Commandments",
          "right": ""
        },
        {
          "left": "Laws",
          "right": ""
        },
        {
          "left": "Number",
          "right": ""
        },
        {
          "left": "Rules and Regulations",
          "right": ""
        },
        {
          "left": "Stone tablets",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        }
      ],
      "source_card": {
        "id": 89,
        "term": "Ten Commandments",
        "clues": [
          "Laws",
          "Number",
          "Rules and Regulations",
          "Stone tablets",
          "Moses"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 90,
    "front_text": "Blood",
    "back_text": "",
    "metadata": {
      "id": 90,
      "contentItemId": "game-bible-talk",
      "sortOrder": 90,
      "pairs": [
        {
          "left": "Blood",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Red in color.",
          "right": ""
        },
        {
          "left": "Skin",
          "right": ""
        },
        {
          "left": "Platelets",
          "right": ""
        },
        {
          "left": "lamb",
          "right": ""
        }
      ],
      "source_card": {
        "id": 90,
        "term": "Blood",
        "clues": [
          "Jesus",
          "Red in color.",
          "Skin",
          "Platelets",
          "lamb"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 91,
    "front_text": "Samson",
    "back_text": "",
    "metadata": {
      "id": 91,
      "contentItemId": "game-bible-talk",
      "sortOrder": 91,
      "pairs": [
        {
          "left": "Samson",
          "right": ""
        },
        {
          "left": "Hair",
          "right": ""
        },
        {
          "left": "Delilah",
          "right": ""
        },
        {
          "left": "Strong",
          "right": ""
        },
        {
          "left": "Judge",
          "right": ""
        },
        {
          "left": "Palestine",
          "right": ""
        }
      ],
      "source_card": {
        "id": 91,
        "term": "Samson",
        "clues": [
          "Hair",
          "Delilah",
          "Strong",
          "Judge",
          "Palestine"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 92,
    "front_text": "Savior",
    "back_text": "",
    "metadata": {
      "id": 92,
      "contentItemId": "game-bible-talk",
      "sortOrder": 92,
      "pairs": [
        {
          "left": "Savior",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Redeemer",
          "right": ""
        },
        {
          "left": "Life",
          "right": ""
        },
        {
          "left": "Help",
          "right": ""
        },
        {
          "left": "Savings",
          "right": ""
        }
      ],
      "source_card": {
        "id": 92,
        "term": "Savior",
        "clues": [
          "Jesus",
          "Redeemer",
          "Life",
          "Help",
          "Savings"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 93,
    "front_text": "Lamb",
    "back_text": "",
    "metadata": {
      "id": 93,
      "contentItemId": "game-bible-talk",
      "sortOrder": 93,
      "pairs": [
        {
          "left": "Lamb",
          "right": ""
        },
        {
          "left": "Sacrifice",
          "right": ""
        },
        {
          "left": "Offering",
          "right": ""
        },
        {
          "left": "Lamb of God.",
          "right": ""
        },
        {
          "left": "Holy",
          "right": ""
        },
        {
          "left": "Pure",
          "right": ""
        }
      ],
      "source_card": {
        "id": 93,
        "term": "Lamb",
        "clues": [
          "Sacrifice",
          "Offering",
          "Lamb of God.",
          "Holy",
          "Pure"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 94,
    "front_text": "Delilah",
    "back_text": "",
    "metadata": {
      "id": 94,
      "contentItemId": "game-bible-talk",
      "sortOrder": 94,
      "pairs": [
        {
          "left": "Delilah",
          "right": ""
        },
        {
          "left": "Beautiful",
          "right": ""
        },
        {
          "left": "Samson",
          "right": ""
        },
        {
          "left": "Book of judges",
          "right": ""
        },
        {
          "left": "Temptresses.",
          "right": ""
        },
        {
          "left": "Valley of Sorek",
          "right": ""
        }
      ],
      "source_card": {
        "id": 94,
        "term": "Delilah",
        "clues": [
          "Beautiful",
          "Samson",
          "Book of judges",
          "Temptresses.",
          "Valley of Sorek"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 95,
    "front_text": "Angels",
    "back_text": "",
    "metadata": {
      "id": 95,
      "contentItemId": "game-bible-talk",
      "sortOrder": 95,
      "pairs": [
        {
          "left": "Angels",
          "right": ""
        },
        {
          "left": "Wings",
          "right": ""
        },
        {
          "left": "Creatures",
          "right": ""
        },
        {
          "left": "Cupid.",
          "right": ""
        },
        {
          "left": "Messenger",
          "right": ""
        },
        {
          "left": "Fly",
          "right": ""
        }
      ],
      "source_card": {
        "id": 95,
        "term": "Angels",
        "clues": [
          "Wings",
          "Creatures",
          "Cupid.",
          "Messenger",
          "Fly"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 96,
    "front_text": "Sword",
    "back_text": "",
    "metadata": {
      "id": 96,
      "contentItemId": "game-bible-talk",
      "sortOrder": 96,
      "pairs": [
        {
          "left": "Sword",
          "right": ""
        },
        {
          "left": "Word of God.",
          "right": ""
        },
        {
          "left": "Blade",
          "right": ""
        },
        {
          "left": "Weapon",
          "right": ""
        },
        {
          "left": "Sharp",
          "right": ""
        },
        {
          "left": "Cut",
          "right": ""
        }
      ],
      "source_card": {
        "id": 96,
        "term": "Sword",
        "clues": [
          "Word of God.",
          "Blade",
          "Weapon",
          "Sharp",
          "Cut"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 97,
    "front_text": "Eden",
    "back_text": "",
    "metadata": {
      "id": 97,
      "contentItemId": "game-bible-talk",
      "sortOrder": 97,
      "pairs": [
        {
          "left": "Eden",
          "right": ""
        },
        {
          "left": "Garden",
          "right": ""
        },
        {
          "left": "Life",
          "right": ""
        },
        {
          "left": "Adam and eve",
          "right": ""
        },
        {
          "left": "Place",
          "right": ""
        },
        {
          "left": "Genesis",
          "right": ""
        }
      ],
      "source_card": {
        "id": 97,
        "term": "Eden",
        "clues": [
          "Garden",
          "Life",
          "Adam and eve",
          "Place",
          "Genesis"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 98,
    "front_text": "Elisha",
    "back_text": "",
    "metadata": {
      "id": 98,
      "contentItemId": "game-bible-talk",
      "sortOrder": 98,
      "pairs": [
        {
          "left": "Elisha",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Bald head",
          "right": ""
        },
        {
          "left": "Gehazi",
          "right": ""
        },
        {
          "left": "Elijah",
          "right": ""
        },
        {
          "left": "Baal",
          "right": ""
        }
      ],
      "source_card": {
        "id": 98,
        "term": "Elisha",
        "clues": [
          "Prophet",
          "Bald head",
          "Gehazi",
          "Elijah",
          "Baal"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 99,
    "front_text": "Proverbs",
    "back_text": "",
    "metadata": {
      "id": 99,
      "contentItemId": "game-bible-talk",
      "sortOrder": 99,
      "pairs": [
        {
          "left": "Proverbs",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Quotes",
          "right": ""
        },
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "Wisdom",
          "right": ""
        },
        {
          "left": "Knowledge",
          "right": ""
        }
      ],
      "source_card": {
        "id": 99,
        "term": "Proverbs",
        "clues": [
          "Book",
          "Quotes",
          "Solomon",
          "Wisdom",
          "Knowledge"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 100,
    "front_text": "Sacrifice",
    "back_text": "",
    "metadata": {
      "id": 100,
      "contentItemId": "game-bible-talk",
      "sortOrder": 100,
      "pairs": [
        {
          "left": "Sacrifice",
          "right": ""
        },
        {
          "left": "Offering",
          "right": ""
        },
        {
          "left": "Giving",
          "right": ""
        },
        {
          "left": "Altar",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Foods",
          "right": ""
        }
      ],
      "source_card": {
        "id": 100,
        "term": "Sacrifice",
        "clues": [
          "Offering",
          "Giving",
          "Altar",
          "Animals",
          "Foods"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 101,
    "front_text": "Elijah",
    "back_text": "",
    "metadata": {
      "id": 101,
      "contentItemId": "game-bible-talk",
      "sortOrder": 101,
      "pairs": [
        {
          "left": "Elijah",
          "right": ""
        },
        {
          "left": "Elisha",
          "right": ""
        },
        {
          "left": "Jezebel",
          "right": ""
        },
        {
          "left": "Chariots of fire",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Baal",
          "right": ""
        }
      ],
      "source_card": {
        "id": 101,
        "term": "Elijah",
        "clues": [
          "Elisha",
          "Jezebel",
          "Chariots of fire",
          "Prophet",
          "Baal"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 102,
    "front_text": "Psalms",
    "back_text": "",
    "metadata": {
      "id": 102,
      "contentItemId": "game-bible-talk",
      "sortOrder": 102,
      "pairs": [
        {
          "left": "Psalms",
          "right": ""
        },
        {
          "left": "Songs",
          "right": ""
        },
        {
          "left": "Hymns",
          "right": ""
        },
        {
          "left": "David",
          "right": ""
        },
        {
          "left": "Worship",
          "right": ""
        },
        {
          "left": "Knowledge",
          "right": ""
        }
      ],
      "source_card": {
        "id": 102,
        "term": "Psalms",
        "clues": [
          "Songs",
          "Hymns",
          "David",
          "Worship",
          "Knowledge"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 103,
    "front_text": "Samuel",
    "back_text": "",
    "metadata": {
      "id": 103,
      "contentItemId": "game-bible-talk",
      "sortOrder": 103,
      "pairs": [
        {
          "left": "Samuel",
          "right": ""
        },
        {
          "left": "Boy prophet",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Seer",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        }
      ],
      "source_card": {
        "id": 103,
        "term": "Samuel",
        "clues": [
          "Boy prophet",
          "Book",
          "Seer",
          "Israel",
          "Priest"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 104,
    "front_text": "Naaman",
    "back_text": "",
    "metadata": {
      "id": 104,
      "contentItemId": "game-bible-talk",
      "sortOrder": 104,
      "pairs": [
        {
          "left": "Naaman",
          "right": ""
        },
        {
          "left": "Leprosy",
          "right": ""
        },
        {
          "left": "Jordan River",
          "right": ""
        },
        {
          "left": "Commander",
          "right": ""
        },
        {
          "left": "Elisha",
          "right": ""
        },
        {
          "left": "Book of Kings",
          "right": ""
        }
      ],
      "source_card": {
        "id": 104,
        "term": "Naaman",
        "clues": [
          "Leprosy",
          "Jordan River",
          "Commander",
          "Elisha",
          "Book of Kings"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 105,
    "front_text": "Isaiah",
    "back_text": "",
    "metadata": {
      "id": 105,
      "contentItemId": "game-bible-talk",
      "sortOrder": 105,
      "pairs": [
        {
          "left": "Isaiah",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Amos",
          "right": ""
        },
        {
          "left": "Prophesy",
          "right": ""
        },
        {
          "left": "Coal",
          "right": ""
        }
      ],
      "source_card": {
        "id": 105,
        "term": "Isaiah",
        "clues": [
          "Prophet",
          "Book",
          "Amos",
          "Prophesy",
          "Coal"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 106,
    "front_text": "Bathsheba",
    "back_text": "",
    "metadata": {
      "id": 106,
      "contentItemId": "game-bible-talk",
      "sortOrder": 106,
      "pairs": [
        {
          "left": "Bathsheba",
          "right": ""
        },
        {
          "left": "David",
          "right": ""
        },
        {
          "left": "Uriah",
          "right": ""
        },
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "Adultery",
          "right": ""
        },
        {
          "left": "Beautiful",
          "right": ""
        }
      ],
      "source_card": {
        "id": 106,
        "term": "Bathsheba",
        "clues": [
          "David",
          "Uriah",
          "Solomon",
          "Adultery",
          "Beautiful"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 107,
    "front_text": "Balaam",
    "back_text": "",
    "metadata": {
      "id": 107,
      "contentItemId": "game-bible-talk",
      "sortOrder": 107,
      "pairs": [
        {
          "left": "Balaam",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Diviner",
          "right": ""
        },
        {
          "left": "Book of Numbers",
          "right": ""
        },
        {
          "left": "Balak",
          "right": ""
        },
        {
          "left": "Donkey",
          "right": ""
        }
      ],
      "source_card": {
        "id": 107,
        "term": "Balaam",
        "clues": [
          "Prophet",
          "Diviner",
          "Book of Numbers",
          "Balak",
          "Donkey"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 108,
    "front_text": "Jeremiah",
    "back_text": "",
    "metadata": {
      "id": 108,
      "contentItemId": "game-bible-talk",
      "sortOrder": 108,
      "pairs": [
        {
          "left": "Jeremiah",
          "right": ""
        },
        {
          "left": "Weeping prophet",
          "right": ""
        },
        {
          "left": "Child.",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Lamentations",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        }
      ],
      "source_card": {
        "id": 108,
        "term": "Jeremiah",
        "clues": [
          "Weeping prophet",
          "Child.",
          "Book",
          "Lamentations",
          "Bible"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 109,
    "front_text": "Ezekiel",
    "back_text": "",
    "metadata": {
      "id": 109,
      "contentItemId": "game-bible-talk",
      "sortOrder": 109,
      "pairs": [
        {
          "left": "Ezekiel",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Dry Bones",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        },
        {
          "left": "Major Prophet",
          "right": ""
        }
      ],
      "source_card": {
        "id": 109,
        "term": "Ezekiel",
        "clues": [
          "Prophet",
          "Book",
          "Dry Bones",
          "Priest",
          "Major Prophet"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 110,
    "front_text": "Ezra",
    "back_text": "",
    "metadata": {
      "id": 110,
      "contentItemId": "game-bible-talk",
      "sortOrder": 110,
      "pairs": [
        {
          "left": "Ezra",
          "right": ""
        },
        {
          "left": "Jew",
          "right": ""
        },
        {
          "left": "Priest.",
          "right": ""
        },
        {
          "left": "Scribe",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Person",
          "right": ""
        }
      ],
      "source_card": {
        "id": 110,
        "term": "Ezra",
        "clues": [
          "Jew",
          "Priest.",
          "Scribe",
          "Book",
          "Person"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 111,
    "front_text": "Nazareth",
    "back_text": "",
    "metadata": {
      "id": 111,
      "contentItemId": "game-bible-talk",
      "sortOrder": 111,
      "pairs": [
        {
          "left": "Nazareth",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Joseph",
          "right": ""
        },
        {
          "left": "Mary",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        },
        {
          "left": "Arab Capital",
          "right": ""
        }
      ],
      "source_card": {
        "id": 111,
        "term": "Nazareth",
        "clues": [
          "Jesus",
          "Joseph",
          "Mary",
          "Israel",
          "Arab Capital"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 112,
    "front_text": "Tithes",
    "back_text": "",
    "metadata": {
      "id": 112,
      "contentItemId": "game-bible-talk",
      "sortOrder": 112,
      "pairs": [
        {
          "left": "Tithes",
          "right": ""
        },
        {
          "left": "10 %",
          "right": ""
        },
        {
          "left": "Income",
          "right": ""
        },
        {
          "left": "Giving",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        },
        {
          "left": "Money",
          "right": ""
        }
      ],
      "source_card": {
        "id": 112,
        "term": "Tithes",
        "clues": [
          "10 %",
          "Income",
          "Giving",
          "Priest",
          "Money"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 113,
    "front_text": "Nehemiah",
    "back_text": "",
    "metadata": {
      "id": 113,
      "contentItemId": "game-bible-talk",
      "sortOrder": 113,
      "pairs": [
        {
          "left": "Nehemiah",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Royal cup-bearer",
          "right": ""
        },
        {
          "left": "King Artaxerxes",
          "right": ""
        },
        {
          "left": "Jerusalem",
          "right": ""
        },
        {
          "left": "Governor",
          "right": ""
        }
      ],
      "source_card": {
        "id": 113,
        "term": "Nehemiah",
        "clues": [
          "Book",
          "Royal cup-bearer",
          "King Artaxerxes",
          "Jerusalem",
          "Governor"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 114,
    "front_text": "Pontious Pilate",
    "back_text": "",
    "metadata": {
      "id": 114,
      "contentItemId": "game-bible-talk",
      "sortOrder": 114,
      "pairs": [
        {
          "left": "Pontious Pilate",
          "right": ""
        },
        {
          "left": "Ruler",
          "right": ""
        },
        {
          "left": "Crucifixion",
          "right": ""
        },
        {
          "left": "Judge",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Trial",
          "right": ""
        }
      ],
      "source_card": {
        "id": 114,
        "term": "Pontious Pilate",
        "clues": [
          "Ruler",
          "Crucifixion",
          "Judge",
          "Jesus",
          "Trial"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 115,
    "front_text": "Bible",
    "back_text": "",
    "metadata": {
      "id": 115,
      "contentItemId": "game-bible-talk",
      "sortOrder": 115,
      "pairs": [
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Scriptures",
          "right": ""
        },
        {
          "left": "Word of God.",
          "right": ""
        },
        {
          "left": "Writings.",
          "right": ""
        },
        {
          "left": "Compilation",
          "right": ""
        }
      ],
      "source_card": {
        "id": 115,
        "term": "Bible",
        "clues": [
          "Book",
          "Scriptures",
          "Word of God.",
          "Writings.",
          "Compilation"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 116,
    "front_text": "Job",
    "back_text": "",
    "metadata": {
      "id": 116,
      "contentItemId": "game-bible-talk",
      "sortOrder": 116,
      "pairs": [
        {
          "left": "Job",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        },
        {
          "left": "Blameless",
          "right": ""
        },
        {
          "left": "Perseverance Massacre",
          "right": ""
        },
        {
          "left": "Gentile",
          "right": ""
        },
        {
          "left": "Faithful to God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 116,
        "term": "Job",
        "clues": [
          "Book",
          "Blameless",
          "Perseverance Massacre",
          "Gentile",
          "Faithful to God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 117,
    "front_text": "Herod",
    "back_text": "",
    "metadata": {
      "id": 117,
      "contentItemId": "game-bible-talk",
      "sortOrder": 117,
      "pairs": [
        {
          "left": "Herod",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Herodias",
          "right": ""
        },
        {
          "left": "of the Innocents",
          "right": ""
        },
        {
          "left": "Adulte",
          "right": ""
        },
        {
          "left": "Roman",
          "right": ""
        }
      ],
      "source_card": {
        "id": 117,
        "term": "Herod",
        "clues": [
          "King",
          "Herodias",
          "of the Innocents",
          "Adulte",
          "Roman"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 118,
    "front_text": "Naomi",
    "back_text": "",
    "metadata": {
      "id": 118,
      "contentItemId": "game-bible-talk",
      "sortOrder": 118,
      "pairs": [
        {
          "left": "Naomi",
          "right": ""
        },
        {
          "left": "Ruth",
          "right": ""
        },
        {
          "left": "Mara",
          "right": ""
        },
        {
          "left": "Elimelech",
          "right": ""
        },
        {
          "left": "Mother-in-law",
          "right": ""
        },
        {
          "left": "Two sons",
          "right": ""
        }
      ],
      "source_card": {
        "id": 118,
        "term": "Naomi",
        "clues": [
          "Ruth",
          "Mara",
          "Elimelech",
          "Mother-in-law",
          "Two sons"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 119,
    "front_text": "Jerusalem",
    "back_text": "",
    "metadata": {
      "id": 119,
      "contentItemId": "game-bible-talk",
      "sortOrder": 119,
      "pairs": [
        {
          "left": "Jerusalem",
          "right": ""
        },
        {
          "left": "Place",
          "right": ""
        },
        {
          "left": "Holy City",
          "right": ""
        },
        {
          "left": "City of God",
          "right": ""
        },
        {
          "left": "Israel",
          "right": ""
        },
        {
          "left": "Capital",
          "right": ""
        }
      ],
      "source_card": {
        "id": 119,
        "term": "Jerusalem",
        "clues": [
          "Place",
          "Holy City",
          "City of God",
          "Israel",
          "Capital"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 120,
    "front_text": "Jonah",
    "back_text": "",
    "metadata": {
      "id": 120,
      "contentItemId": "game-bible-talk",
      "sortOrder": 120,
      "pairs": [
        {
          "left": "Jonah",
          "right": ""
        },
        {
          "left": "Big Fish",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Nineveh",
          "right": ""
        },
        {
          "left": "Storm",
          "right": ""
        },
        {
          "left": "Book",
          "right": ""
        }
      ],
      "source_card": {
        "id": 120,
        "term": "Jonah",
        "clues": [
          "Big Fish",
          "Prophet",
          "Nineveh",
          "Storm",
          "Book"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 121,
    "front_text": "Zacchaeus",
    "back_text": "",
    "metadata": {
      "id": 121,
      "contentItemId": "game-bible-talk",
      "sortOrder": 121,
      "pairs": [
        {
          "left": "Zacchaeus",
          "right": ""
        },
        {
          "left": "Tax Collector",
          "right": ""
        },
        {
          "left": "Chief",
          "right": ""
        },
        {
          "left": "Short Man",
          "right": ""
        },
        {
          "left": "Sycamore man",
          "right": ""
        },
        {
          "left": "Corrupt",
          "right": ""
        }
      ],
      "source_card": {
        "id": 121,
        "term": "Zacchaeus",
        "clues": [
          "Tax Collector",
          "Chief",
          "Short Man",
          "Sycamore man",
          "Corrupt"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 122,
    "front_text": "Seth",
    "back_text": "",
    "metadata": {
      "id": 122,
      "contentItemId": "game-bible-talk",
      "sortOrder": 122,
      "pairs": [
        {
          "left": "Seth",
          "right": ""
        },
        {
          "left": "Genesis",
          "right": ""
        },
        {
          "left": "Adam",
          "right": ""
        },
        {
          "left": "Eve",
          "right": ""
        },
        {
          "left": "Japhet",
          "right": ""
        },
        {
          "left": "Brother",
          "right": ""
        }
      ],
      "source_card": {
        "id": 122,
        "term": "Seth",
        "clues": [
          "Genesis",
          "Adam",
          "Eve",
          "Japhet",
          "Brother"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 123,
    "front_text": "Rahab",
    "back_text": "",
    "metadata": {
      "id": 123,
      "contentItemId": "game-bible-talk",
      "sortOrder": 123,
      "pairs": [
        {
          "left": "Rahab",
          "right": ""
        },
        {
          "left": "Prostitute",
          "right": ""
        },
        {
          "left": "Walls",
          "right": ""
        },
        {
          "left": "Jericho",
          "right": ""
        },
        {
          "left": "Spies",
          "right": ""
        },
        {
          "left": "Joshua",
          "right": ""
        }
      ],
      "source_card": {
        "id": 123,
        "term": "Rahab",
        "clues": [
          "Prostitute",
          "Walls",
          "Jericho",
          "Spies",
          "Joshua"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 124,
    "front_text": "Levites",
    "back_text": "",
    "metadata": {
      "id": 124,
      "contentItemId": "game-bible-talk",
      "sortOrder": 124,
      "pairs": [
        {
          "left": "Levites",
          "right": ""
        },
        {
          "left": "Tribe",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        },
        {
          "left": "Temple workers",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        },
        {
          "left": "Tithe",
          "right": ""
        }
      ],
      "source_card": {
        "id": 124,
        "term": "Levites",
        "clues": [
          "Tribe",
          "Priest",
          "Temple workers",
          "Israelites",
          "Tithe"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 125,
    "front_text": "Zipporah",
    "back_text": "",
    "metadata": {
      "id": 125,
      "contentItemId": "game-bible-talk",
      "sortOrder": 125,
      "pairs": [
        {
          "left": "Zipporah",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Wife",
          "right": ""
        },
        {
          "left": "Jethro",
          "right": ""
        },
        {
          "left": "Exodus",
          "right": ""
        },
        {
          "left": "Cushite",
          "right": ""
        }
      ],
      "source_card": {
        "id": 125,
        "term": "Zipporah",
        "clues": [
          "Moses",
          "Wife",
          "Jethro",
          "Exodus",
          "Cushite"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 126,
    "front_text": "Aaron",
    "back_text": "",
    "metadata": {
      "id": 126,
      "contentItemId": "game-bible-talk",
      "sortOrder": 126,
      "pairs": [
        {
          "left": "Aaron",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Levite",
          "right": ""
        },
        {
          "left": "Miracles",
          "right": ""
        },
        {
          "left": "Spokesperson",
          "right": ""
        }
      ],
      "source_card": {
        "id": 126,
        "term": "Aaron",
        "clues": [
          "Priest",
          "Moses",
          "Levite",
          "Miracles",
          "Spokesperson"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 127,
    "front_text": "Lazarus",
    "back_text": "",
    "metadata": {
      "id": 127,
      "contentItemId": "game-bible-talk",
      "sortOrder": 127,
      "pairs": [
        {
          "left": "Lazarus",
          "right": ""
        },
        {
          "left": "Friend",
          "right": ""
        },
        {
          "left": "Resurrected",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Martha",
          "right": ""
        },
        {
          "left": "Mary",
          "right": ""
        }
      ],
      "source_card": {
        "id": 127,
        "term": "Lazarus",
        "clues": [
          "Friend",
          "Resurrected",
          "Jesus",
          "Martha",
          "Mary"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 128,
    "front_text": "Boas",
    "back_text": "",
    "metadata": {
      "id": 128,
      "contentItemId": "game-bible-talk",
      "sortOrder": 128,
      "pairs": [
        {
          "left": "Boas",
          "right": ""
        },
        {
          "left": "Ruth",
          "right": ""
        },
        {
          "left": "Keensman redeemer.",
          "right": ""
        },
        {
          "left": "Rahab",
          "right": ""
        },
        {
          "left": "Obed",
          "right": ""
        },
        {
          "left": "Landowner",
          "right": ""
        }
      ],
      "source_card": {
        "id": 128,
        "term": "Boas",
        "clues": [
          "Ruth",
          "Keensman redeemer.",
          "Rahab",
          "Obed",
          "Landowner"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 129,
    "front_text": "Miriam",
    "back_text": "",
    "metadata": {
      "id": 129,
      "contentItemId": "game-bible-talk",
      "sortOrder": 129,
      "pairs": [
        {
          "left": "Miriam",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Aaron",
          "right": ""
        },
        {
          "left": "Gossip",
          "right": ""
        },
        {
          "left": "Exodus",
          "right": ""
        },
        {
          "left": "Prophetess",
          "right": ""
        }
      ],
      "source_card": {
        "id": 129,
        "term": "Miriam",
        "clues": [
          "Moses",
          "Aaron",
          "Gossip",
          "Exodus",
          "Prophetess"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 130,
    "front_text": "Cain",
    "back_text": "",
    "metadata": {
      "id": 130,
      "contentItemId": "game-bible-talk",
      "sortOrder": 130,
      "pairs": [
        {
          "left": "Cain",
          "right": ""
        },
        {
          "left": "Murderer",
          "right": ""
        },
        {
          "left": "Jealous",
          "right": ""
        },
        {
          "left": "Adam",
          "right": ""
        },
        {
          "left": "Abel",
          "right": ""
        },
        {
          "left": "Crop farmer",
          "right": ""
        }
      ],
      "source_card": {
        "id": 130,
        "term": "Cain",
        "clues": [
          "Murderer",
          "Jealous",
          "Adam",
          "Abel",
          "Crop farmer"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 131,
    "front_text": "Hannah",
    "back_text": "",
    "metadata": {
      "id": 131,
      "contentItemId": "game-bible-talk",
      "sortOrder": 131,
      "pairs": [
        {
          "left": "Hannah",
          "right": ""
        },
        {
          "left": "Prayer",
          "right": ""
        },
        {
          "left": "Samuel",
          "right": ""
        },
        {
          "left": "Temple",
          "right": ""
        },
        {
          "left": "Elkanah",
          "right": ""
        },
        {
          "left": "Drunk",
          "right": ""
        }
      ],
      "source_card": {
        "id": 131,
        "term": "Hannah",
        "clues": [
          "Prayer",
          "Samuel",
          "Temple",
          "Elkanah",
          "Drunk"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 132,
    "front_text": "Vashti",
    "back_text": "",
    "metadata": {
      "id": 132,
      "contentItemId": "game-bible-talk",
      "sortOrder": 132,
      "pairs": [
        {
          "left": "Vashti",
          "right": ""
        },
        {
          "left": "Queen",
          "right": ""
        },
        {
          "left": "Esther",
          "right": ""
        },
        {
          "left": "Beautiful",
          "right": ""
        },
        {
          "left": "Disobedience",
          "right": ""
        },
        {
          "left": "King Xerxes",
          "right": ""
        }
      ],
      "source_card": {
        "id": 132,
        "term": "Vashti",
        "clues": [
          "Queen",
          "Esther",
          "Beautiful",
          "Disobedience",
          "King Xerxes"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 133,
    "front_text": "Jonathan",
    "back_text": "",
    "metadata": {
      "id": 133,
      "contentItemId": "game-bible-talk",
      "sortOrder": 133,
      "pairs": [
        {
          "left": "Jonathan",
          "right": ""
        },
        {
          "left": "Saul",
          "right": ""
        },
        {
          "left": "David",
          "right": ""
        },
        {
          "left": "Bestfriend",
          "right": ""
        },
        {
          "left": "Prince",
          "right": ""
        },
        {
          "left": "Samuel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 133,
        "term": "Jonathan",
        "clues": [
          "Saul",
          "David",
          "Bestfriend",
          "Prince",
          "Samuel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 134,
    "front_text": "Baptism",
    "back_text": "",
    "metadata": {
      "id": 134,
      "contentItemId": "game-bible-talk",
      "sortOrder": 134,
      "pairs": [
        {
          "left": "Baptism",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "John",
          "right": ""
        },
        {
          "left": "River",
          "right": ""
        },
        {
          "left": "Commandments of the Lord",
          "right": ""
        },
        {
          "left": "Water",
          "right": ""
        }
      ],
      "source_card": {
        "id": 134,
        "term": "Baptism",
        "clues": [
          "Jesus",
          "John",
          "River",
          "Commandments of the Lord",
          "Water"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 135,
    "front_text": "Altar",
    "back_text": "",
    "metadata": {
      "id": 135,
      "contentItemId": "game-bible-talk",
      "sortOrder": 135,
      "pairs": [
        {
          "left": "Altar",
          "right": ""
        },
        {
          "left": "Offerings",
          "right": ""
        },
        {
          "left": "Prayers",
          "right": ""
        },
        {
          "left": "Flowers",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        }
      ],
      "source_card": {
        "id": 135,
        "term": "Altar",
        "clues": [
          "Offerings",
          "Prayers",
          "Flowers",
          "Jesus",
          "Priest"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 136,
    "front_text": "Zarephath",
    "back_text": "",
    "metadata": {
      "id": 136,
      "contentItemId": "game-bible-talk",
      "sortOrder": 136,
      "pairs": [
        {
          "left": "Zarephath",
          "right": ""
        },
        {
          "left": "Place",
          "right": ""
        },
        {
          "left": "Widow",
          "right": ""
        },
        {
          "left": "Elijah",
          "right": ""
        },
        {
          "left": "Sidon",
          "right": ""
        },
        {
          "left": "Elijah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 136,
        "term": "Zarephath",
        "clues": [
          "Place",
          "Widow",
          "Elijah",
          "Sidon",
          "Elijah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 137,
    "front_text": "Miriam",
    "back_text": "",
    "metadata": {
      "id": 137,
      "contentItemId": "game-bible-talk",
      "sortOrder": 137,
      "pairs": [
        {
          "left": "Miriam",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Aaron",
          "right": ""
        },
        {
          "left": "Gossip",
          "right": ""
        },
        {
          "left": "Exodus",
          "right": ""
        },
        {
          "left": "Prophetess",
          "right": ""
        }
      ],
      "source_card": {
        "id": 137,
        "term": "Miriam",
        "clues": [
          "Moses",
          "Aaron",
          "Gossip",
          "Exodus",
          "Prophetess"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 138,
    "front_text": "Death",
    "back_text": "",
    "metadata": {
      "id": 138,
      "contentItemId": "game-bible-talk",
      "sortOrder": 138,
      "pairs": [
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "People",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Judgment",
          "right": ""
        },
        {
          "left": "Burial",
          "right": ""
        },
        {
          "left": "Savior",
          "right": ""
        }
      ],
      "source_card": {
        "id": 138,
        "term": "Death",
        "clues": [
          "People",
          "Sinners",
          "Judgment",
          "Burial",
          "Savior"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 139,
    "front_text": "Caleb",
    "back_text": "",
    "metadata": {
      "id": 139,
      "contentItemId": "game-bible-talk",
      "sortOrder": 139,
      "pairs": [
        {
          "left": "Caleb",
          "right": ""
        },
        {
          "left": "Joshua",
          "right": ""
        },
        {
          "left": "Strong",
          "right": ""
        },
        {
          "left": "Faith",
          "right": ""
        },
        {
          "left": "Spy",
          "right": ""
        },
        {
          "left": "Canaan",
          "right": ""
        }
      ],
      "source_card": {
        "id": 139,
        "term": "Caleb",
        "clues": [
          "Joshua",
          "Strong",
          "Faith",
          "Spy",
          "Canaan"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 140,
    "front_text": "Heaven",
    "back_text": "",
    "metadata": {
      "id": 140,
      "contentItemId": "game-bible-talk",
      "sortOrder": 140,
      "pairs": [
        {
          "left": "Heaven",
          "right": ""
        },
        {
          "left": "Home",
          "right": ""
        },
        {
          "left": "Eternal Life",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Angels",
          "right": ""
        },
        {
          "left": "Cloudy",
          "right": ""
        }
      ],
      "source_card": {
        "id": 140,
        "term": "Heaven",
        "clues": [
          "Home",
          "Eternal Life",
          "Death",
          "Angels",
          "Cloudy"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 141,
    "front_text": "Crown of Thorns",
    "back_text": "",
    "metadata": {
      "id": 141,
      "contentItemId": "game-bible-talk",
      "sortOrder": 141,
      "pairs": [
        {
          "left": "Crown of Thorns",
          "right": ""
        },
        {
          "left": "Honor",
          "right": ""
        },
        {
          "left": "Jesus Super",
          "right": ""
        },
        {
          "left": "Royalty",
          "right": ""
        },
        {
          "left": "Pain",
          "right": ""
        },
        {
          "left": "Paintfull",
          "right": ""
        }
      ],
      "source_card": {
        "id": 141,
        "term": "Crown of Thorns",
        "clues": [
          "Honor",
          "Jesus Super",
          "Royalty",
          "Pain",
          "Paintfull"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 142,
    "front_text": "Red Sea",
    "back_text": "",
    "metadata": {
      "id": 142,
      "contentItemId": "game-bible-talk",
      "sortOrder": 142,
      "pairs": [
        {
          "left": "Red Sea",
          "right": ""
        },
        {
          "left": "Salty",
          "right": ""
        },
        {
          "left": "Wilderness",
          "right": ""
        },
        {
          "left": "Moses",
          "right": ""
        },
        {
          "left": "Turn to Dry land",
          "right": ""
        },
        {
          "left": "Divide",
          "right": ""
        }
      ],
      "source_card": {
        "id": 142,
        "term": "Red Sea",
        "clues": [
          "Salty",
          "Wilderness",
          "Moses",
          "Turn to Dry land",
          "Divide"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 143,
    "front_text": "Fire",
    "back_text": "",
    "metadata": {
      "id": 143,
      "contentItemId": "game-bible-talk",
      "sortOrder": 143,
      "pairs": [
        {
          "left": "Fire",
          "right": ""
        },
        {
          "left": "Hot",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Home of Fallen Angels",
          "right": ""
        },
        {
          "left": "Gives Light",
          "right": ""
        }
      ],
      "source_card": {
        "id": 143,
        "term": "Fire",
        "clues": [
          "Hot",
          "Sinners",
          "Death",
          "Home of Fallen Angels",
          "Gives Light"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 144,
    "front_text": "Second Coming",
    "back_text": "",
    "metadata": {
      "id": 144,
      "contentItemId": "game-bible-talk",
      "sortOrder": 144,
      "pairs": [
        {
          "left": "Second Coming",
          "right": ""
        },
        {
          "left": "Judgment",
          "right": ""
        },
        {
          "left": "Punishment",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Jesus Christ",
          "right": ""
        }
      ],
      "source_card": {
        "id": 144,
        "term": "Second Coming",
        "clues": [
          "Judgment",
          "Punishment",
          "Death",
          "Sinners",
          "Jesus Christ"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 145,
    "front_text": "Enoch",
    "back_text": "",
    "metadata": {
      "id": 145,
      "contentItemId": "game-bible-talk",
      "sortOrder": 145,
      "pairs": [
        {
          "left": "Enoch",
          "right": ""
        },
        {
          "left": "Jared",
          "right": ""
        },
        {
          "left": "Father",
          "right": ""
        },
        {
          "left": "Servant",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "God took him",
          "right": ""
        }
      ],
      "source_card": {
        "id": 145,
        "term": "Enoch",
        "clues": [
          "Jared",
          "Father",
          "Servant",
          "Death",
          "God took him"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 146,
    "front_text": "Ezekiel",
    "back_text": "",
    "metadata": {
      "id": 146,
      "contentItemId": "game-bible-talk",
      "sortOrder": 146,
      "pairs": [
        {
          "left": "Ezekiel",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Israelites",
          "right": ""
        },
        {
          "left": "Promise Land Plotted",
          "right": ""
        },
        {
          "left": "People of Judah Organized",
          "right": ""
        },
        {
          "left": "“their own Land”",
          "right": ""
        }
      ],
      "source_card": {
        "id": 146,
        "term": "Ezekiel",
        "clues": [
          "Prophet",
          "Israelites",
          "Promise Land Plotted",
          "People of Judah Organized",
          "“their own Land”"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 147,
    "front_text": "Absalom",
    "back_text": "",
    "metadata": {
      "id": 147,
      "contentItemId": "game-bible-talk",
      "sortOrder": 147,
      "pairs": [
        {
          "left": "Absalom",
          "right": ""
        },
        {
          "left": "Father of peace",
          "right": ""
        },
        {
          "left": "David Son",
          "right": ""
        },
        {
          "left": "revenge on Amnon",
          "right": ""
        },
        {
          "left": "Revolt to David",
          "right": ""
        },
        {
          "left": "Kill by joab",
          "right": ""
        }
      ],
      "source_card": {
        "id": 147,
        "term": "Absalom",
        "clues": [
          "Father of peace",
          "David Son",
          "revenge on Amnon",
          "Revolt to David",
          "Kill by joab"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 148,
    "front_text": "Elizabeth",
    "back_text": "",
    "metadata": {
      "id": 148,
      "contentItemId": "game-bible-talk",
      "sortOrder": 148,
      "pairs": [
        {
          "left": "Elizabeth",
          "right": ""
        },
        {
          "left": "John",
          "right": ""
        },
        {
          "left": "Miracles",
          "right": ""
        },
        {
          "left": "Give Birth",
          "right": ""
        },
        {
          "left": "Mary Magdalane",
          "right": ""
        },
        {
          "left": "Zechariah",
          "right": ""
        },
        {
          "left": "Ezra",
          "right": ""
        }
      ],
      "source_card": {
        "id": 148,
        "term": "Elizabeth",
        "clues": [
          "John",
          "Miracles",
          "Give Birth",
          "Mary Magdalane",
          "Zechariah",
          "Ezra"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 149,
    "front_text": "Abigail",
    "back_text": "",
    "metadata": {
      "id": 149,
      "contentItemId": "game-bible-talk",
      "sortOrder": 149,
      "pairs": [
        {
          "left": "Abigail",
          "right": ""
        },
        {
          "left": "King David",
          "right": ""
        },
        {
          "left": "Wife of Nabal",
          "right": ""
        },
        {
          "left": "Helped David",
          "right": ""
        },
        {
          "left": "Wife Accused",
          "right": ""
        },
        {
          "left": "Amasa",
          "right": ""
        },
        {
          "left": "Abimelech",
          "right": ""
        }
      ],
      "source_card": {
        "id": 149,
        "term": "Abigail",
        "clues": [
          "King David",
          "Wife of Nabal",
          "Helped David",
          "Wife Accused",
          "Amasa",
          "Abimelech"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 150,
    "front_text": "Ahasuerus",
    "back_text": "",
    "metadata": {
      "id": 150,
      "contentItemId": "game-bible-talk",
      "sortOrder": 150,
      "pairs": [
        {
          "left": "Ahasuerus",
          "right": ""
        },
        {
          "left": "King of Persia",
          "right": ""
        },
        {
          "left": "Husband of Esther",
          "right": ""
        },
        {
          "left": "Mighty Man",
          "right": ""
        },
        {
          "left": "inhabitants of Judah",
          "right": ""
        },
        {
          "left": "& Jerusalem",
          "right": ""
        },
        {
          "left": "Amos",
          "right": ""
        }
      ],
      "source_card": {
        "id": 150,
        "term": "Ahasuerus",
        "clues": [
          "King of Persia",
          "Husband of Esther",
          "Mighty Man",
          "inhabitants of Judah",
          "& Jerusalem",
          "Amos"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 151,
    "front_text": "Leader",
    "back_text": "",
    "metadata": {
      "id": 151,
      "contentItemId": "game-bible-talk",
      "sortOrder": 151,
      "pairs": [
        {
          "left": "Leader",
          "right": ""
        },
        {
          "left": "Jews",
          "right": ""
        },
        {
          "left": "God helps",
          "right": ""
        },
        {
          "left": "Activist",
          "right": ""
        },
        {
          "left": "Author",
          "right": ""
        },
        {
          "left": "Gabriel ( Angel)",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 151,
        "term": "Leader",
        "clues": [
          "Jews",
          "God helps",
          "Activist",
          "Author",
          "Gabriel ( Angel)",
          "Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 152,
    "front_text": "Judge of Israel",
    "back_text": "",
    "metadata": {
      "id": 152,
      "contentItemId": "game-bible-talk",
      "sortOrder": 152,
      "pairs": [
        {
          "left": "Judge of Israel",
          "right": ""
        },
        {
          "left": "Son of Gideon",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Assassinate all his Brothers",
          "right": ""
        },
        {
          "left": "Killed by the Woman",
          "right": ""
        },
        {
          "left": "Abner",
          "right": ""
        },
        {
          "left": "Chief of the Army",
          "right": ""
        }
      ],
      "source_card": {
        "id": 152,
        "term": "Judge of Israel",
        "clues": [
          "Son of Gideon",
          "King",
          "Assassinate all his Brothers",
          "Killed by the Woman",
          "Abner",
          "Chief of the Army"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 153,
    "front_text": "Herdsman",
    "back_text": "",
    "metadata": {
      "id": 153,
      "contentItemId": "game-bible-talk",
      "sortOrder": 153,
      "pairs": [
        {
          "left": "Herdsman",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Book of the Bible",
          "right": ""
        },
        {
          "left": "Doom of Judah",
          "right": ""
        },
        {
          "left": "Heed th warnings",
          "right": ""
        },
        {
          "left": "Andrew",
          "right": ""
        },
        {
          "left": "Apostle",
          "right": ""
        }
      ],
      "source_card": {
        "id": 153,
        "term": "Herdsman",
        "clues": [
          "Prophet",
          "Book of the Bible",
          "Doom of Judah",
          "Heed th warnings",
          "Andrew",
          "Apostle"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 154,
    "front_text": "Interpret Vision",
    "back_text": "",
    "metadata": {
      "id": 154,
      "contentItemId": "game-bible-talk",
      "sortOrder": 154,
      "pairs": [
        {
          "left": "Interpret Vision",
          "right": ""
        },
        {
          "left": "Mary",
          "right": ""
        },
        {
          "left": "Have Power",
          "right": ""
        },
        {
          "left": "Guardian",
          "right": ""
        }
      ],
      "source_card": {
        "id": 154,
        "term": "Interpret Vision",
        "clues": [
          "Mary",
          "Have Power",
          "Guardian"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 155,
    "front_text": "Saul's highest military",
    "back_text": "",
    "metadata": {
      "id": 155,
      "contentItemId": "game-bible-talk",
      "sortOrder": 155,
      "pairs": [
        {
          "left": "Saul's highest military",
          "right": ""
        },
        {
          "left": "Made Ishbosheth as King",
          "right": ""
        },
        {
          "left": "Killed by Asahel",
          "right": ""
        },
        {
          "left": "Shift his Loyalties to David",
          "right": ""
        }
      ],
      "source_card": {
        "id": 155,
        "term": "Saul's highest military",
        "clues": [
          "Made Ishbosheth as King",
          "Killed by Asahel",
          "Shift his Loyalties to David"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 156,
    "front_text": "Brother of Simon Peter",
    "back_text": "",
    "metadata": {
      "id": 156,
      "contentItemId": "game-bible-talk",
      "sortOrder": 156,
      "pairs": [
        {
          "left": "Brother of Simon Peter",
          "right": ""
        },
        {
          "left": "Sea of Galilee",
          "right": ""
        },
        {
          "left": "Fisher of Men",
          "right": ""
        },
        {
          "left": "Mount of Olives",
          "right": ""
        }
      ],
      "source_card": {
        "id": 156,
        "term": "Brother of Simon Peter",
        "clues": [
          "Sea of Galilee",
          "Fisher of Men",
          "Mount of Olives"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 157,
    "front_text": "Bildad",
    "back_text": "",
    "metadata": {
      "id": 157,
      "contentItemId": "game-bible-talk",
      "sortOrder": 157,
      "pairs": [
        {
          "left": "Bildad",
          "right": ""
        },
        {
          "left": "Job",
          "right": ""
        },
        {
          "left": "The Shuhite",
          "right": ""
        },
        {
          "left": "Friend of Eliphazz",
          "right": ""
        },
        {
          "left": "Blamed Job",
          "right": ""
        },
        {
          "left": "Offer Sacrifice",
          "right": ""
        }
      ],
      "source_card": {
        "id": 157,
        "term": "Bildad",
        "clues": [
          "Job",
          "The Shuhite",
          "Friend of Eliphazz",
          "Blamed Job",
          "Offer Sacrifice"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 158,
    "front_text": "Enoch",
    "back_text": "",
    "metadata": {
      "id": 158,
      "contentItemId": "game-bible-talk",
      "sortOrder": 158,
      "pairs": [
        {
          "left": "Enoch",
          "right": ""
        },
        {
          "left": "Son of Cain",
          "right": ""
        },
        {
          "left": "Father of Methuselah",
          "right": ""
        },
        {
          "left": "Walk with God",
          "right": ""
        },
        {
          "left": "Doesn't see Death",
          "right": ""
        },
        {
          "left": "God took him",
          "right": ""
        }
      ],
      "source_card": {
        "id": 158,
        "term": "Enoch",
        "clues": [
          "Son of Cain",
          "Father of Methuselah",
          "Walk with God",
          "Doesn't see Death",
          "God took him"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 159,
    "front_text": "Ishbosheth",
    "back_text": "",
    "metadata": {
      "id": 159,
      "contentItemId": "game-bible-talk",
      "sortOrder": 159,
      "pairs": [
        {
          "left": "Ishbosheth",
          "right": ""
        },
        {
          "left": "King Solomon",
          "right": ""
        },
        {
          "left": "King",
          "right": ""
        },
        {
          "left": "Brother of Jonathan",
          "right": ""
        },
        {
          "left": "Baanah & Rechab",
          "right": ""
        },
        {
          "left": "Assassinated",
          "right": ""
        }
      ],
      "source_card": {
        "id": 159,
        "term": "Ishbosheth",
        "clues": [
          "King Solomon",
          "King",
          "Brother of Jonathan",
          "Baanah & Rechab",
          "Assassinated"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 160,
    "front_text": "Delilah",
    "back_text": "",
    "metadata": {
      "id": 160,
      "contentItemId": "game-bible-talk",
      "sortOrder": 160,
      "pairs": [
        {
          "left": "Delilah",
          "right": ""
        },
        {
          "left": "Philistine",
          "right": ""
        },
        {
          "left": "Love of Samson",
          "right": ""
        },
        {
          "left": "1100 pieces Silver",
          "right": ""
        },
        {
          "left": "Betrayed Samson",
          "right": ""
        },
        {
          "left": "Cut Samson's Hair",
          "right": ""
        },
        {
          "left": "Eli",
          "right": ""
        }
      ],
      "source_card": {
        "id": 160,
        "term": "Delilah",
        "clues": [
          "Philistine",
          "Love of Samson",
          "1100 pieces Silver",
          "Betrayed Samson",
          "Cut Samson's Hair",
          "Eli"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 161,
    "front_text": "Gad",
    "back_text": "",
    "metadata": {
      "id": 161,
      "contentItemId": "game-bible-talk",
      "sortOrder": 161,
      "pairs": [
        {
          "left": "Gad",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Persuaded David",
          "right": ""
        },
        {
          "left": "Told to build altar",
          "right": ""
        },
        {
          "left": "Cymbals, harp, lyres Pray",
          "right": ""
        },
        {
          "left": "Good Fortune",
          "right": ""
        },
        {
          "left": "Gideon",
          "right": ""
        }
      ],
      "source_card": {
        "id": 161,
        "term": "Gad",
        "clues": [
          "Prophet",
          "Persuaded David",
          "Told to build altar",
          "Cymbals, harp, lyres Pray",
          "Good Fortune",
          "Gideon"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 162,
    "front_text": "Jabez",
    "back_text": "",
    "metadata": {
      "id": 162,
      "contentItemId": "game-bible-talk",
      "sortOrder": 162,
      "pairs": [
        {
          "left": "Jabez",
          "right": ""
        },
        {
          "left": "Line of Judah",
          "right": ""
        },
        {
          "left": "Distress",
          "right": ""
        },
        {
          "left": "City of Judah",
          "right": ""
        },
        {
          "left": "to God to Bless him",
          "right": ""
        },
        {
          "left": "Keep him from evil",
          "right": ""
        },
        {
          "left": "Jesse",
          "right": ""
        }
      ],
      "source_card": {
        "id": 162,
        "term": "Jabez",
        "clues": [
          "Line of Judah",
          "Distress",
          "City of Judah",
          "to God to Bless him",
          "Keep him from evil",
          "Jesse"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 163,
    "front_text": "High Priest",
    "back_text": "",
    "metadata": {
      "id": 163,
      "contentItemId": "game-bible-talk",
      "sortOrder": 163,
      "pairs": [
        {
          "left": "High Priest",
          "right": ""
        },
        {
          "left": "Judge",
          "right": ""
        },
        {
          "left": "Punish by God",
          "right": ""
        },
        {
          "left": "Broke his neck & Died",
          "right": ""
        },
        {
          "left": "The Lord is Exalted",
          "right": ""
        },
        {
          "left": "Creation",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 163,
        "term": "High Priest",
        "clues": [
          "Judge",
          "Punish by God",
          "Broke his neck & Died",
          "The Lord is Exalted",
          "Creation",
          "God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 164,
    "front_text": "Son of Joash",
    "back_text": "",
    "metadata": {
      "id": 164,
      "contentItemId": "game-bible-talk",
      "sortOrder": 164,
      "pairs": [
        {
          "left": "Son of Joash",
          "right": ""
        },
        {
          "left": "Judge",
          "right": ""
        },
        {
          "left": "Leader of the Army",
          "right": ""
        },
        {
          "left": "Save the Israelites Permitted",
          "right": ""
        },
        {
          "left": "“Day of Median”",
          "right": ""
        },
        {
          "left": "Ham",
          "right": ""
        },
        {
          "left": "Noah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 164,
        "term": "Son of Joash",
        "clues": [
          "Judge",
          "Leader of the Army",
          "Save the Israelites Permitted",
          "“Day of Median”",
          "Ham",
          "Noah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 165,
    "front_text": "Father of David",
    "back_text": "",
    "metadata": {
      "id": 165,
      "contentItemId": "game-bible-talk",
      "sortOrder": 165,
      "pairs": [
        {
          "left": "Father of David",
          "right": ""
        },
        {
          "left": "Successor of king Saul",
          "right": ""
        },
        {
          "left": "Ancestors of Jesus",
          "right": ""
        },
        {
          "left": "David to play for",
          "right": ""
        },
        {
          "left": "Solomon",
          "right": ""
        },
        {
          "left": "Joel",
          "right": ""
        },
        {
          "left": "Son of Pethuel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 165,
        "term": "Father of David",
        "clues": [
          "Successor of king Saul",
          "Ancestors of Jesus",
          "David to play for",
          "Solomon",
          "Joel",
          "Son of Pethuel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 166,
    "front_text": "Heavens & Earth",
    "back_text": "",
    "metadata": {
      "id": 166,
      "contentItemId": "game-bible-talk",
      "sortOrder": 166,
      "pairs": [
        {
          "left": "Heavens & Earth",
          "right": ""
        },
        {
          "left": "6 th Days",
          "right": ""
        },
        {
          "left": "Adam & Eve",
          "right": ""
        },
        {
          "left": "Stars in the sky",
          "right": ""
        }
      ],
      "source_card": {
        "id": 166,
        "term": "Heavens & Earth",
        "clues": [
          "6 th Days",
          "Adam & Eve",
          "Stars in the sky"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 167,
    "front_text": "Shem and Japheth",
    "back_text": "",
    "metadata": {
      "id": 167,
      "contentItemId": "game-bible-talk",
      "sortOrder": 167,
      "pairs": [
        {
          "left": "Shem and Japheth",
          "right": ""
        },
        {
          "left": "The Great Flood",
          "right": ""
        },
        {
          "left": "Father of Canaan",
          "right": ""
        },
        {
          "left": "Son Cush is Nimrod",
          "right": ""
        }
      ],
      "source_card": {
        "id": 167,
        "term": "Shem and Japheth",
        "clues": [
          "The Great Flood",
          "Father of Canaan",
          "Son Cush is Nimrod"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 168,
    "front_text": "“locust plague”",
    "back_text": "",
    "metadata": {
      "id": 168,
      "contentItemId": "game-bible-talk",
      "sortOrder": 168,
      "pairs": [
        {
          "left": "“locust plague”",
          "right": ""
        },
        {
          "left": "“Apocalyptic”",
          "right": ""
        },
        {
          "left": "Day of the Lord",
          "right": ""
        },
        {
          "left": "Gifted Poet",
          "right": ""
        }
      ],
      "source_card": {
        "id": 168,
        "term": "“locust plague”",
        "clues": [
          "“Apocalyptic”",
          "Day of the Lord",
          "Gifted Poet"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 169,
    "front_text": "John the Apostle",
    "back_text": "",
    "metadata": {
      "id": 169,
      "contentItemId": "game-bible-talk",
      "sortOrder": 169,
      "pairs": [
        {
          "left": "John the Apostle",
          "right": ""
        },
        {
          "left": "Prophet",
          "right": ""
        },
        {
          "left": "Author of New Testaments",
          "right": ""
        },
        {
          "left": "Brother of James",
          "right": ""
        },
        {
          "left": "Fishers Men",
          "right": ""
        },
        {
          "left": "Beloved Disciple",
          "right": ""
        }
      ],
      "source_card": {
        "id": 169,
        "term": "John the Apostle",
        "clues": [
          "Prophet",
          "Author of New Testaments",
          "Brother of James",
          "Fishers Men",
          "Beloved Disciple"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 170,
    "front_text": "Luke",
    "back_text": "",
    "metadata": {
      "id": 170,
      "contentItemId": "game-bible-talk",
      "sortOrder": 170,
      "pairs": [
        {
          "left": "Luke",
          "right": ""
        },
        {
          "left": "New Testaments",
          "right": ""
        },
        {
          "left": "Physician",
          "right": ""
        },
        {
          "left": "Gospel",
          "right": ""
        },
        {
          "left": "Book of Acts",
          "right": ""
        },
        {
          "left": "Perfect God-Man",
          "right": ""
        }
      ],
      "source_card": {
        "id": 170,
        "term": "Luke",
        "clues": [
          "New Testaments",
          "Physician",
          "Gospel",
          "Book of Acts",
          "Perfect God-Man"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 171,
    "front_text": "Manasseh",
    "back_text": "",
    "metadata": {
      "id": 171,
      "contentItemId": "game-bible-talk",
      "sortOrder": 171,
      "pairs": [
        {
          "left": "Manasseh",
          "right": ""
        },
        {
          "left": "Son of Joseph",
          "right": ""
        },
        {
          "left": "Grandson of Jacob",
          "right": ""
        },
        {
          "left": "Tribes settle in Jordan",
          "right": ""
        },
        {
          "left": "Receive Seal of God",
          "right": ""
        },
        {
          "left": "“to forget”",
          "right": ""
        }
      ],
      "source_card": {
        "id": 171,
        "term": "Manasseh",
        "clues": [
          "Son of Joseph",
          "Grandson of Jacob",
          "Tribes settle in Jordan",
          "Receive Seal of God",
          "“to forget”"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 172,
    "front_text": "Jude",
    "back_text": "",
    "metadata": {
      "id": 172,
      "contentItemId": "game-bible-talk",
      "sortOrder": 172,
      "pairs": [
        {
          "left": "Jude",
          "right": ""
        },
        {
          "left": "New Testaments",
          "right": ""
        },
        {
          "left": "Brother of James",
          "right": ""
        },
        {
          "left": "False Teachers",
          "right": ""
        },
        {
          "left": "False Doctrine",
          "right": ""
        },
        {
          "left": "Stand the Power of God",
          "right": ""
        },
        {
          "left": "Leah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 172,
        "term": "Jude",
        "clues": [
          "New Testaments",
          "Brother of James",
          "False Teachers",
          "False Doctrine",
          "Stand the Power of God",
          "Leah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 173,
    "front_text": "Malachi",
    "back_text": "",
    "metadata": {
      "id": 173,
      "contentItemId": "game-bible-talk",
      "sortOrder": 173,
      "pairs": [
        {
          "left": "Malachi",
          "right": ""
        },
        {
          "left": "My messenger",
          "right": ""
        },
        {
          "left": "Old Testaments",
          "right": ""
        },
        {
          "left": "Coming of Messiah",
          "right": ""
        },
        {
          "left": "Last Book of Prophets",
          "right": ""
        },
        {
          "left": "Forerunner John the Baptist",
          "right": ""
        },
        {
          "left": "Chariot",
          "right": ""
        }
      ],
      "source_card": {
        "id": 173,
        "term": "Malachi",
        "clues": [
          "My messenger",
          "Old Testaments",
          "Coming of Messiah",
          "Last Book of Prophets",
          "Forerunner John the Baptist",
          "Chariot"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 174,
    "front_text": "Matthias",
    "back_text": "",
    "metadata": {
      "id": 174,
      "contentItemId": "game-bible-talk",
      "sortOrder": 174,
      "pairs": [
        {
          "left": "Matthias",
          "right": ""
        },
        {
          "left": "Apostles",
          "right": ""
        },
        {
          "left": "Replace Judas",
          "right": ""
        },
        {
          "left": "Preached in Judea",
          "right": ""
        },
        {
          "left": "Died A Martyr",
          "right": ""
        },
        {
          "left": "“Gift of God”",
          "right": ""
        },
        {
          "left": "Naomi",
          "right": ""
        }
      ],
      "source_card": {
        "id": 174,
        "term": "Matthias",
        "clues": [
          "Apostles",
          "Replace Judas",
          "Preached in Judea",
          "Died A Martyr",
          "“Gift of God”",
          "Naomi"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 175,
    "front_text": "Laban's Daughter",
    "back_text": "",
    "metadata": {
      "id": 175,
      "contentItemId": "game-bible-talk",
      "sortOrder": 175,
      "pairs": [
        {
          "left": "Laban's Daughter",
          "right": ""
        },
        {
          "left": "Jacob wife",
          "right": ""
        },
        {
          "left": "Sister of Rachel",
          "right": ""
        },
        {
          "left": "Mother of Judah",
          "right": ""
        },
        {
          "left": "Give Jacob her Handmaid",
          "right": ""
        },
        {
          "left": "Lot",
          "right": ""
        },
        {
          "left": "Nephew of Abraham",
          "right": ""
        }
      ],
      "source_card": {
        "id": 175,
        "term": "Laban's Daughter",
        "clues": [
          "Jacob wife",
          "Sister of Rachel",
          "Mother of Judah",
          "Give Jacob her Handmaid",
          "Lot",
          "Nephew of Abraham"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 176,
    "front_text": "Horse",
    "back_text": "",
    "metadata": {
      "id": 176,
      "contentItemId": "game-bible-talk",
      "sortOrder": 176,
      "pairs": [
        {
          "left": "Horse",
          "right": ""
        },
        {
          "left": "Doctrine of Good & Truth",
          "right": ""
        },
        {
          "left": "Carried Elijah",
          "right": ""
        },
        {
          "left": "Whirlwind into Heaven",
          "right": ""
        },
        {
          "left": "Send By God",
          "right": ""
        },
        {
          "left": "Elder",
          "right": ""
        },
        {
          "left": "Chief things of Wisdom",
          "right": ""
        }
      ],
      "source_card": {
        "id": 176,
        "term": "Horse",
        "clues": [
          "Doctrine of Good & Truth",
          "Carried Elijah",
          "Whirlwind into Heaven",
          "Send By God",
          "Elder",
          "Chief things of Wisdom"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 177,
    "front_text": "Mother-in-law of Ruth",
    "back_text": "",
    "metadata": {
      "id": 177,
      "contentItemId": "game-bible-talk",
      "sortOrder": 177,
      "pairs": [
        {
          "left": "Mother-in-law of Ruth",
          "right": ""
        },
        {
          "left": "Wife of Elimelech",
          "right": ""
        },
        {
          "left": "In the Book of Ruth",
          "right": ""
        },
        {
          "left": "Return to Judah",
          "right": ""
        },
        {
          "left": "“my joy”",
          "right": ""
        },
        {
          "left": "Manna",
          "right": ""
        },
        {
          "left": "Spiritual good",
          "right": ""
        }
      ],
      "source_card": {
        "id": 177,
        "term": "Mother-in-law of Ruth",
        "clues": [
          "Wife of Elimelech",
          "In the Book of Ruth",
          "Return to Judah",
          "“my joy”",
          "Manna",
          "Spiritual good"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 178,
    "front_text": "Jordan River Valley",
    "back_text": "",
    "metadata": {
      "id": 178,
      "contentItemId": "game-bible-talk",
      "sortOrder": 178,
      "pairs": [
        {
          "left": "Jordan River Valley",
          "right": ""
        },
        {
          "left": "Sodom",
          "right": ""
        },
        {
          "left": "Prisoner",
          "right": ""
        },
        {
          "left": "Pillar of Salt",
          "right": ""
        }
      ],
      "source_card": {
        "id": 178,
        "term": "Jordan River Valley",
        "clues": [
          "Sodom",
          "Prisoner",
          "Pillar of Salt"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 179,
    "front_text": "Old Men Good",
    "back_text": "",
    "metadata": {
      "id": 179,
      "contentItemId": "game-bible-talk",
      "sortOrder": 179,
      "pairs": [
        {
          "left": "Old Men Good",
          "right": ""
        },
        {
          "left": "Congregation",
          "right": ""
        },
        {
          "left": "Denotes who are in Good",
          "right": ""
        },
        {
          "left": "Intelligence Supreme",
          "right": ""
        }
      ],
      "source_card": {
        "id": 179,
        "term": "Old Men Good",
        "clues": [
          "Congregation",
          "Denotes who are in Good",
          "Intelligence Supreme"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 180,
    "front_text": "of the spiritual church",
    "back_text": "",
    "metadata": {
      "id": 180,
      "contentItemId": "game-bible-talk",
      "sortOrder": 180,
      "pairs": [
        {
          "left": "of the spiritual church",
          "right": ""
        },
        {
          "left": "Grain of the heavens",
          "right": ""
        },
        {
          "left": "The Lord in Us",
          "right": ""
        },
        {
          "left": "sense is significance",
          "right": ""
        }
      ],
      "source_card": {
        "id": 180,
        "term": "of the spiritual church",
        "clues": [
          "Grain of the heavens",
          "The Lord in Us",
          "sense is significance"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 181,
    "front_text": "Nebuchadnezzar",
    "back_text": "",
    "metadata": {
      "id": 181,
      "contentItemId": "game-bible-talk",
      "sortOrder": 181,
      "pairs": [
        {
          "left": "Nebuchadnezzar",
          "right": ""
        },
        {
          "left": "King Babylon",
          "right": ""
        },
        {
          "left": "Put Daniel Staff Advisors",
          "right": ""
        },
        {
          "left": "Interpret Dreams",
          "right": ""
        },
        {
          "left": "Praised & worship God",
          "right": ""
        },
        {
          "left": "In the Book of Daniel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 181,
        "term": "Nebuchadnezzar",
        "clues": [
          "King Babylon",
          "Put Daniel Staff Advisors",
          "Interpret Dreams",
          "Praised & worship God",
          "In the Book of Daniel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 182,
    "front_text": "Stephen",
    "back_text": "",
    "metadata": {
      "id": 182,
      "contentItemId": "game-bible-talk",
      "sortOrder": 182,
      "pairs": [
        {
          "left": "Stephen",
          "right": ""
        },
        {
          "left": "Decons",
          "right": ""
        },
        {
          "left": "Full of Faith",
          "right": ""
        },
        {
          "left": "Synagogues",
          "right": ""
        },
        {
          "left": "Blasphemy",
          "right": ""
        },
        {
          "left": "Stone to Death",
          "right": ""
        }
      ],
      "source_card": {
        "id": 182,
        "term": "Stephen",
        "clues": [
          "Decons",
          "Full of Faith",
          "Synagogues",
          "Blasphemy",
          "Stone to Death"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 183,
    "front_text": "Prophecies",
    "back_text": "",
    "metadata": {
      "id": 183,
      "contentItemId": "game-bible-talk",
      "sortOrder": 183,
      "pairs": [
        {
          "left": "Prophecies",
          "right": ""
        },
        {
          "left": "God Plan",
          "right": ""
        },
        {
          "left": "All The prophets",
          "right": ""
        },
        {
          "left": "Warning",
          "right": ""
        },
        {
          "left": "Signs of the times",
          "right": ""
        },
        {
          "left": "Children of God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 183,
        "term": "Prophecies",
        "clues": [
          "God Plan",
          "All The prophets",
          "Warning",
          "Signs of the times",
          "Children of God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 184,
    "front_text": "Onesimus",
    "back_text": "",
    "metadata": {
      "id": 184,
      "contentItemId": "game-bible-talk",
      "sortOrder": 184,
      "pairs": [
        {
          "left": "Onesimus",
          "right": ""
        },
        {
          "left": "Slave",
          "right": ""
        },
        {
          "left": "Met Apostle Paul",
          "right": ""
        },
        {
          "left": "Philemon",
          "right": ""
        },
        {
          "left": "Pay for any injustice",
          "right": ""
        },
        {
          "left": "“Useful”",
          "right": ""
        },
        {
          "left": "Potiphar",
          "right": ""
        }
      ],
      "source_card": {
        "id": 184,
        "term": "Onesimus",
        "clues": [
          "Slave",
          "Met Apostle Paul",
          "Philemon",
          "Pay for any injustice",
          "“Useful”",
          "Potiphar"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 185,
    "front_text": "Titus",
    "back_text": "",
    "metadata": {
      "id": 185,
      "contentItemId": "game-bible-talk",
      "sortOrder": 185,
      "pairs": [
        {
          "left": "Titus",
          "right": ""
        },
        {
          "left": "Gentile",
          "right": ""
        },
        {
          "left": "New Testaments",
          "right": ""
        },
        {
          "left": "Paul",
          "right": ""
        },
        {
          "left": "Not Jewish",
          "right": ""
        },
        {
          "left": "Christian Living",
          "right": ""
        },
        {
          "left": "Zephaniah 12",
          "right": ""
        }
      ],
      "source_card": {
        "id": 185,
        "term": "Titus",
        "clues": [
          "Gentile",
          "New Testaments",
          "Paul",
          "Not Jewish",
          "Christian Living",
          "Zephaniah 12"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 186,
    "front_text": "Salvation",
    "back_text": "",
    "metadata": {
      "id": 186,
      "contentItemId": "game-bible-talk",
      "sortOrder": 186,
      "pairs": [
        {
          "left": "Salvation",
          "right": ""
        },
        {
          "left": "Christians",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Gift",
          "right": ""
        },
        {
          "left": "Sons of God",
          "right": ""
        },
        {
          "left": "Repentance",
          "right": ""
        },
        {
          "left": "Tribes of Israel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 186,
        "term": "Salvation",
        "clues": [
          "Christians",
          "Sinners",
          "Gift",
          "Sons of God",
          "Repentance",
          "Tribes of Israel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 187,
    "front_text": "Chief Steward",
    "back_text": "",
    "metadata": {
      "id": 187,
      "contentItemId": "game-bible-talk",
      "sortOrder": 187,
      "pairs": [
        {
          "left": "Chief Steward",
          "right": ""
        },
        {
          "left": "Pharaohs",
          "right": ""
        },
        {
          "left": "Throw Joseph in Prison",
          "right": ""
        },
        {
          "left": "Punish Joseph",
          "right": ""
        },
        {
          "left": "Enemy of Joseph",
          "right": ""
        },
        {
          "left": "Second Coming",
          "right": ""
        },
        {
          "left": "In the blink of an-eye",
          "right": ""
        }
      ],
      "source_card": {
        "id": 187,
        "term": "Chief Steward",
        "clues": [
          "Pharaohs",
          "Throw Joseph in Prison",
          "Punish Joseph",
          "Enemy of Joseph",
          "Second Coming",
          "In the blink of an-eye"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 188,
    "front_text": "Cousin oh King Josiah",
    "back_text": "",
    "metadata": {
      "id": 188,
      "contentItemId": "game-bible-talk",
      "sortOrder": 188,
      "pairs": [
        {
          "left": "Cousin oh King Josiah",
          "right": ""
        },
        {
          "left": "Prophet to Judah",
          "right": ""
        },
        {
          "left": "“No Gods Beside Me”",
          "right": ""
        },
        {
          "left": "“The Day of Judgment",
          "right": ""
        },
        {
          "left": "“The Lord has hidden Away”",
          "right": ""
        },
        {
          "left": "Zipporah",
          "right": ""
        },
        {
          "left": "Wife of Moses",
          "right": ""
        }
      ],
      "source_card": {
        "id": 188,
        "term": "Cousin oh King Josiah",
        "clues": [
          "Prophet to Judah",
          "“No Gods Beside Me”",
          "“The Day of Judgment",
          "“The Lord has hidden Away”",
          "Zipporah",
          "Wife of Moses"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 189,
    "front_text": "Benjamin",
    "back_text": "",
    "metadata": {
      "id": 189,
      "contentItemId": "game-bible-talk",
      "sortOrder": 189,
      "pairs": [
        {
          "left": "Benjamin",
          "right": ""
        },
        {
          "left": "Joseph",
          "right": ""
        },
        {
          "left": "Judah",
          "right": ""
        },
        {
          "left": "Simeon",
          "right": ""
        },
        {
          "left": "12 Sons",
          "right": ""
        },
        {
          "left": "12 Apostles",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 189,
        "term": "Benjamin",
        "clues": [
          "Joseph",
          "Judah",
          "Simeon",
          "12 Sons",
          "12 Apostles",
          "Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 190,
    "front_text": "Tribulation",
    "back_text": "",
    "metadata": {
      "id": 190,
      "contentItemId": "game-bible-talk",
      "sortOrder": 190,
      "pairs": [
        {
          "left": "Tribulation",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Judgment Day",
          "right": ""
        },
        {
          "left": "Christians",
          "right": ""
        }
      ],
      "source_card": {
        "id": 190,
        "term": "Tribulation",
        "clues": [
          "Sinners",
          "Judgment Day",
          "Christians"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 191,
    "front_text": "Mentioned 4 times in Bible",
    "back_text": "",
    "metadata": {
      "id": 191,
      "contentItemId": "game-bible-talk",
      "sortOrder": 191,
      "pairs": [
        {
          "left": "Mentioned 4 times in Bible",
          "right": ""
        },
        {
          "left": "Daughter of Jethro",
          "right": ""
        },
        {
          "left": "Mother of Gershom & Eliezer",
          "right": ""
        }
      ],
      "source_card": {
        "id": 191,
        "term": "Mentioned 4 times in Bible",
        "clues": [
          "Daughter of Jethro",
          "Mother of Gershom & Eliezer"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 192,
    "front_text": "Fallower",
    "back_text": "",
    "metadata": {
      "id": 192,
      "contentItemId": "game-bible-talk",
      "sortOrder": 192,
      "pairs": [
        {
          "left": "Fallower",
          "right": ""
        },
        {
          "left": "Books of the Bible",
          "right": ""
        },
        {
          "left": "Disciples",
          "right": ""
        },
        {
          "left": "Fishers of Man",
          "right": ""
        }
      ],
      "source_card": {
        "id": 192,
        "term": "Fallower",
        "clues": [
          "Books of the Bible",
          "Disciples",
          "Fishers of Man"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 193,
    "front_text": "Tree of Life",
    "back_text": "",
    "metadata": {
      "id": 193,
      "contentItemId": "game-bible-talk",
      "sortOrder": 193,
      "pairs": [
        {
          "left": "Tree of Life",
          "right": ""
        },
        {
          "left": "Adam & Eve",
          "right": ""
        },
        {
          "left": "Serpent",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "Forbidden",
          "right": ""
        },
        {
          "left": "Punish by God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 193,
        "term": "Tree of Life",
        "clues": [
          "Adam & Eve",
          "Serpent",
          "Sin",
          "Forbidden",
          "Punish by God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 194,
    "front_text": "Sycamore Tree",
    "back_text": "",
    "metadata": {
      "id": 194,
      "contentItemId": "game-bible-talk",
      "sortOrder": 194,
      "pairs": [
        {
          "left": "Sycamore Tree",
          "right": ""
        },
        {
          "left": "Zacchaeous",
          "right": ""
        },
        {
          "left": "Climb",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "In the Bible",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        }
      ],
      "source_card": {
        "id": 194,
        "term": "Sycamore Tree",
        "clues": [
          "Zacchaeous",
          "Climb",
          "Jesus",
          "In the Bible",
          "Jesus"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 195,
    "front_text": "Silas",
    "back_text": "",
    "metadata": {
      "id": 195,
      "contentItemId": "game-bible-talk",
      "sortOrder": 195,
      "pairs": [
        {
          "left": "Silas",
          "right": ""
        },
        {
          "left": "Member of Christian",
          "right": ""
        },
        {
          "left": "Paul Selected him",
          "right": ""
        },
        {
          "left": "Cast into Prison",
          "right": ""
        },
        {
          "left": "Preaching the Gospel",
          "right": ""
        },
        {
          "left": "Gifted Speaker",
          "right": ""
        }
      ],
      "source_card": {
        "id": 195,
        "term": "Silas",
        "clues": [
          "Member of Christian",
          "Paul Selected him",
          "Cast into Prison",
          "Preaching the Gospel",
          "Gifted Speaker"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 196,
    "front_text": "Flood",
    "back_text": "",
    "metadata": {
      "id": 196,
      "contentItemId": "game-bible-talk",
      "sortOrder": 196,
      "pairs": [
        {
          "left": "Flood",
          "right": ""
        },
        {
          "left": "Noah",
          "right": ""
        },
        {
          "left": "Ark",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Washed",
          "right": ""
        },
        {
          "left": "Mount Ararat",
          "right": ""
        },
        {
          "left": "Olive oil",
          "right": ""
        }
      ],
      "source_card": {
        "id": 196,
        "term": "Flood",
        "clues": [
          "Noah",
          "Ark",
          "Sinners",
          "Washed",
          "Mount Ararat",
          "Olive oil"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 197,
    "front_text": "Reuben",
    "back_text": "",
    "metadata": {
      "id": 197,
      "contentItemId": "game-bible-talk",
      "sortOrder": 197,
      "pairs": [
        {
          "left": "Reuben",
          "right": ""
        },
        {
          "left": "Jacob",
          "right": ""
        },
        {
          "left": "Canaan",
          "right": ""
        },
        {
          "left": "Bilhah",
          "right": ""
        },
        {
          "left": "Seal of God",
          "right": ""
        },
        {
          "left": "“See a son”",
          "right": ""
        },
        {
          "left": "Rebecca",
          "right": ""
        }
      ],
      "source_card": {
        "id": 197,
        "term": "Reuben",
        "clues": [
          "Jacob",
          "Canaan",
          "Bilhah",
          "Seal of God",
          "“See a son”",
          "Rebecca"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 198,
    "front_text": "Miracle",
    "back_text": "",
    "metadata": {
      "id": 198,
      "contentItemId": "game-bible-talk",
      "sortOrder": 198,
      "pairs": [
        {
          "left": "Miracle",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Apostles",
          "right": ""
        },
        {
          "left": "Sick",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Believers",
          "right": ""
        },
        {
          "left": "Christian",
          "right": ""
        }
      ],
      "source_card": {
        "id": 198,
        "term": "Miracle",
        "clues": [
          "Jesus",
          "Apostles",
          "Sick",
          "God",
          "Believers",
          "Christian"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 199,
    "front_text": "Expensive Oil",
    "back_text": "",
    "metadata": {
      "id": 199,
      "contentItemId": "game-bible-talk",
      "sortOrder": 199,
      "pairs": [
        {
          "left": "Expensive Oil",
          "right": ""
        },
        {
          "left": "Use to wash God Feet",
          "right": ""
        },
        {
          "left": "Goods",
          "right": ""
        },
        {
          "left": "Found in Bible",
          "right": ""
        },
        {
          "left": "Use for Food",
          "right": ""
        },
        {
          "left": "Angels",
          "right": ""
        },
        {
          "left": "Guardian",
          "right": ""
        }
      ],
      "source_card": {
        "id": 199,
        "term": "Expensive Oil",
        "clues": [
          "Use to wash God Feet",
          "Goods",
          "Found in Bible",
          "Use for Food",
          "Angels",
          "Guardian"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 200,
    "front_text": "Wife of Isaac",
    "back_text": "",
    "metadata": {
      "id": 200,
      "contentItemId": "game-bible-talk",
      "sortOrder": 200,
      "pairs": [
        {
          "left": "Wife of Isaac",
          "right": ""
        },
        {
          "left": "Mother of Jacob & Esau",
          "right": ""
        },
        {
          "left": "Deceived Isaac",
          "right": ""
        },
        {
          "left": "Protected Jacob",
          "right": ""
        },
        {
          "left": "Beautiful",
          "right": ""
        },
        {
          "left": "Fallen Angels",
          "right": ""
        },
        {
          "left": "Disobeyed God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 200,
        "term": "Wife of Isaac",
        "clues": [
          "Mother of Jacob & Esau",
          "Deceived Isaac",
          "Protected Jacob",
          "Beautiful",
          "Fallen Angels",
          "Disobeyed God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 201,
    "front_text": "Salvation",
    "back_text": "",
    "metadata": {
      "id": 201,
      "contentItemId": "game-bible-talk",
      "sortOrder": 201,
      "pairs": [
        {
          "left": "Salvation",
          "right": ""
        },
        {
          "left": "Accept Christ",
          "right": ""
        },
        {
          "left": "Walked with God",
          "right": ""
        },
        {
          "left": "Witnesses",
          "right": ""
        },
        {
          "left": "Fallow Gods word",
          "right": ""
        },
        {
          "left": "Thomas",
          "right": ""
        },
        {
          "left": "Apostles",
          "right": ""
        }
      ],
      "source_card": {
        "id": 201,
        "term": "Salvation",
        "clues": [
          "Accept Christ",
          "Walked with God",
          "Witnesses",
          "Fallow Gods word",
          "Thomas",
          "Apostles"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 202,
    "front_text": "Messenger",
    "back_text": "",
    "metadata": {
      "id": 202,
      "contentItemId": "game-bible-talk",
      "sortOrder": 202,
      "pairs": [
        {
          "left": "Messenger",
          "right": ""
        },
        {
          "left": "Powerful Guard",
          "right": ""
        },
        {
          "left": "Heaven",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 202,
        "term": "Messenger",
        "clues": [
          "Powerful Guard",
          "Heaven",
          "God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 203,
    "front_text": "Powerful",
    "back_text": "",
    "metadata": {
      "id": 203,
      "contentItemId": "game-bible-talk",
      "sortOrder": 203,
      "pairs": [
        {
          "left": "Powerful",
          "right": ""
        },
        {
          "left": "Provoke Person to be Sin",
          "right": ""
        },
        {
          "left": "Cast in the Lake of Fire",
          "right": ""
        },
        {
          "left": "Satan",
          "right": ""
        }
      ],
      "source_card": {
        "id": 203,
        "term": "Powerful",
        "clues": [
          "Provoke Person to be Sin",
          "Cast in the Lake of Fire",
          "Satan"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 204,
    "front_text": "Jesus",
    "back_text": "",
    "metadata": {
      "id": 204,
      "contentItemId": "game-bible-talk",
      "sortOrder": 204,
      "pairs": [
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Didymus",
          "right": ""
        },
        {
          "left": "Confessed his Faith",
          "right": ""
        },
        {
          "left": "Sea of Galilee",
          "right": ""
        }
      ],
      "source_card": {
        "id": 204,
        "term": "Jesus",
        "clues": [
          "Didymus",
          "Confessed his Faith",
          "Sea of Galilee"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 205,
    "front_text": "Satan",
    "back_text": "",
    "metadata": {
      "id": 205,
      "contentItemId": "game-bible-talk",
      "sortOrder": 205,
      "pairs": [
        {
          "left": "Satan",
          "right": ""
        },
        {
          "left": "Fallen Angels",
          "right": ""
        },
        {
          "left": "Enemy",
          "right": ""
        },
        {
          "left": "Wanted to have Power",
          "right": ""
        },
        {
          "left": "Believe to much on his Self",
          "right": ""
        },
        {
          "left": "Fire",
          "right": ""
        }
      ],
      "source_card": {
        "id": 205,
        "term": "Satan",
        "clues": [
          "Fallen Angels",
          "Enemy",
          "Wanted to have Power",
          "Believe to much on his Self",
          "Fire"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 206,
    "front_text": "Trials",
    "back_text": "",
    "metadata": {
      "id": 206,
      "contentItemId": "game-bible-talk",
      "sortOrder": 206,
      "pairs": [
        {
          "left": "Trials",
          "right": ""
        },
        {
          "left": "Given by Satan",
          "right": ""
        },
        {
          "left": "Jesus allowed it",
          "right": ""
        },
        {
          "left": "Christian",
          "right": ""
        },
        {
          "left": "Strength",
          "right": ""
        },
        {
          "left": "Job",
          "right": ""
        }
      ],
      "source_card": {
        "id": 206,
        "term": "Trials",
        "clues": [
          "Given by Satan",
          "Jesus allowed it",
          "Christian",
          "Strength",
          "Job"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 207,
    "front_text": "Psalms",
    "back_text": "",
    "metadata": {
      "id": 207,
      "contentItemId": "game-bible-talk",
      "sortOrder": 207,
      "pairs": [
        {
          "left": "Psalms",
          "right": ""
        },
        {
          "left": "Old Testaments",
          "right": ""
        },
        {
          "left": "Songs",
          "right": ""
        },
        {
          "left": "Praises",
          "right": ""
        },
        {
          "left": "Wondrous works",
          "right": ""
        },
        {
          "left": "Many chapters",
          "right": ""
        }
      ],
      "source_card": {
        "id": 207,
        "term": "Psalms",
        "clues": [
          "Old Testaments",
          "Songs",
          "Praises",
          "Wondrous works",
          "Many chapters"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 208,
    "front_text": "Gold",
    "back_text": "",
    "metadata": {
      "id": 208,
      "contentItemId": "game-bible-talk",
      "sortOrder": 208,
      "pairs": [
        {
          "left": "Gold",
          "right": ""
        },
        {
          "left": "Offering",
          "right": ""
        },
        {
          "left": "Heaven",
          "right": ""
        },
        {
          "left": "Precious",
          "right": ""
        },
        {
          "left": "Kings Riches",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Pastors",
          "right": ""
        }
      ],
      "source_card": {
        "id": 208,
        "term": "Gold",
        "clues": [
          "Offering",
          "Heaven",
          "Precious",
          "Kings Riches",
          "Jesus",
          "Pastors"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 209,
    "front_text": "Church",
    "back_text": "",
    "metadata": {
      "id": 209,
      "contentItemId": "game-bible-talk",
      "sortOrder": 209,
      "pairs": [
        {
          "left": "Church",
          "right": ""
        },
        {
          "left": "Sabbath One",
          "right": ""
        },
        {
          "left": "Christians",
          "right": ""
        },
        {
          "left": "Pastors",
          "right": ""
        },
        {
          "left": "Elder",
          "right": ""
        },
        {
          "left": "House of God",
          "right": ""
        },
        {
          "left": "Abel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 209,
        "term": "Church",
        "clues": [
          "Sabbath One",
          "Christians",
          "Pastors",
          "Elder",
          "House of God",
          "Abel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 210,
    "front_text": "Ahithophel",
    "back_text": "",
    "metadata": {
      "id": 210,
      "contentItemId": "game-bible-talk",
      "sortOrder": 210,
      "pairs": [
        {
          "left": "Ahithophel",
          "right": ""
        },
        {
          "left": "of Davids Counselor",
          "right": ""
        },
        {
          "left": "Assist Absalom",
          "right": ""
        },
        {
          "left": "Take David harem",
          "right": ""
        },
        {
          "left": "Pursue David",
          "right": ""
        },
        {
          "left": "Put his Household",
          "right": ""
        },
        {
          "left": "Amon",
          "right": ""
        }
      ],
      "source_card": {
        "id": 210,
        "term": "Ahithophel",
        "clues": [
          "of Davids Counselor",
          "Assist Absalom",
          "Take David harem",
          "Pursue David",
          "Put his Household",
          "Amon"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 211,
    "front_text": "Salvation",
    "back_text": "",
    "metadata": {
      "id": 211,
      "contentItemId": "game-bible-talk",
      "sortOrder": 211,
      "pairs": [
        {
          "left": "Salvation",
          "right": ""
        },
        {
          "left": "Men of God",
          "right": ""
        },
        {
          "left": "Witness",
          "right": ""
        },
        {
          "left": "Worker",
          "right": ""
        },
        {
          "left": "Teach Nations",
          "right": ""
        },
        {
          "left": "Thanksgiving",
          "right": ""
        },
        {
          "left": "Offering",
          "right": ""
        }
      ],
      "source_card": {
        "id": 211,
        "term": "Salvation",
        "clues": [
          "Men of God",
          "Witness",
          "Worker",
          "Teach Nations",
          "Thanksgiving",
          "Offering"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 212,
    "front_text": "Second Son of Adam",
    "back_text": "",
    "metadata": {
      "id": 212,
      "contentItemId": "game-bible-talk",
      "sortOrder": 212,
      "pairs": [
        {
          "left": "Second Son of Adam",
          "right": ""
        },
        {
          "left": "Cain",
          "right": ""
        },
        {
          "left": "Murdered",
          "right": ""
        },
        {
          "left": "Jealous",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Darkness",
          "right": ""
        },
        {
          "left": "Evening",
          "right": ""
        }
      ],
      "source_card": {
        "id": 212,
        "term": "Second Son of Adam",
        "clues": [
          "Cain",
          "Murdered",
          "Jealous",
          "Death",
          "Darkness",
          "Evening"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 213,
    "front_text": "Son of king Manasseh",
    "back_text": "",
    "metadata": {
      "id": 213,
      "contentItemId": "game-bible-talk",
      "sortOrder": 213,
      "pairs": [
        {
          "left": "Son of king Manasseh",
          "right": ""
        },
        {
          "left": "King of Judah",
          "right": ""
        },
        {
          "left": "Reign Evil One",
          "right": ""
        },
        {
          "left": "Sacrificed to pagan",
          "right": ""
        },
        {
          "left": "Assassinated",
          "right": ""
        },
        {
          "left": "Bartimaeus",
          "right": ""
        },
        {
          "left": "Son of Timaeous",
          "right": ""
        }
      ],
      "source_card": {
        "id": 213,
        "term": "Son of king Manasseh",
        "clues": [
          "King of Judah",
          "Reign Evil One",
          "Sacrificed to pagan",
          "Assassinated",
          "Bartimaeus",
          "Son of Timaeous"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 214,
    "front_text": "Given Back to the Lord",
    "back_text": "",
    "metadata": {
      "id": 214,
      "contentItemId": "game-bible-talk",
      "sortOrder": 214,
      "pairs": [
        {
          "left": "Given Back to the Lord",
          "right": ""
        },
        {
          "left": "Gathering",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Fellowship",
          "right": ""
        }
      ],
      "source_card": {
        "id": 214,
        "term": "Given Back to the Lord",
        "clues": [
          "Gathering",
          "Jesus",
          "Fellowship"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 215,
    "front_text": "Stars, Moon",
    "back_text": "",
    "metadata": {
      "id": 215,
      "contentItemId": "game-bible-talk",
      "sortOrder": 215,
      "pairs": [
        {
          "left": "Stars, Moon",
          "right": ""
        },
        {
          "left": "Second coming",
          "right": ""
        },
        {
          "left": "Light",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        }
      ],
      "source_card": {
        "id": 215,
        "term": "Stars, Moon",
        "clues": [
          "Second coming",
          "Light",
          "God"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 216,
    "front_text": "Blind Beggar",
    "back_text": "",
    "metadata": {
      "id": 216,
      "contentItemId": "game-bible-talk",
      "sortOrder": 216,
      "pairs": [
        {
          "left": "Blind Beggar",
          "right": ""
        },
        {
          "left": "Faith to be healed",
          "right": ""
        },
        {
          "left": "Jesus Miracle",
          "right": ""
        },
        {
          "left": "Believe in Gods Power",
          "right": ""
        }
      ],
      "source_card": {
        "id": 216,
        "term": "Blind Beggar",
        "clues": [
          "Faith to be healed",
          "Jesus Miracle",
          "Believe in Gods Power"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 217,
    "front_text": "Prodigal Son",
    "back_text": "",
    "metadata": {
      "id": 217,
      "contentItemId": "game-bible-talk",
      "sortOrder": 217,
      "pairs": [
        {
          "left": "Prodigal Son",
          "right": ""
        },
        {
          "left": "Repent",
          "right": ""
        },
        {
          "left": "Supper",
          "right": ""
        },
        {
          "left": "Wealthy man",
          "right": ""
        },
        {
          "left": "Accept by his Father",
          "right": ""
        },
        {
          "left": "Change Life",
          "right": ""
        }
      ],
      "source_card": {
        "id": 217,
        "term": "Prodigal Son",
        "clues": [
          "Repent",
          "Supper",
          "Wealthy man",
          "Accept by his Father",
          "Change Life"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 218,
    "front_text": "Cyrus",
    "back_text": "",
    "metadata": {
      "id": 218,
      "contentItemId": "game-bible-talk",
      "sortOrder": 218,
      "pairs": [
        {
          "left": "Cyrus",
          "right": ""
        },
        {
          "left": "King of Persia Village",
          "right": ""
        },
        {
          "left": "Open the gates of Babylon Woman",
          "right": ""
        },
        {
          "left": "In the books of Chronicles",
          "right": ""
        },
        {
          "left": "Proclamation of Kingdom",
          "right": ""
        },
        {
          "left": "Build a temple in Jerusalem",
          "right": ""
        }
      ],
      "source_card": {
        "id": 218,
        "term": "Cyrus",
        "clues": [
          "King of Persia Village",
          "Open the gates of Babylon Woman",
          "In the books of Chronicles",
          "Proclamation of Kingdom",
          "Build a temple in Jerusalem"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 219,
    "front_text": "Bethany",
    "back_text": "",
    "metadata": {
      "id": 219,
      "contentItemId": "game-bible-talk",
      "sortOrder": 219,
      "pairs": [
        {
          "left": "Bethany",
          "right": ""
        },
        {
          "left": "on the Mount of Olives",
          "right": ""
        },
        {
          "left": "poured a bottle of",
          "right": ""
        },
        {
          "left": "expensive perfume",
          "right": ""
        },
        {
          "left": "Jesus Lodged",
          "right": ""
        },
        {
          "left": "Palm Sunday",
          "right": ""
        }
      ],
      "source_card": {
        "id": 219,
        "term": "Bethany",
        "clues": [
          "on the Mount of Olives",
          "poured a bottle of",
          "expensive perfume",
          "Jesus Lodged",
          "Palm Sunday"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 220,
    "front_text": "Tomb",
    "back_text": "",
    "metadata": {
      "id": 220,
      "contentItemId": "game-bible-talk",
      "sortOrder": 220,
      "pairs": [
        {
          "left": "Tomb",
          "right": ""
        },
        {
          "left": "Death",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Resurrected",
          "right": ""
        },
        {
          "left": "Disciple",
          "right": ""
        },
        {
          "left": "Miracle",
          "right": ""
        }
      ],
      "source_card": {
        "id": 220,
        "term": "Tomb",
        "clues": [
          "Death",
          "Jesus",
          "Resurrected",
          "Disciple",
          "Miracle"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 221,
    "front_text": "Baptist",
    "back_text": "",
    "metadata": {
      "id": 221,
      "contentItemId": "game-bible-talk",
      "sortOrder": 221,
      "pairs": [
        {
          "left": "Baptist",
          "right": ""
        },
        {
          "left": "John",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Fallow God",
          "right": ""
        },
        {
          "left": "Ordinance of God Large",
          "right": ""
        },
        {
          "left": "Immerse City",
          "right": ""
        }
      ],
      "source_card": {
        "id": 221,
        "term": "Baptist",
        "clues": [
          "John",
          "Jesus",
          "Fallow God",
          "Ordinance of God Large",
          "Immerse City"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 222,
    "front_text": "Damascus",
    "back_text": "",
    "metadata": {
      "id": 222,
      "contentItemId": "game-bible-talk",
      "sortOrder": 222,
      "pairs": [
        {
          "left": "Damascus",
          "right": ""
        },
        {
          "left": "Capitol Syria",
          "right": ""
        },
        {
          "left": "Largest city",
          "right": ""
        },
        {
          "left": "New testaments",
          "right": ""
        },
        {
          "left": "Jewish Community",
          "right": ""
        },
        {
          "left": "in which Paul began",
          "right": ""
        }
      ],
      "source_card": {
        "id": 222,
        "term": "Damascus",
        "clues": [
          "Capitol Syria",
          "Largest city",
          "New testaments",
          "Jewish Community",
          "in which Paul began"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 223,
    "front_text": "Benaiah",
    "back_text": "",
    "metadata": {
      "id": 223,
      "contentItemId": "game-bible-talk",
      "sortOrder": 223,
      "pairs": [
        {
          "left": "Benaiah",
          "right": ""
        },
        {
          "left": "Bodyguards of David",
          "right": ""
        },
        {
          "left": "Loyal Supporter",
          "right": ""
        },
        {
          "left": "Executed Adonijah",
          "right": ""
        },
        {
          "left": "Commander of Army",
          "right": ""
        },
        {
          "left": "Killed Lion",
          "right": ""
        }
      ],
      "source_card": {
        "id": 223,
        "term": "Benaiah",
        "clues": [
          "Bodyguards of David",
          "Loyal Supporter",
          "Executed Adonijah",
          "Commander of Army",
          "Killed Lion"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 224,
    "front_text": "Tabernacle",
    "back_text": "",
    "metadata": {
      "id": 224,
      "contentItemId": "game-bible-talk",
      "sortOrder": 224,
      "pairs": [
        {
          "left": "Tabernacle",
          "right": ""
        },
        {
          "left": "Quite Place",
          "right": ""
        },
        {
          "left": "For Worship",
          "right": ""
        },
        {
          "left": "Temple",
          "right": ""
        },
        {
          "left": "Holy Place",
          "right": ""
        },
        {
          "left": "In the bible",
          "right": ""
        }
      ],
      "source_card": {
        "id": 224,
        "term": "Tabernacle",
        "clues": [
          "Quite Place",
          "For Worship",
          "Temple",
          "Holy Place",
          "In the bible"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 225,
    "front_text": "Dead Sea",
    "back_text": "",
    "metadata": {
      "id": 225,
      "contentItemId": "game-bible-talk",
      "sortOrder": 225,
      "pairs": [
        {
          "left": "Dead Sea",
          "right": ""
        },
        {
          "left": "Lowest point of Earth",
          "right": ""
        },
        {
          "left": "Judea Hills",
          "right": ""
        },
        {
          "left": "High Salth Content",
          "right": ""
        },
        {
          "left": "Found in the bible",
          "right": ""
        },
        {
          "left": "Book of Ezekiel",
          "right": ""
        }
      ],
      "source_card": {
        "id": 225,
        "term": "Dead Sea",
        "clues": [
          "Lowest point of Earth",
          "Judea Hills",
          "High Salth Content",
          "Found in the bible",
          "Book of Ezekiel"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 226,
    "front_text": "Boaz",
    "back_text": "",
    "metadata": {
      "id": 226,
      "contentItemId": "game-bible-talk",
      "sortOrder": 226,
      "pairs": [
        {
          "left": "Boaz",
          "right": ""
        },
        {
          "left": "Wealthy Man",
          "right": ""
        },
        {
          "left": "Husband of Ruth",
          "right": ""
        },
        {
          "left": "Buy estate for Ruth",
          "right": ""
        },
        {
          "left": "Great Grandfather of David",
          "right": ""
        },
        {
          "left": "“Strength”",
          "right": ""
        }
      ],
      "source_card": {
        "id": 226,
        "term": "Boaz",
        "clues": [
          "Wealthy Man",
          "Husband of Ruth",
          "Buy estate for Ruth",
          "Great Grandfather of David",
          "“Strength”"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 227,
    "front_text": "Antioch",
    "back_text": "",
    "metadata": {
      "id": 227,
      "contentItemId": "game-bible-talk",
      "sortOrder": 227,
      "pairs": [
        {
          "left": "Antioch",
          "right": ""
        },
        {
          "left": "Mediterranean",
          "right": ""
        },
        {
          "left": "Places",
          "right": ""
        },
        {
          "left": "Stephens",
          "right": ""
        },
        {
          "left": "Church 7",
          "right": ""
        },
        {
          "left": "Peter Visited",
          "right": ""
        }
      ],
      "source_card": {
        "id": 227,
        "term": "Antioch",
        "clues": [
          "Mediterranean",
          "Places",
          "Stephens",
          "Church 7",
          "Peter Visited"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 228,
    "front_text": "Ephesus",
    "back_text": "",
    "metadata": {
      "id": 228,
      "contentItemId": "game-bible-talk",
      "sortOrder": 228,
      "pairs": [
        {
          "left": "Ephesus",
          "right": ""
        },
        {
          "left": "Wealthiest city",
          "right": ""
        },
        {
          "left": "Paul stayed here",
          "right": ""
        },
        {
          "left": "Idol making crafts",
          "right": ""
        },
        {
          "left": "Churches of Revelation",
          "right": ""
        },
        {
          "left": "Apostle John",
          "right": ""
        }
      ],
      "source_card": {
        "id": 228,
        "term": "Ephesus",
        "clues": [
          "Wealthiest city",
          "Paul stayed here",
          "Idol making crafts",
          "Churches of Revelation",
          "Apostle John"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 229,
    "front_text": "Living Sacrifice",
    "back_text": "",
    "metadata": {
      "id": 229,
      "contentItemId": "game-bible-talk",
      "sortOrder": 229,
      "pairs": [
        {
          "left": "Living Sacrifice",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Lamp",
          "right": ""
        },
        {
          "left": "Sheep",
          "right": ""
        },
        {
          "left": "Silver & Gold",
          "right": ""
        },
        {
          "left": "Offerings",
          "right": ""
        }
      ],
      "source_card": {
        "id": 229,
        "term": "Living Sacrifice",
        "clues": [
          "Jesus",
          "Lamp",
          "Sheep",
          "Silver & Gold",
          "Offerings"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 230,
    "front_text": "Mrs. Noah",
    "back_text": "",
    "metadata": {
      "id": 230,
      "contentItemId": "game-bible-talk",
      "sortOrder": 230,
      "pairs": [
        {
          "left": "Mrs. Noah",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Wife",
          "right": ""
        },
        {
          "left": "Flood",
          "right": ""
        }
      ],
      "source_card": {
        "id": 230,
        "term": "Mrs. Noah",
        "clues": [
          "Animals",
          "Bible",
          "Sinners",
          "Wife",
          "Flood"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 231,
    "front_text": "Ahasuerus",
    "back_text": "",
    "metadata": {
      "id": 231,
      "contentItemId": "game-bible-talk",
      "sortOrder": 231,
      "pairs": [
        {
          "left": "Ahasuerus",
          "right": ""
        },
        {
          "left": "King of Persia",
          "right": ""
        },
        {
          "left": "Esther",
          "right": ""
        },
        {
          "left": "Old Testaments",
          "right": ""
        },
        {
          "left": "Discovered Mordecai",
          "right": ""
        },
        {
          "left": "“might man”",
          "right": ""
        }
      ],
      "source_card": {
        "id": 231,
        "term": "Ahasuerus",
        "clues": [
          "King of Persia",
          "Esther",
          "Old Testaments",
          "Discovered Mordecai",
          "“might man”"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 232,
    "front_text": "Bread of Life",
    "back_text": "",
    "metadata": {
      "id": 232,
      "contentItemId": "game-bible-talk",
      "sortOrder": 232,
      "pairs": [
        {
          "left": "Bread of Life",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Words of God",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Supply our Needs",
          "right": ""
        },
        {
          "left": "Christians",
          "right": ""
        }
      ],
      "source_card": {
        "id": 232,
        "term": "Bread of Life",
        "clues": [
          "Bible",
          "Words of God",
          "Jesus",
          "Supply our Needs",
          "Christians"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 233,
    "front_text": "Kidron Valley",
    "back_text": "",
    "metadata": {
      "id": 233,
      "contentItemId": "game-bible-talk",
      "sortOrder": 233,
      "pairs": [
        {
          "left": "Kidron Valley",
          "right": ""
        },
        {
          "left": "East Wall of Jerusalem",
          "right": ""
        },
        {
          "left": "Temple Mount",
          "right": ""
        },
        {
          "left": "Mount of Olives",
          "right": ""
        },
        {
          "left": "Josiah destroy Pagan god",
          "right": ""
        },
        {
          "left": "Tomb of Absalom is here",
          "right": ""
        }
      ],
      "source_card": {
        "id": 233,
        "term": "Kidron Valley",
        "clues": [
          "East Wall of Jerusalem",
          "Temple Mount",
          "Mount of Olives",
          "Josiah destroy Pagan god",
          "Tomb of Absalom is here"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 234,
    "front_text": "Hezekiah",
    "back_text": "",
    "metadata": {
      "id": 234,
      "contentItemId": "game-bible-talk",
      "sortOrder": 234,
      "pairs": [
        {
          "left": "Hezekiah",
          "right": ""
        },
        {
          "left": "King of Judah",
          "right": ""
        },
        {
          "left": "II Chronicles",
          "right": ""
        },
        {
          "left": "Isaiah",
          "right": ""
        },
        {
          "left": "Sanctification",
          "right": ""
        },
        {
          "left": "Restoration of Levites",
          "right": ""
        }
      ],
      "source_card": {
        "id": 234,
        "term": "Hezekiah",
        "clues": [
          "King of Judah",
          "II Chronicles",
          "Isaiah",
          "Sanctification",
          "Restoration of Levites"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 235,
    "front_text": "Shepherds",
    "back_text": "",
    "metadata": {
      "id": 235,
      "contentItemId": "game-bible-talk",
      "sortOrder": 235,
      "pairs": [
        {
          "left": "Shepherds",
          "right": ""
        },
        {
          "left": "Apostles",
          "right": ""
        },
        {
          "left": "Disciples",
          "right": ""
        },
        {
          "left": "Followers of God",
          "right": ""
        },
        {
          "left": "Animals",
          "right": ""
        },
        {
          "left": "Preachers",
          "right": ""
        }
      ],
      "source_card": {
        "id": 235,
        "term": "Shepherds",
        "clues": [
          "Apostles",
          "Disciples",
          "Followers of God",
          "Animals",
          "Preachers"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 236,
    "front_text": "Babylon",
    "back_text": "",
    "metadata": {
      "id": 236,
      "contentItemId": "game-bible-talk",
      "sortOrder": 236,
      "pairs": [
        {
          "left": "Babylon",
          "right": ""
        },
        {
          "left": "Jerusalem",
          "right": ""
        },
        {
          "left": "Subject of Prophecies",
          "right": ""
        },
        {
          "left": "Jeremiah",
          "right": ""
        },
        {
          "left": "Cyrus & Army Persians Encourage",
          "right": ""
        },
        {
          "left": "Rule over the Judah",
          "right": ""
        }
      ],
      "source_card": {
        "id": 236,
        "term": "Babylon",
        "clues": [
          "Jerusalem",
          "Subject of Prophecies",
          "Jeremiah",
          "Cyrus & Army Persians Encourage",
          "Rule over the Judah"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 237,
    "front_text": "Jehoshaphat",
    "back_text": "",
    "metadata": {
      "id": 237,
      "contentItemId": "game-bible-talk",
      "sortOrder": 237,
      "pairs": [
        {
          "left": "Jehoshaphat",
          "right": ""
        },
        {
          "left": "Son of King Asa",
          "right": ""
        },
        {
          "left": "King of Judah",
          "right": ""
        },
        {
          "left": "Wealthy & Popular",
          "right": ""
        },
        {
          "left": "to Worship God",
          "right": ""
        },
        {
          "left": "Battle between Ammon",
          "right": ""
        }
      ],
      "source_card": {
        "id": 237,
        "term": "Jehoshaphat",
        "clues": [
          "Son of King Asa",
          "King of Judah",
          "Wealthy & Popular",
          "to Worship God",
          "Battle between Ammon"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 238,
    "front_text": "Money",
    "back_text": "",
    "metadata": {
      "id": 238,
      "contentItemId": "game-bible-talk",
      "sortOrder": 238,
      "pairs": [
        {
          "left": "Money",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Temptation",
          "right": ""
        },
        {
          "left": "Trade",
          "right": ""
        },
        {
          "left": "Satan",
          "right": ""
        },
        {
          "left": "Ruth of Evil",
          "right": ""
        }
      ],
      "source_card": {
        "id": 238,
        "term": "Money",
        "clues": [
          "Bible",
          "Temptation",
          "Trade",
          "Satan",
          "Ruth of Evil"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 239,
    "front_text": "Holy",
    "back_text": "",
    "metadata": {
      "id": 239,
      "contentItemId": "game-bible-talk",
      "sortOrder": 239,
      "pairs": [
        {
          "left": "Holy",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "God Commandments",
          "right": ""
        },
        {
          "left": "God",
          "right": ""
        },
        {
          "left": "Mountains",
          "right": ""
        },
        {
          "left": "Believers",
          "right": ""
        }
      ],
      "source_card": {
        "id": 239,
        "term": "Holy",
        "clues": [
          "Bible",
          "God Commandments",
          "God",
          "Mountains",
          "Believers"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 240,
    "front_text": "Robbers",
    "back_text": "",
    "metadata": {
      "id": 240,
      "contentItemId": "game-bible-talk",
      "sortOrder": 240,
      "pairs": [
        {
          "left": "Robbers",
          "right": ""
        },
        {
          "left": "Bible",
          "right": ""
        },
        {
          "left": "Christians",
          "right": ""
        },
        {
          "left": "Sin",
          "right": ""
        },
        {
          "left": "Money",
          "right": ""
        },
        {
          "left": "Titles",
          "right": ""
        }
      ],
      "source_card": {
        "id": 240,
        "term": "Robbers",
        "clues": [
          "Bible",
          "Christians",
          "Sin",
          "Money",
          "Titles"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 241,
    "front_text": "Jehoiada",
    "back_text": "",
    "metadata": {
      "id": 241,
      "contentItemId": "game-bible-talk",
      "sortOrder": 241,
      "pairs": [
        {
          "left": "Jehoiada",
          "right": ""
        },
        {
          "left": "Priest",
          "right": ""
        },
        {
          "left": "Advisor to Joash",
          "right": ""
        },
        {
          "left": "Restore the Temple of the Lord",
          "right": ""
        },
        {
          "left": "Died on age 130 yrs old",
          "right": ""
        },
        {
          "left": "“God has known”",
          "right": ""
        }
      ],
      "source_card": {
        "id": 241,
        "term": "Jehoiada",
        "clues": [
          "Priest",
          "Advisor to Joash",
          "Restore the Temple of the Lord",
          "Died on age 130 yrs old",
          "“God has known”"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 242,
    "front_text": "Nail",
    "back_text": "",
    "metadata": {
      "id": 242,
      "contentItemId": "game-bible-talk",
      "sortOrder": 242,
      "pairs": [
        {
          "left": "Nail",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Punish",
          "right": ""
        },
        {
          "left": "Painful",
          "right": ""
        },
        {
          "left": "Blood",
          "right": ""
        },
        {
          "left": "Cross",
          "right": ""
        }
      ],
      "source_card": {
        "id": 242,
        "term": "Nail",
        "clues": [
          "Jesus",
          "Punish",
          "Painful",
          "Blood",
          "Cross"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 243,
    "front_text": "Teaching",
    "back_text": "",
    "metadata": {
      "id": 243,
      "contentItemId": "game-bible-talk",
      "sortOrder": 243,
      "pairs": [
        {
          "left": "Teaching",
          "right": ""
        },
        {
          "left": "Nations",
          "right": ""
        },
        {
          "left": "Word of God",
          "right": ""
        },
        {
          "left": "Commandments",
          "right": ""
        },
        {
          "left": "Jesus",
          "right": ""
        },
        {
          "left": "Disciples",
          "right": ""
        }
      ],
      "source_card": {
        "id": 243,
        "term": "Teaching",
        "clues": [
          "Nations",
          "Word of God",
          "Commandments",
          "Jesus",
          "Disciples"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 244,
    "front_text": "Couples",
    "back_text": "",
    "metadata": {
      "id": 244,
      "contentItemId": "game-bible-talk",
      "sortOrder": 244,
      "pairs": [
        {
          "left": "Couples",
          "right": ""
        },
        {
          "left": "Adam & Eve",
          "right": ""
        },
        {
          "left": "Sinners",
          "right": ""
        },
        {
          "left": "Made by God",
          "right": ""
        },
        {
          "left": "Relationship",
          "right": ""
        },
        {
          "left": "Life Partner",
          "right": ""
        }
      ],
      "source_card": {
        "id": 244,
        "term": "Couples",
        "clues": [
          "Adam & Eve",
          "Sinners",
          "Made by God",
          "Relationship",
          "Life Partner"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 245,
    "front_text": "Water",
    "back_text": "",
    "metadata": {
      "id": 245,
      "contentItemId": "game-bible-talk",
      "sortOrder": 245,
      "pairs": [
        {
          "left": "Water",
          "right": ""
        },
        {
          "left": "Thirst",
          "right": ""
        },
        {
          "left": "Cleanse",
          "right": ""
        },
        {
          "left": "Sea",
          "right": ""
        },
        {
          "left": "Flood",
          "right": ""
        },
        {
          "left": "Pure",
          "right": ""
        }
      ],
      "source_card": {
        "id": 245,
        "term": "Water",
        "clues": [
          "Thirst",
          "Cleanse",
          "Sea",
          "Flood",
          "Pure"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 246,
    "front_text": "Silent",
    "back_text": "",
    "metadata": {
      "id": 246,
      "contentItemId": "game-bible-talk",
      "sortOrder": 246,
      "pairs": [
        {
          "left": "Silent",
          "right": ""
        },
        {
          "left": "Temple",
          "right": ""
        },
        {
          "left": "Sleeping",
          "right": ""
        },
        {
          "left": "Holy City",
          "right": ""
        },
        {
          "left": "Prayer",
          "right": ""
        },
        {
          "left": "Midnight",
          "right": ""
        }
      ],
      "source_card": {
        "id": 246,
        "term": "Silent",
        "clues": [
          "Temple",
          "Sleeping",
          "Holy City",
          "Prayer",
          "Midnight"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 247,
    "front_text": "Queen",
    "back_text": "",
    "metadata": {
      "id": 247,
      "contentItemId": "game-bible-talk",
      "sortOrder": 247,
      "pairs": [
        {
          "left": "Queen",
          "right": ""
        },
        {
          "left": "Beautiful",
          "right": ""
        },
        {
          "left": "Treasures",
          "right": ""
        },
        {
          "left": "Powerful",
          "right": ""
        },
        {
          "left": "Wife",
          "right": ""
        },
        {
          "left": "Esther",
          "right": ""
        }
      ],
      "source_card": {
        "id": 247,
        "term": "Queen",
        "clues": [
          "Beautiful",
          "Treasures",
          "Powerful",
          "Wife",
          "Esther"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 248,
    "front_text": "Religion",
    "back_text": "",
    "metadata": {
      "id": 248,
      "contentItemId": "game-bible-talk",
      "sortOrder": 248,
      "pairs": [
        {
          "left": "Religion",
          "right": ""
        },
        {
          "left": "Biblical",
          "right": ""
        },
        {
          "left": "Many Nations",
          "right": ""
        },
        {
          "left": "People",
          "right": ""
        },
        {
          "left": "Pastors",
          "right": ""
        },
        {
          "left": "Group",
          "right": ""
        }
      ],
      "source_card": {
        "id": 248,
        "term": "Religion",
        "clues": [
          "Biblical",
          "Many Nations",
          "People",
          "Pastors",
          "Group"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 249,
    "front_text": "Ephesus",
    "back_text": "",
    "metadata": {
      "id": 249,
      "contentItemId": "game-bible-talk",
      "sortOrder": 249,
      "pairs": [
        {
          "left": "Ephesus",
          "right": ""
        },
        {
          "left": "Wealthiest city",
          "right": ""
        },
        {
          "left": "Paul stayed here",
          "right": ""
        },
        {
          "left": "Idol making crafts",
          "right": ""
        },
        {
          "left": "7 Churches of Revelation",
          "right": ""
        },
        {
          "left": "Apostle John",
          "right": ""
        }
      ],
      "source_card": {
        "id": 249,
        "term": "Ephesus",
        "clues": [
          "Wealthiest city",
          "Paul stayed here",
          "Idol making crafts",
          "7 Churches of Revelation",
          "Apostle John"
        ]
      }
    }
  },
  {
    "game_id": "game-bible-talk",
    "sort_order": 250,
    "front_text": "Crown",
    "back_text": "",
    "metadata": {
      "id": 250,
      "contentItemId": "game-bible-talk",
      "sortOrder": 250,
      "pairs": [
        {
          "left": "Crown",
          "right": ""
        },
        {
          "left": "Gold",
          "right": ""
        },
        {
          "left": "King or Queen",
          "right": ""
        },
        {
          "left": "Power",
          "right": ""
        },
        {
          "left": "Award",
          "right": ""
        },
        {
          "left": "Winning the Battles",
          "right": ""
        }
      ],
      "source_card": {
        "id": 250,
        "term": "Crown",
        "clues": [
          "Gold",
          "King or Queen",
          "Power",
          "Award",
          "Winning the Battles"
        ]
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 1,
    "front_text": "If a man is called to be a streetsweeper, he should sweep streets even as Michaelangelo painted, or Beethoven composed music, or Shakespeare wrote poetry. He should sweep the streets so well that all the hosts of heaven and earth will pause to say- here lived a great streetsweeper who did his job well.",
    "back_text": "",
    "metadata": {
      "id": 1,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 1,
      "pairs": [
        {
          "left": "If a man is called to be a streetsweeper, he should sweep streets even as Michaelangelo painted, or Beethoven composed music, or Shakespeare wrote poetry. He should sweep the streets so well that all the hosts of heaven and earth will pause to say- here lived a great streetsweeper who did his job well.",
          "right": ""
        },
        {
          "left": "- Martin Luther King",
          "right": ""
        },
        {
          "left": "What work would you be so passionate about that people would say this about you \"he/she is a great....\" And why?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 1,
        "quote": "If a man is called to be a streetsweeper, he should sweep streets even as Michaelangelo painted, or Beethoven composed music, or Shakespeare wrote poetry. He should sweep the streets so well that all the hosts of heaven and earth will pause to say- here lived a great streetsweeper who did his job well.",
        "author": "Martin Luther King",
        "question": "What work would you be so passionate about that people would say this about you \"he/she is a great....\" And why?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 2,
    "front_text": "If worship is just one of the things we do, everything becomes mundane. If worship is the one thing we do, everything takes on eternal significance.",
    "back_text": "",
    "metadata": {
      "id": 2,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 2,
      "pairs": [
        {
          "left": "If worship is just one of the things we do, everything becomes mundane. If worship is the one thing we do, everything takes on eternal significance.",
          "right": ""
        },
        {
          "left": "- Timothy Christenson",
          "right": ""
        },
        {
          "left": "What steps can you take so that you will have a more worshipful heart?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 2,
        "quote": "If worship is just one of the things we do, everything becomes mundane. If worship is the one thing we do, everything takes on eternal significance.",
        "author": "Timothy Christenson",
        "question": "What steps can you take so that you will have a more worshipful heart?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 3,
    "front_text": "Beware in your prayers, above everything else, of limiting God, not only by unbelief, but by fancying that you know what He can do. Expect unexpected things, 'above all that we ask or think'. Each time, before you Intercede, be quiet first, and worship God in His glory. Think of what He can do, and how He delights to hear the prayers of His redeemed people. Think of your place and privilege in Christ, and expect great things!",
    "back_text": "",
    "metadata": {
      "id": 3,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 3,
      "pairs": [
        {
          "left": "Beware in your prayers, above everything else, of limiting God, not only by unbelief, but by fancying that you know what He can do. Expect unexpected things, 'above all that we ask or think'. Each time, before you Intercede, be quiet first, and worship God in His glory. Think of what He can do, and how He delights to hear the prayers of His redeemed people. Think of your place and privilege in Christ, and expect great things!",
          "right": ""
        },
        {
          "left": "- Andrew Murray",
          "right": ""
        },
        {
          "left": "Name a time when God answered your prayer in a way that exceeded your expectations",
          "right": ""
        }
      ],
      "source_card": {
        "id": 3,
        "quote": "Beware in your prayers, above everything else, of limiting God, not only by unbelief, but by fancying that you know what He can do. Expect unexpected things, 'above all that we ask or think'. Each time, before you Intercede, be quiet first, and worship God in His glory. Think of what He can do, and how He delights to hear the prayers of His redeemed people. Think of your place and privilege in Christ, and expect great things!",
        "author": "Andrew Murray",
        "question": "Name a time when God answered your prayer in a way that exceeded your expectations"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 4,
    "front_text": "Our love to God is measured by our everyday fellowship with others and the love it displays.",
    "back_text": "",
    "metadata": {
      "id": 4,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 4,
      "pairs": [
        {
          "left": "Our love to God is measured by our everyday fellowship with others and the love it displays.",
          "right": ""
        },
        {
          "left": "- Andrew Murray",
          "right": ""
        },
        {
          "left": "What is the most loving thing that you feel someone has done to you and what is the most loving thing that you have done to someone?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 4,
        "quote": "Our love to God is measured by our everyday fellowship with others and the love it displays.",
        "author": "Andrew Murray",
        "question": "What is the most loving thing that you feel someone has done to you and what is the most loving thing that you have done to someone?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 5,
    "front_text": "He knows not his own strength that hath not met adversity. Heaven prepares good men with crosses.",
    "back_text": "",
    "metadata": {
      "id": 5,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 5,
      "pairs": [
        {
          "left": "He knows not his own strength that hath not met adversity. Heaven prepares good men with crosses.",
          "right": ""
        },
        {
          "left": "- Ben Johnson",
          "right": ""
        },
        {
          "left": "What is the greatest problem you ever had in your life, how did you overcome it and how did it make you a better person?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 5,
        "quote": "He knows not his own strength that hath not met adversity. Heaven prepares good men with crosses.",
        "author": "Ben Johnson",
        "question": "What is the greatest problem you ever had in your life, how did you overcome it and how did it make you a better person?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 6,
    "front_text": "The best way to prepare for the coming of Christ is never to forget the presence of Christ.",
    "back_text": "",
    "metadata": {
      "id": 6,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 6,
      "pairs": [
        {
          "left": "The best way to prepare for the coming of Christ is never to forget the presence of Christ.",
          "right": ""
        },
        {
          "left": "- William Barclay",
          "right": ""
        },
        {
          "left": "What can you do to continually bask in the presence of Christ?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 6,
        "quote": "The best way to prepare for the coming of Christ is never to forget the presence of Christ.",
        "author": "William Barclay",
        "question": "What can you do to continually bask in the presence of Christ?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 7,
    "front_text": "In the world to come, I shall not be asked, why were you not Moses? I shall be asked, why were you not Zusya?",
    "back_text": "",
    "metadata": {
      "id": 7,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 7,
      "pairs": [
        {
          "left": "In the world to come, I shall not be asked, why were you not Moses? I shall be asked, why were you not Zusya?",
          "right": ""
        },
        {
          "left": "- Rabbi Zusya",
          "right": ""
        },
        {
          "left": "In what way have you kept on improving yourself and how has the improvement been manifested in your life?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 7,
        "quote": "In the world to come, I shall not be asked, why were you not Moses? I shall be asked, why were you not Zusya?",
        "author": "Rabbi Zusya",
        "question": "In what way have you kept on improving yourself and how has the improvement been manifested in your life?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 8,
    "front_text": "If God has fit you to be a missionary, I would not have you shrivel down to be a king.",
    "back_text": "",
    "metadata": {
      "id": 8,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 8,
      "pairs": [
        {
          "left": "If God has fit you to be a missionary, I would not have you shrivel down to be a king.",
          "right": ""
        },
        {
          "left": "- Charles Spurgeon",
          "right": ""
        },
        {
          "left": "What important thing have you given up for God and how has God rewarded you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 8,
        "quote": "If God has fit you to be a missionary, I would not have you shrivel down to be a king.",
        "author": "Charles Spurgeon",
        "question": "What important thing have you given up for God and how has God rewarded you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 9,
    "front_text": "Adversity is often the window of opportunity for change. Few people or organizations want to change when there is prosperity and peace. Major changes are often precipitated by necessity.",
    "back_text": "",
    "metadata": {
      "id": 9,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 9,
      "pairs": [
        {
          "left": "Adversity is often the window of opportunity for change. Few people or organizations want to change when there is prosperity and peace. Major changes are often precipitated by necessity.",
          "right": ""
        },
        {
          "left": "- Leith Anderson",
          "right": ""
        },
        {
          "left": "What was the latest crisis in your life and how did it change you for the better?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 9,
        "quote": "Adversity is often the window of opportunity for change. Few people or organizations want to change when there is prosperity and peace. Major changes are often precipitated by necessity.",
        "author": "Leith Anderson",
        "question": "What was the latest crisis in your life and how did it change you for the better?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 10,
    "front_text": "The error of youth is to believe that intelligence is a substitute for experience, while the error of age is to believe that experience is a substitute for intelligence.",
    "back_text": "",
    "metadata": {
      "id": 10,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 10,
      "pairs": [
        {
          "left": "The error of youth is to believe that intelligence is a substitute for experience, while the error of age is to believe that experience is a substitute for intelligence.",
          "right": ""
        },
        {
          "left": "- Lyman Bryson",
          "right": ""
        },
        {
          "left": "What major issues did you have with people older than you (parents, bosses) and what have you learned from resolving those issues?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 10,
        "quote": "The error of youth is to believe that intelligence is a substitute for experience, while the error of age is to believe that experience is a substitute for intelligence.",
        "author": "Lyman Bryson",
        "question": "What major issues did you have with people older than you (parents, bosses) and what have you learned from resolving those issues?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 11,
    "front_text": "The bible is alive, it speaks to me; it has feet, it runs after me; it has hands, it lays hold of me.",
    "back_text": "",
    "metadata": {
      "id": 11,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 11,
      "pairs": [
        {
          "left": "The bible is alive, it speaks to me; it has feet, it runs after me; it has hands, it lays hold of me.",
          "right": ""
        },
        {
          "left": "- Martin Luther",
          "right": ""
        },
        {
          "left": "Share about a time when the bible convicted you to do something you would not have done otherwise",
          "right": ""
        }
      ],
      "source_card": {
        "id": 11,
        "quote": "The bible is alive, it speaks to me; it has feet, it runs after me; it has hands, it lays hold of me.",
        "author": "Martin Luther",
        "question": "Share about a time when the bible convicted you to do something you would not have done otherwise"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 12,
    "front_text": "The bible was not given to increase our knowledge but to change our lives.",
    "back_text": "",
    "metadata": {
      "id": 12,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 12,
      "pairs": [
        {
          "left": "The bible was not given to increase our knowledge but to change our lives.",
          "right": ""
        },
        {
          "left": "- D.L. Moody",
          "right": ""
        },
        {
          "left": "In what ways has the bible changed the way you think, the way you are?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 12,
        "quote": "The bible was not given to increase our knowledge but to change our lives.",
        "author": "D.L. Moody",
        "question": "In what ways has the bible changed the way you think, the way you are?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 13,
    "front_text": "There are no menial jobs, only menial attitudes.",
    "back_text": "",
    "metadata": {
      "id": 13,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 13,
      "pairs": [
        {
          "left": "There are no menial jobs, only menial attitudes.",
          "right": ""
        },
        {
          "left": "- William J. Bennett",
          "right": ""
        },
        {
          "left": "Share about a person who has a work considered menial but who you admire very much for his or her work ethic. What makes this person different?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 13,
        "quote": "There are no menial jobs, only menial attitudes.",
        "author": "William J. Bennett",
        "question": "Share about a person who has a work considered menial but who you admire very much for his or her work ethic. What makes this person different?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 14,
    "front_text": "For a small reward, a man will hurry away on a long journey; while for eternal life, many will hardly take a single step.",
    "back_text": "",
    "metadata": {
      "id": 14,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 14,
      "pairs": [
        {
          "left": "For a small reward, a man will hurry away on a long journey; while for eternal life, many will hardly take a single step.",
          "right": ""
        },
        {
          "left": "- Thomas a' Kempis",
          "right": ""
        },
        {
          "left": "What is the best reward that God has given you so far in your life.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 14,
        "quote": "For a small reward, a man will hurry away on a long journey; while for eternal life, many will hardly take a single step.",
        "author": "Thomas a' Kempis",
        "question": "What is the best reward that God has given you so far in your life."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 15,
    "front_text": "The kind of successor I may get depends a great deal on the kind of predecessor I've been and how I've related to my own predecessor. To reject the past and ignore the future.... is both selfish and foolish.",
    "back_text": "",
    "metadata": {
      "id": 15,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 15,
      "pairs": [
        {
          "left": "The kind of successor I may get depends a great deal on the kind of predecessor I've been and how I've related to my own predecessor. To reject the past and ignore the future.... is both selfish and foolish.",
          "right": ""
        },
        {
          "left": "- Warren W. Wiersbe",
          "right": ""
        },
        {
          "left": "What is the most important lesson that you learned from your mentor and what important lesson do you want to teach your mentee?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 15,
        "quote": "The kind of successor I may get depends a great deal on the kind of predecessor I've been and how I've related to my own predecessor. To reject the past and ignore the future.... is both selfish and foolish.",
        "author": "Warren W. Wiersbe",
        "question": "What is the most important lesson that you learned from your mentor and what important lesson do you want to teach your mentee?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 16,
    "front_text": "This book will keep you from sin, or sin will keep you from this book.",
    "back_text": "",
    "metadata": {
      "id": 16,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 16,
      "pairs": [
        {
          "left": "This book will keep you from sin, or sin will keep you from this book.",
          "right": ""
        },
        {
          "left": "- Charles Spurgeon",
          "right": ""
        },
        {
          "left": "How has the bible helped you overcome your greatest temptations?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 16,
        "quote": "This book will keep you from sin, or sin will keep you from this book.",
        "author": "Charles Spurgeon",
        "question": "How has the bible helped you overcome your greatest temptations?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 17,
    "front_text": "Alone I cannot serve God effectively, and he will spare no pains to teach me this. He will bring things to an end, allowing doors to close and leaving me ineffectively knocking my head against the wall until I realize that I need help of the body as well as of the Lord.",
    "back_text": "",
    "metadata": {
      "id": 17,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 17,
      "pairs": [
        {
          "left": "Alone I cannot serve God effectively, and he will spare no pains to teach me this. He will bring things to an end, allowing doors to close and leaving me ineffectively knocking my head against the wall until I realize that I need help of the body as well as of the Lord.",
          "right": ""
        },
        {
          "left": "- Watchman Nee",
          "right": ""
        },
        {
          "left": "Share about an unsuccessful task you tried to accomplish yourself which became successful when other people helped you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 17,
        "quote": "Alone I cannot serve God effectively, and he will spare no pains to teach me this. He will bring things to an end, allowing doors to close and leaving me ineffectively knocking my head against the wall until I realize that I need help of the body as well as of the Lord.",
        "author": "Watchman Nee",
        "question": "Share about an unsuccessful task you tried to accomplish yourself which became successful when other people helped you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 18,
    "front_text": "The ultimate measure of a man is not where he stands in moments of comfort and convenience, but where he stands at times of challenge and controversy.",
    "back_text": "",
    "metadata": {
      "id": 18,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 18,
      "pairs": [
        {
          "left": "The ultimate measure of a man is not where he stands in moments of comfort and convenience, but where he stands at times of challenge and controversy.",
          "right": ""
        },
        {
          "left": "- Martin Luther King Jr.",
          "right": ""
        },
        {
          "left": "Share about when you stood alone for a principle even when others were against what you did?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 18,
        "quote": "The ultimate measure of a man is not where he stands in moments of comfort and convenience, but where he stands at times of challenge and controversy.",
        "author": "Martin Luther King Jr.",
        "question": "Share about when you stood alone for a principle even when others were against what you did?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 19,
    "front_text": "The proof of Christianity is not a book but a life. The power of Christianity is not a creed but a Christian character; and wherever you see life that has been transformed by the grace of God, you see a witness to the resurrection of Jesus.",
    "back_text": "",
    "metadata": {
      "id": 19,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 19,
      "pairs": [
        {
          "left": "The proof of Christianity is not a book but a life. The power of Christianity is not a creed but a Christian character; and wherever you see life that has been transformed by the grace of God, you see a witness to the resurrection of Jesus.",
          "right": ""
        },
        {
          "left": "- William Woodfin",
          "right": ""
        },
        {
          "left": "Share about a person who you never thought would become a believer but who by the grace of God was transformed?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 19,
        "quote": "The proof of Christianity is not a book but a life. The power of Christianity is not a creed but a Christian character; and wherever you see life that has been transformed by the grace of God, you see a witness to the resurrection of Jesus.",
        "author": "William Woodfin",
        "question": "Share about a person who you never thought would become a believer but who by the grace of God was transformed?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 20,
    "front_text": "People are like stained glass windows. They sparkle and shine when the sun is out. But in the darkness, beauty is seen only if there is light within.",
    "back_text": "",
    "metadata": {
      "id": 20,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 20,
      "pairs": [
        {
          "left": "People are like stained glass windows. They sparkle and shine when the sun is out. But in the darkness, beauty is seen only if there is light within.",
          "right": ""
        },
        {
          "left": "- Anonymous",
          "right": ""
        },
        {
          "left": "When was the darkest time in your life and what lessons did you learn from it?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 20,
        "quote": "People are like stained glass windows. They sparkle and shine when the sun is out. But in the darkness, beauty is seen only if there is light within.",
        "author": "Anonymous",
        "question": "When was the darkest time in your life and what lessons did you learn from it?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 21,
    "front_text": "Get your friends to tell you your faults, or better still, welcome an enemy who will watch you keenly and sting you savagely. What a blessing such an irritating critic will be to a wise man, what an intolerable nuisance to a fool!",
    "back_text": "",
    "metadata": {
      "id": 21,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 21,
      "pairs": [
        {
          "left": "Get your friends to tell you your faults, or better still, welcome an enemy who will watch you keenly and sting you savagely. What a blessing such an irritating critic will be to a wise man, what an intolerable nuisance to a fool!",
          "right": ""
        },
        {
          "left": "- Charles Spurgeon",
          "right": ""
        },
        {
          "left": "What was the best criticism you ever got and how did it help you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 21,
        "quote": "Get your friends to tell you your faults, or better still, welcome an enemy who will watch you keenly and sting you savagely. What a blessing such an irritating critic will be to a wise man, what an intolerable nuisance to a fool!",
        "author": "Charles Spurgeon",
        "question": "What was the best criticism you ever got and how did it help you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 22,
    "front_text": "You will invest your life in something, or you will throw it away on nothing.",
    "back_text": "",
    "metadata": {
      "id": 22,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 22,
      "pairs": [
        {
          "left": "You will invest your life in something, or you will throw it away on nothing.",
          "right": ""
        },
        {
          "left": "- Haddon Robinson",
          "right": ""
        },
        {
          "left": "What is one thing you can invest your life on that will have a great impact?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 22,
        "quote": "You will invest your life in something, or you will throw it away on nothing.",
        "author": "Haddon Robinson",
        "question": "What is one thing you can invest your life on that will have a great impact?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 23,
    "front_text": "Let my heart be broken by the things that break the heart of God.",
    "back_text": "",
    "metadata": {
      "id": 23,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 23,
      "pairs": [
        {
          "left": "Let my heart be broken by the things that break the heart of God.",
          "right": ""
        },
        {
          "left": "- Bob Pierce",
          "right": ""
        },
        {
          "left": "What can we do so that we can constantly have a broken spirit and a contrite heart?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 23,
        "quote": "Let my heart be broken by the things that break the heart of God.",
        "author": "Bob Pierce",
        "question": "What can we do so that we can constantly have a broken spirit and a contrite heart?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 24,
    "front_text": "It is right to be contented with what we have, never with what we are.",
    "back_text": "",
    "metadata": {
      "id": 24,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 24,
      "pairs": [
        {
          "left": "It is right to be contented with what we have, never with what we are.",
          "right": ""
        },
        {
          "left": "- James Mackintosh",
          "right": ""
        },
        {
          "left": "How have you been trying to improve yourself or what can you do to constantly improve yourself?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 24,
        "quote": "It is right to be contented with what we have, never with what we are.",
        "author": "James Mackintosh",
        "question": "How have you been trying to improve yourself or what can you do to constantly improve yourself?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 25,
    "front_text": "In matters of style, swim with the current. In matters of principle, stand like a rock.",
    "back_text": "",
    "metadata": {
      "id": 25,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 25,
      "pairs": [
        {
          "left": "In matters of style, swim with the current. In matters of principle, stand like a rock.",
          "right": ""
        },
        {
          "left": "- Thomas Jefferson",
          "right": ""
        },
        {
          "left": "Share a time when you stood firm on your principle and was rewarded for it.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 25,
        "quote": "In matters of style, swim with the current. In matters of principle, stand like a rock.",
        "author": "Thomas Jefferson",
        "question": "Share a time when you stood firm on your principle and was rewarded for it."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 26,
    "front_text": "If one man calls you a donkey, pay him no mind. If two men call you a donkey, look for footprints. If three call you a donkey, get a saddle.",
    "back_text": "",
    "metadata": {
      "id": 26,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 26,
      "pairs": [
        {
          "left": "If one man calls you a donkey, pay him no mind. If two men call you a donkey, look for footprints. If three call you a donkey, get a saddle.",
          "right": ""
        },
        {
          "left": "- Unknown",
          "right": ""
        },
        {
          "left": "Share about how friends brought your attention to a blind area in your life and how you responded.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 26,
        "quote": "If one man calls you a donkey, pay him no mind. If two men call you a donkey, look for footprints. If three call you a donkey, get a saddle.",
        "author": "Unknown",
        "question": "Share about how friends brought your attention to a blind area in your life and how you responded."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 27,
    "front_text": "Whatever you have to say to people, be sure to say it in words that will cause them to smile and you will be on pretty safe ground. And when you do find it necessary to criticize someone, put your criticism in the form of a question which the other fellow is practically sure to have to answer in a manner that he becomes his own critic.",
    "back_text": "",
    "metadata": {
      "id": 27,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 27,
      "pairs": [
        {
          "left": "Whatever you have to say to people, be sure to say it in words that will cause them to smile and you will be on pretty safe ground. And when you do find it necessary to criticize someone, put your criticism in the form of a question which the other fellow is practically sure to have to answer in a manner that he becomes his own critic.",
          "right": ""
        },
        {
          "left": "- John Wanamaker",
          "right": ""
        },
        {
          "left": "Share about a time when somebody criticized you so constructively that you welcomed the criticism and benefitted from it.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 27,
        "quote": "Whatever you have to say to people, be sure to say it in words that will cause them to smile and you will be on pretty safe ground. And when you do find it necessary to criticize someone, put your criticism in the form of a question which the other fellow is practically sure to have to answer in a manner that he becomes his own critic.",
        "author": "John Wanamaker",
        "question": "Share about a time when somebody criticized you so constructively that you welcomed the criticism and benefitted from it."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 28,
    "front_text": "Give us grace, o god, to do the deed which we well know cries to be done. Let us not hesitate because of ease, or the words of men's mouths, or our own lives. Mighty causes are calling us... but they call with voices that mean work and sacrifice and death. Mercifully grant us, o god, the spirit of Esther, that we say, I will go unto the king and if I perish, I perish, amen.",
    "back_text": "",
    "metadata": {
      "id": 28,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 28,
      "pairs": [
        {
          "left": "Give us grace, o god, to do the deed which we well know cries to be done. Let us not hesitate because of ease, or the words of men's mouths, or our own lives. Mighty causes are calling us... but they call with voices that mean work and sacrifice and death. Mercifully grant us, o god, the spirit of Esther, that we say, I will go unto the king and if I perish, I perish, amen.",
          "right": ""
        },
        {
          "left": "- W.E.B. Dubois",
          "right": ""
        },
        {
          "left": "What is the most courageous thing you have ever done?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 28,
        "quote": "Give us grace, o god, to do the deed which we well know cries to be done. Let us not hesitate because of ease, or the words of men's mouths, or our own lives. Mighty causes are calling us... but they call with voices that mean work and sacrifice and death. Mercifully grant us, o god, the spirit of Esther, that we say, I will go unto the king and if I perish, I perish, amen.",
        "author": "W.E.B. Dubois",
        "question": "What is the most courageous thing you have ever done?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 29,
    "front_text": "If life is to have meaning, and if God's will is to be done, all of us have to accept who we are and what we are, give it back to God, and thank him for the way he made us. What I am is God's gift to me; what I do with it is my gift to him.",
    "back_text": "",
    "metadata": {
      "id": 29,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 29,
      "pairs": [
        {
          "left": "If life is to have meaning, and if God's will is to be done, all of us have to accept who we are and what we are, give it back to God, and thank him for the way he made us. What I am is God's gift to me; what I do with it is my gift to him.",
          "right": ""
        },
        {
          "left": "- Warren Wiersbe",
          "right": ""
        },
        {
          "left": "What words would you like to appear on your tombstone?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 29,
        "quote": "If life is to have meaning, and if God's will is to be done, all of us have to accept who we are and what we are, give it back to God, and thank him for the way he made us. What I am is God's gift to me; what I do with it is my gift to him.",
        "author": "Warren Wiersbe",
        "question": "What words would you like to appear on your tombstone?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 30,
    "front_text": "I shall study and prepare myself, and someday my chance will come.",
    "back_text": "",
    "metadata": {
      "id": 30,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 30,
      "pairs": [
        {
          "left": "I shall study and prepare myself, and someday my chance will come.",
          "right": ""
        },
        {
          "left": "- Abraham Lincoln",
          "right": ""
        },
        {
          "left": "If you had to prepare to achieve one important thing, what would that achievement be?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 30,
        "quote": "I shall study and prepare myself, and someday my chance will come.",
        "author": "Abraham Lincoln",
        "question": "If you had to prepare to achieve one important thing, what would that achievement be?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 31,
    "front_text": "If you want to enrich days, plant flowers; if you wish to enrich years, plant trees; if you wish to enrich eternity, plant ideals in the lives of others.",
    "back_text": "",
    "metadata": {
      "id": 31,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 31,
      "pairs": [
        {
          "left": "If you want to enrich days, plant flowers; if you wish to enrich years, plant trees; if you wish to enrich eternity, plant ideals in the lives of others.",
          "right": ""
        },
        {
          "left": "- Struett Cathy",
          "right": ""
        },
        {
          "left": "Who has influenced you the most in your life? How?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 31,
        "quote": "If you want to enrich days, plant flowers; if you wish to enrich years, plant trees; if you wish to enrich eternity, plant ideals in the lives of others.",
        "author": "Struett Cathy",
        "question": "Who has influenced you the most in your life? How?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 32,
    "front_text": "Spiritual things are not to be boasted of. One can boast of worldly riches, and paper money will not fly away unspent nor will the amount magically decrease, but the spiritual riches you boast of vanish with the telling.",
    "back_text": "",
    "metadata": {
      "id": 32,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 32,
      "pairs": [
        {
          "left": "Spiritual things are not to be boasted of. One can boast of worldly riches, and paper money will not fly away unspent nor will the amount magically decrease, but the spiritual riches you boast of vanish with the telling.",
          "right": ""
        },
        {
          "left": "- Watchman Nee",
          "right": ""
        },
        {
          "left": "Who is the most humble person you know? What makes this person so humble?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 32,
        "quote": "Spiritual things are not to be boasted of. One can boast of worldly riches, and paper money will not fly away unspent nor will the amount magically decrease, but the spiritual riches you boast of vanish with the telling.",
        "author": "Watchman Nee",
        "question": "Who is the most humble person you know? What makes this person so humble?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 33,
    "front_text": "Hope has two beautiful daughters. Their names are anger and courage; anger at the way things are, and courage to see that they do not remain the way they are.",
    "back_text": "",
    "metadata": {
      "id": 33,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 33,
      "pairs": [
        {
          "left": "Hope has two beautiful daughters. Their names are anger and courage; anger at the way things are, and courage to see that they do not remain the way they are.",
          "right": ""
        },
        {
          "left": "- Augustine",
          "right": ""
        },
        {
          "left": "Share about a person you know who has made a difference because he/she had the courage to stand up and make things different. What impact did this person make?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 33,
        "quote": "Hope has two beautiful daughters. Their names are anger and courage; anger at the way things are, and courage to see that they do not remain the way they are.",
        "author": "Augustine",
        "question": "Share about a person you know who has made a difference because he/she had the courage to stand up and make things different. What impact did this person make?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 34,
    "front_text": "I would rather be disagreed with by someone who understands me, than to be agreed with by someone who does not understand me.",
    "back_text": "",
    "metadata": {
      "id": 34,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 34,
      "pairs": [
        {
          "left": "I would rather be disagreed with by someone who understands me, than to be agreed with by someone who does not understand me.",
          "right": ""
        },
        {
          "left": "- James D. Glasse",
          "right": ""
        },
        {
          "left": "Who is the most understanding person you have ever met and what have you learned from him/her?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 34,
        "quote": "I would rather be disagreed with by someone who understands me, than to be agreed with by someone who does not understand me.",
        "author": "James D. Glasse",
        "question": "Who is the most understanding person you have ever met and what have you learned from him/her?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 35,
    "front_text": "Destiny is not a matter of chance; it is a matter of choice.",
    "back_text": "",
    "metadata": {
      "id": 35,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 35,
      "pairs": [
        {
          "left": "Destiny is not a matter of chance; it is a matter of choice.",
          "right": ""
        },
        {
          "left": "- William Jennings Bryan",
          "right": ""
        },
        {
          "left": "What would you like to have accomplished 5 years from now?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 35,
        "quote": "Destiny is not a matter of chance; it is a matter of choice.",
        "author": "William Jennings Bryan",
        "question": "What would you like to have accomplished 5 years from now?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 36,
    "front_text": "Integrity is keeping my commitment even if the circumstances when I made the commitment has changed.",
    "back_text": "",
    "metadata": {
      "id": 36,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 36,
      "pairs": [
        {
          "left": "Integrity is keeping my commitment even if the circumstances when I made the commitment has changed.",
          "right": ""
        },
        {
          "left": "- David Jeremiah",
          "right": ""
        },
        {
          "left": "What is the greatest example of integrity that you have seen in your life?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 36,
        "quote": "Integrity is keeping my commitment even if the circumstances when I made the commitment has changed.",
        "author": "David Jeremiah",
        "question": "What is the greatest example of integrity that you have seen in your life?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 37,
    "front_text": "This is the land of sin and death and tears... but up yonder is unceasing joy!",
    "back_text": "",
    "metadata": {
      "id": 37,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 37,
      "pairs": [
        {
          "left": "This is the land of sin and death and tears... but up yonder is unceasing joy!",
          "right": ""
        },
        {
          "left": "- D.L. Moody",
          "right": ""
        },
        {
          "left": "What excites you most about going to heaven?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 37,
        "quote": "This is the land of sin and death and tears... but up yonder is unceasing joy!",
        "author": "D.L. Moody",
        "question": "What excites you most about going to heaven?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 38,
    "front_text": "Do you wish to be great? Then begin by being. Do you desire to construct a vast and lofty fabric? Think first about the foundations of humility. The higher your structure is to be, the deeper must be its foundation.",
    "back_text": "",
    "metadata": {
      "id": 38,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 38,
      "pairs": [
        {
          "left": "Do you wish to be great? Then begin by being. Do you desire to construct a vast and lofty fabric? Think first about the foundations of humility. The higher your structure is to be, the deeper must be its foundation.",
          "right": ""
        },
        {
          "left": "- Augustine",
          "right": ""
        },
        {
          "left": "Who is the greatest man/woman of God of all the people you know? What makes this person great?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 38,
        "quote": "Do you wish to be great? Then begin by being. Do you desire to construct a vast and lofty fabric? Think first about the foundations of humility. The higher your structure is to be, the deeper must be its foundation.",
        "author": "Augustine",
        "question": "Who is the greatest man/woman of God of all the people you know? What makes this person great?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 39,
    "front_text": "He that is kind is free, though he is a slave; he that is evil is a slave, though he be a king.",
    "back_text": "",
    "metadata": {
      "id": 39,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 39,
      "pairs": [
        {
          "left": "He that is kind is free, though he is a slave; he that is evil is a slave, though he be a king.",
          "right": ""
        },
        {
          "left": "- Augustine",
          "right": ""
        },
        {
          "left": "Who is the kindest person that you know?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 39,
        "quote": "He that is kind is free, though he is a slave; he that is evil is a slave, though he be a king.",
        "author": "Augustine",
        "question": "Who is the kindest person that you know?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 40,
    "front_text": "Since love grows within you, so beauty grows. For love is the beauty of the soul.",
    "back_text": "",
    "metadata": {
      "id": 40,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 40,
      "pairs": [
        {
          "left": "Since love grows within you, so beauty grows. For love is the beauty of the soul.",
          "right": ""
        },
        {
          "left": "- Augustine",
          "right": ""
        },
        {
          "left": "Who would you say is the most beautiful person that you know? Why?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 40,
        "quote": "Since love grows within you, so beauty grows. For love is the beauty of the soul.",
        "author": "Augustine",
        "question": "Who would you say is the most beautiful person that you know? Why?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 41,
    "front_text": "Do not open your heart to every man, but discuss your affairs with one who is wise and who fears God.",
    "back_text": "",
    "metadata": {
      "id": 41,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 41,
      "pairs": [
        {
          "left": "Do not open your heart to every man, but discuss your affairs with one who is wise and who fears God.",
          "right": ""
        },
        {
          "left": "- Thomas a' Kempis",
          "right": ""
        },
        {
          "left": "What is the best advice you have ever received and from whom did you receive it?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 41,
        "quote": "Do not open your heart to every man, but discuss your affairs with one who is wise and who fears God.",
        "author": "Thomas a' Kempis",
        "question": "What is the best advice you have ever received and from whom did you receive it?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 42,
    "front_text": "Somehow, forty percent of churchgoers seem to have picked up the idea that singing in the church is for singers. The truth is that singing is for believers. The relevant question is not-do you have a voice? But- do you have a song?",
    "back_text": "",
    "metadata": {
      "id": 42,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 42,
      "pairs": [
        {
          "left": "Somehow, forty percent of churchgoers seem to have picked up the idea that singing in the church is for singers. The truth is that singing is for believers. The relevant question is not-do you have a voice? But- do you have a song?",
          "right": ""
        },
        {
          "left": "- Donald Hustad",
          "right": ""
        },
        {
          "left": "If you were a song, what would the lyrics of your song and the title of your song be?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 42,
        "quote": "Somehow, forty percent of churchgoers seem to have picked up the idea that singing in the church is for singers. The truth is that singing is for believers. The relevant question is not-do you have a voice? But- do you have a song?",
        "author": "Donald Hustad",
        "question": "If you were a song, what would the lyrics of your song and the title of your song be?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 43,
    "front_text": "Worship does not satisfy our hunger for God, it whets our appetite.",
    "back_text": "",
    "metadata": {
      "id": 43,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 43,
      "pairs": [
        {
          "left": "Worship does not satisfy our hunger for God, it whets our appetite.",
          "right": ""
        },
        {
          "left": "- Eugene Peterson",
          "right": ""
        },
        {
          "left": "Who is a person you know who always has a worshipful heart? What do you think is his/her secret?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 43,
        "quote": "Worship does not satisfy our hunger for God, it whets our appetite.",
        "author": "Eugene Peterson",
        "question": "Who is a person you know who always has a worshipful heart? What do you think is his/her secret?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 44,
    "front_text": "Anyone can love the ideal church. The challenge is to love the real church.",
    "back_text": "",
    "metadata": {
      "id": 44,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 44,
      "pairs": [
        {
          "left": "Anyone can love the ideal church. The challenge is to love the real church.",
          "right": ""
        },
        {
          "left": "- Bishop Joseph Mckinney",
          "right": ""
        },
        {
          "left": "Share about a person who hurt you or who quarreled with you yet who is now a good friend of yours.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 44,
        "quote": "Anyone can love the ideal church. The challenge is to love the real church.",
        "author": "Bishop Joseph Mckinney",
        "question": "Share about a person who hurt you or who quarreled with you yet who is now a good friend of yours."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 45,
    "front_text": "Faith does not operate in the realm of the possible. There is no glory for God in that which is humanly possible. Faith begins where man's power ends.",
    "back_text": "",
    "metadata": {
      "id": 45,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 45,
      "pairs": [
        {
          "left": "Faith does not operate in the realm of the possible. There is no glory for God in that which is humanly possible. Faith begins where man's power ends.",
          "right": ""
        },
        {
          "left": "- George Muller",
          "right": ""
        },
        {
          "left": "What is the most wonderful thing that you have seen God do?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 45,
        "quote": "Faith does not operate in the realm of the possible. There is no glory for God in that which is humanly possible. Faith begins where man's power ends.",
        "author": "George Muller",
        "question": "What is the most wonderful thing that you have seen God do?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 46,
    "front_text": "The spiritual poverty of the western world is much greater than the physical poverty of our people. You in the west have millions of people who suffer such terrible loneliness and emptiness.",
    "back_text": "",
    "metadata": {
      "id": 46,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 46,
      "pairs": [
        {
          "left": "The spiritual poverty of the western world is much greater than the physical poverty of our people. You in the west have millions of people who suffer such terrible loneliness and emptiness.",
          "right": ""
        },
        {
          "left": "- Mother Teresa",
          "right": ""
        },
        {
          "left": "Who is the richest person you know who suffers emptiness and loneliness because of spiritual poverty?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 46,
        "quote": "The spiritual poverty of the western world is much greater than the physical poverty of our people. You in the west have millions of people who suffer such terrible loneliness and emptiness.",
        "author": "Mother Teresa",
        "question": "Who is the richest person you know who suffers emptiness and loneliness because of spiritual poverty?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 47,
    "front_text": "Beware of anything that competes with loyalty to Jesus Christ. The greatest competitor of devotion to Jesus is service for him.",
    "back_text": "",
    "metadata": {
      "id": 47,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 47,
      "pairs": [
        {
          "left": "Beware of anything that competes with loyalty to Jesus Christ. The greatest competitor of devotion to Jesus is service for him.",
          "right": ""
        },
        {
          "left": "- Oswald Chambers",
          "right": ""
        },
        {
          "left": "How can you be alert so that you nourish both fellowship with Christ and service to Christ?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 47,
        "quote": "Beware of anything that competes with loyalty to Jesus Christ. The greatest competitor of devotion to Jesus is service for him.",
        "author": "Oswald Chambers",
        "question": "How can you be alert so that you nourish both fellowship with Christ and service to Christ?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 48,
    "front_text": "Nothing that is God's is obtainable by money.",
    "back_text": "",
    "metadata": {
      "id": 48,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 48,
      "pairs": [
        {
          "left": "Nothing that is God's is obtainable by money.",
          "right": ""
        },
        {
          "left": "- Tertullian",
          "right": ""
        },
        {
          "left": "If you were to ask God for 3 things, what would it be?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 48,
        "quote": "Nothing that is God's is obtainable by money.",
        "author": "Tertullian",
        "question": "If you were to ask God for 3 things, what would it be?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 49,
    "front_text": "No man knows what he is living for until he knows what he'll die for.",
    "back_text": "",
    "metadata": {
      "id": 49,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 49,
      "pairs": [
        {
          "left": "No man knows what he is living for until he knows what he'll die for.",
          "right": ""
        },
        {
          "left": "- Peter Pertocci",
          "right": ""
        },
        {
          "left": "What are 3 things you value most in this world?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 49,
        "quote": "No man knows what he is living for until he knows what he'll die for.",
        "author": "Peter Pertocci",
        "question": "What are 3 things you value most in this world?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-1",
    "sort_order": 50,
    "front_text": "Keep away from people who try to belittle your ambitions. Small people always do that, but the really great make you feel that you, too, can become great.",
    "back_text": "",
    "metadata": {
      "id": 50,
      "contentItemId": "game-inspirational-talk-1",
      "sortOrder": 50,
      "pairs": [
        {
          "left": "Keep away from people who try to belittle your ambitions. Small people always do that, but the really great make you feel that you, too, can become great.",
          "right": ""
        },
        {
          "left": "- Mark Twain",
          "right": ""
        },
        {
          "left": "Share about the most encouraging words that were said to you and how it affected your life?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 50,
        "quote": "Keep away from people who try to belittle your ambitions. Small people always do that, but the really great make you feel that you, too, can become great.",
        "author": "Mark Twain",
        "question": "Share about the most encouraging words that were said to you and how it affected your life?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 1,
    "front_text": "The Magi, who studied the stars, came from the east to Jerusalem and asked, \"Where is the baby born to be the King of the Jews? We have come to worship Him.\"",
    "back_text": "",
    "metadata": {
      "id": 1,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 1,
      "pairs": [
        {
          "left": "The Magi, who studied the stars, came from the east to Jerusalem and asked, \"Where is the baby born to be the King of the Jews? We have come to worship Him.\"",
          "right": ""
        },
        {
          "left": "What is the most important thing you have looked for?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 1,
        "quote": "The Magi, who studied the stars, came from the east to Jerusalem and asked, \"Where is the baby born to be the King of the Jews? We have come to worship Him.\"",
        "question": "What is the most important thing you have looked for?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 2,
    "front_text": "Mary Magdalene was crying outside the tomb when a man approached her and asked her why she was crying. Then Jesus called out, \"Mary!\"",
    "back_text": "",
    "metadata": {
      "id": 2,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 2,
      "pairs": [
        {
          "left": "Mary Magdalene was crying outside the tomb when a man approached her and asked her why she was crying. Then Jesus called out, \"Mary!\"",
          "right": ""
        },
        {
          "left": "Have you ever thought you lost someone, yet discovered that person joyfully again?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 2,
        "quote": "Mary Magdalene was crying outside the tomb when a man approached her and asked her why she was crying. Then Jesus called out, \"Mary!\"",
        "question": "Have you ever thought you lost someone, yet discovered that person joyfully again?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 3,
    "front_text": "Jesus said, \"The kingdom of heaven is like a mustard seed. It is the smallest of all seeds, but when it grows up, it is the biggest of all plants.\"",
    "back_text": "",
    "metadata": {
      "id": 3,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 3,
      "pairs": [
        {
          "left": "Jesus said, \"The kingdom of heaven is like a mustard seed. It is the smallest of all seeds, but when it grows up, it is the biggest of all plants.\"",
          "right": ""
        },
        {
          "left": "What is your biggest achievement in life?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 3,
        "quote": "Jesus said, \"The kingdom of heaven is like a mustard seed. It is the smallest of all seeds, but when it grows up, it is the biggest of all plants.\"",
        "question": "What is your biggest achievement in life?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 4,
    "front_text": "When Jesus preached in Capernaum, four friends of a paralyzed man cut a hole in the roof and lowered down the paralyzed man in front of Jesus. Jesus was pleased by their faith and healed the paralytic.",
    "back_text": "",
    "metadata": {
      "id": 4,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 4,
      "pairs": [
        {
          "left": "When Jesus preached in Capernaum, four friends of a paralyzed man cut a hole in the roof and lowered down the paralyzed man in front of Jesus. Jesus was pleased by their faith and healed the paralytic.",
          "right": ""
        },
        {
          "left": "Who are your close friends who would do the same thing for you, and you for them?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 4,
        "quote": "When Jesus preached in Capernaum, four friends of a paralyzed man cut a hole in the roof and lowered down the paralyzed man in front of Jesus. Jesus was pleased by their faith and healed the paralytic.",
        "question": "Who are your close friends who would do the same thing for you, and you for them?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 5,
    "front_text": "Peter was asked by Jesus 3 times, \"Do you love me?\" When Peter answered \"Yes\", Jesus said, \"Feed my sheep.\"",
    "back_text": "",
    "metadata": {
      "id": 5,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 5,
      "pairs": [
        {
          "left": "Peter was asked by Jesus 3 times, \"Do you love me?\" When Peter answered \"Yes\", Jesus said, \"Feed my sheep.\"",
          "right": ""
        },
        {
          "left": "What is the most important thing that you have ever been asked to do and what was the result?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 5,
        "quote": "Peter was asked by Jesus 3 times, \"Do you love me?\" When Peter answered \"Yes\", Jesus said, \"Feed my sheep.\"",
        "question": "What is the most important thing that you have ever been asked to do and what was the result?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 6,
    "front_text": "An angel appeared to the shepherds and said, \"This very day in David's town your Savior was born—Christ the Lord!\"",
    "back_text": "",
    "metadata": {
      "id": 6,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 6,
      "pairs": [
        {
          "left": "An angel appeared to the shepherds and said, \"This very day in David's town your Savior was born—Christ the Lord!\"",
          "right": ""
        },
        {
          "left": "What is the best news you have ever received?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 6,
        "quote": "An angel appeared to the shepherds and said, \"This very day in David's town your Savior was born—Christ the Lord!\"",
        "question": "What is the best news you have ever received?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 7,
    "front_text": "Peter was asked if he could give the lame man silver and gold. Peter replied, \"Silver and gold I do not have, but in the name of Jesus Christ get up and walk.\"",
    "back_text": "",
    "metadata": {
      "id": 7,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 7,
      "pairs": [
        {
          "left": "Peter was asked if he could give the lame man silver and gold. Peter replied, \"Silver and gold I do not have, but in the name of Jesus Christ get up and walk.\"",
          "right": ""
        },
        {
          "left": "Have you ever asked something from God and been given much more than you expected?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 7,
        "quote": "Peter was asked if he could give the lame man silver and gold. Peter replied, \"Silver and gold I do not have, but in the name of Jesus Christ get up and walk.\"",
        "question": "Have you ever asked something from God and been given much more than you expected?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 8,
    "front_text": "Saul was persecuting the followers of Jesus Christ when he was suddenly blinded by a light from heaven. Three days later, Ananias came and taught Saul about Jesus. Saul then began to preach that Jesus was the Son of God.",
    "back_text": "",
    "metadata": {
      "id": 8,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 8,
      "pairs": [
        {
          "left": "Saul was persecuting the followers of Jesus Christ when he was suddenly blinded by a light from heaven. Three days later, Ananias came and taught Saul about Jesus. Saul then began to preach that Jesus was the Son of God.",
          "right": ""
        },
        {
          "left": "Have you ever had a life changing experience that made you see things in a different way?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 8,
        "quote": "Saul was persecuting the followers of Jesus Christ when he was suddenly blinded by a light from heaven. Three days later, Ananias came and taught Saul about Jesus. Saul then began to preach that Jesus was the Son of God.",
        "question": "Have you ever had a life changing experience that made you see things in a different way?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 9,
    "front_text": "Jesus asked Peter, \"Who do you say I Am?\" Peter answered, \"You are the Messiah, the Son of the Living God.\"",
    "back_text": "",
    "metadata": {
      "id": 9,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 9,
      "pairs": [
        {
          "left": "Jesus asked Peter, \"Who do you say I Am?\" Peter answered, \"You are the Messiah, the Son of the Living God.\"",
          "right": ""
        },
        {
          "left": "What is the most wonderful thing that has been said about you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 9,
        "quote": "Jesus asked Peter, \"Who do you say I Am?\" Peter answered, \"You are the Messiah, the Son of the Living God.\"",
        "question": "What is the most wonderful thing that has been said about you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 10,
    "front_text": "John writes at the end of his gospel, \"These have been written in order that you may believe Jesus is the Messiah.\"",
    "back_text": "",
    "metadata": {
      "id": 10,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 10,
      "pairs": [
        {
          "left": "John writes at the end of his gospel, \"These have been written in order that you may believe Jesus is the Messiah.\"",
          "right": ""
        },
        {
          "left": "If a book was written about you, what would the book say? What would the title be?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 10,
        "quote": "John writes at the end of his gospel, \"These have been written in order that you may believe Jesus is the Messiah.\"",
        "question": "If a book was written about you, what would the book say? What would the title be?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 11,
    "front_text": "Zacchaeus climbed a Sycamore tree to get a glimpse of Jesus, and when Jesus arrived at where Zacchaeus was, Jesus said, \"I am coming to your house today.\"",
    "back_text": "",
    "metadata": {
      "id": 11,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 11,
      "pairs": [
        {
          "left": "Zacchaeus climbed a Sycamore tree to get a glimpse of Jesus, and when Jesus arrived at where Zacchaeus was, Jesus said, \"I am coming to your house today.\"",
          "right": ""
        },
        {
          "left": "Who is the greatest person you have ever met, and what impact did he/she have on you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 11,
        "quote": "Zacchaeus climbed a Sycamore tree to get a glimpse of Jesus, and when Jesus arrived at where Zacchaeus was, Jesus said, \"I am coming to your house today.\"",
        "question": "Who is the greatest person you have ever met, and what impact did he/she have on you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 12,
    "front_text": "When Jesus was being baptized, heaven was opened and a voice came down from heaven and said: \"You are my own dear Son. I am pleased with You.\"",
    "back_text": "",
    "metadata": {
      "id": 12,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 12,
      "pairs": [
        {
          "left": "When Jesus was being baptized, heaven was opened and a voice came down from heaven and said: \"You are my own dear Son. I am pleased with You.\"",
          "right": ""
        },
        {
          "left": "What is the best compliment you have ever received? And from whom?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 12,
        "quote": "When Jesus was being baptized, heaven was opened and a voice came down from heaven and said: \"You are my own dear Son. I am pleased with You.\"",
        "question": "What is the best compliment you have ever received? And from whom?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 13,
    "front_text": "Jesus said to Simon, \"You did not give me any water for my feet, but she wet my feet with her tears and wiped them with her hair. Therefore, I tell you, her many sins have been forgiven--for she loved much.\"",
    "back_text": "",
    "metadata": {
      "id": 13,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 13,
      "pairs": [
        {
          "left": "Jesus said to Simon, \"You did not give me any water for my feet, but she wet my feet with her tears and wiped them with her hair. Therefore, I tell you, her many sins have been forgiven--for she loved much.\"",
          "right": ""
        },
        {
          "left": "What is the most loving thing that has been done to you and that you have done to another?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 13,
        "quote": "Jesus said to Simon, \"You did not give me any water for my feet, but she wet my feet with her tears and wiped them with her hair. Therefore, I tell you, her many sins have been forgiven--for she loved much.\"",
        "question": "What is the most loving thing that has been done to you and that you have done to another?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 14,
    "front_text": "Jesus said: \"What good will it be for a man if he gains the whole world, yet forfeits his soul? Or what can a man give in exchange for his soul?\"",
    "back_text": "",
    "metadata": {
      "id": 14,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 14,
      "pairs": [
        {
          "left": "Jesus said: \"What good will it be for a man if he gains the whole world, yet forfeits his soul? Or what can a man give in exchange for his soul?\"",
          "right": ""
        },
        {
          "left": "What precious thing have you struggled to give up to God knowing that it was best for you to give it up?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 14,
        "quote": "Jesus said: \"What good will it be for a man if he gains the whole world, yet forfeits his soul? Or what can a man give in exchange for his soul?\"",
        "question": "What precious thing have you struggled to give up to God knowing that it was best for you to give it up?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 15,
    "front_text": "Jesus said, \"Greater love has no one than this, that he lay down his life for his friends.\"",
    "back_text": "",
    "metadata": {
      "id": 15,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 15,
      "pairs": [
        {
          "left": "Jesus said, \"Greater love has no one than this, that he lay down his life for his friends.\"",
          "right": ""
        },
        {
          "left": "Share about a close friend or a relative who sacrificed a lot for you because they loved you.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 15,
        "quote": "Jesus said, \"Greater love has no one than this, that he lay down his life for his friends.\"",
        "question": "Share about a close friend or a relative who sacrificed a lot for you because they loved you."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 16,
    "front_text": "A Roman Centurion asked Jesus to give a word so that his dear servant would be healed. Jesus said, \"I have never found faith like this, not even in Israel.\"",
    "back_text": "",
    "metadata": {
      "id": 16,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 16,
      "pairs": [
        {
          "left": "A Roman Centurion asked Jesus to give a word so that his dear servant would be healed. Jesus said, \"I have never found faith like this, not even in Israel.\"",
          "right": ""
        },
        {
          "left": "Among the people you know, who has the greatest faith? What is the secret of their great faith?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 16,
        "quote": "A Roman Centurion asked Jesus to give a word so that his dear servant would be healed. Jesus said, \"I have never found faith like this, not even in Israel.\"",
        "question": "Among the people you know, who has the greatest faith? What is the secret of their great faith?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 17,
    "front_text": "When Jesus asked Simon to push the boat deeper into the sea, Simon doubted Jesus. But when Simon realized he was wrong, he fell on his knees and said, \"Go away from a sinful man.\" But Jesus said to Simon, \"Don't be afraid, from now on you will be fishers of men.\"",
    "back_text": "",
    "metadata": {
      "id": 17,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 17,
      "pairs": [
        {
          "left": "When Jesus asked Simon to push the boat deeper into the sea, Simon doubted Jesus. But when Simon realized he was wrong, he fell on his knees and said, \"Go away from a sinful man.\" But Jesus said to Simon, \"Don't be afraid, from now on you will be fishers of men.\"",
          "right": ""
        },
        {
          "left": "Share about an important situation where you did not start well but where you finished well.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 17,
        "quote": "When Jesus asked Simon to push the boat deeper into the sea, Simon doubted Jesus. But when Simon realized he was wrong, he fell on his knees and said, \"Go away from a sinful man.\" But Jesus said to Simon, \"Don't be afraid, from now on you will be fishers of men.\"",
        "question": "Share about an important situation where you did not start well but where you finished well."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 18,
    "front_text": "Jesus was tempted by the devil for forty days. When the devil tempted Jesus in every way and found he could not prevail, he left Jesus.",
    "back_text": "",
    "metadata": {
      "id": 18,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 18,
      "pairs": [
        {
          "left": "Jesus was tempted by the devil for forty days. When the devil tempted Jesus in every way and found he could not prevail, he left Jesus.",
          "right": ""
        },
        {
          "left": "What is the greatest temptation you have faced? Where you were able to prevail?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 18,
        "quote": "Jesus was tempted by the devil for forty days. When the devil tempted Jesus in every way and found he could not prevail, he left Jesus.",
        "question": "What is the greatest temptation you have faced? Where you were able to prevail?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 19,
    "front_text": "The disciples returned with joy and said, \"Lord, even the demons submit to us in Your Name.\" Jesus said, \"Do not rejoice that the spirits submit to you, but rejoice that your names are written in heaven.\"",
    "back_text": "",
    "metadata": {
      "id": 19,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 19,
      "pairs": [
        {
          "left": "The disciples returned with joy and said, \"Lord, even the demons submit to us in Your Name.\" Jesus said, \"Do not rejoice that the spirits submit to you, but rejoice that your names are written in heaven.\"",
          "right": ""
        },
        {
          "left": "Name 5 people close to your heart who do not know God yet, but who you would like to see in heaven.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 19,
        "quote": "The disciples returned with joy and said, \"Lord, even the demons submit to us in Your Name.\" Jesus said, \"Do not rejoice that the spirits submit to you, but rejoice that your names are written in heaven.\"",
        "question": "Name 5 people close to your heart who do not know God yet, but who you would like to see in heaven."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 20,
    "front_text": "Jesus said, \"Whoever humbles himself like a child is the greatest in the kingdom of heaven.\"",
    "back_text": "",
    "metadata": {
      "id": 20,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 20,
      "pairs": [
        {
          "left": "Jesus said, \"Whoever humbles himself like a child is the greatest in the kingdom of heaven.\"",
          "right": ""
        },
        {
          "left": "Who is the most humble person you have known? Share your experience about this person.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 20,
        "quote": "Jesus said, \"Whoever humbles himself like a child is the greatest in the kingdom of heaven.\"",
        "question": "Who is the most humble person you have known? Share your experience about this person."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 21,
    "front_text": "Jesus was on a mountainside and the people were amazed when they saw the mute speaking, the crippled made well, the lame walking and the blind seeing. And they praised the God of Israel.",
    "back_text": "",
    "metadata": {
      "id": 21,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 21,
      "pairs": [
        {
          "left": "Jesus was on a mountainside and the people were amazed when they saw the mute speaking, the crippled made well, the lame walking and the blind seeing. And they praised the God of Israel.",
          "right": ""
        },
        {
          "left": "Share about a time when people praised God because of your service to them.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 21,
        "quote": "Jesus was on a mountainside and the people were amazed when they saw the mute speaking, the crippled made well, the lame walking and the blind seeing. And they praised the God of Israel.",
        "question": "Share about a time when people praised God because of your service to them."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 22,
    "front_text": "Parable of the lost coin.",
    "back_text": "",
    "metadata": {
      "id": 22,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 22,
      "pairs": [
        {
          "left": "Parable of the lost coin.",
          "right": ""
        },
        {
          "left": "Share about a person or thing that you lost but to your great joy was able to find again.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 22,
        "quote": "Parable of the lost coin.",
        "question": "Share about a person or thing that you lost but to your great joy was able to find again."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 23,
    "front_text": "When Jesus went into Levi's house, Pharisees complained that Jesus ate and drank with tax collectors and sinners. Jesus replied, \"I have not come to call...\"",
    "back_text": "",
    "metadata": {
      "id": 23,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 23,
      "pairs": [
        {
          "left": "When Jesus went into Levi's house, Pharisees complained that Jesus ate and drank with tax collectors and sinners. Jesus replied, \"I have not come to call...\"",
          "right": ""
        },
        {
          "left": "Share about a person you know who was a great sinner yet became a good servant of God.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 23,
        "quote": "When Jesus went into Levi's house, Pharisees complained that Jesus ate and drank with tax collectors and sinners. Jesus replied, \"I have not come to call...\"",
        "question": "Share about a person you know who was a great sinner yet became a good servant of God."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 24,
    "front_text": "Jesus was able to feed five thousand people using four loaves of bread and five fish.",
    "back_text": "",
    "metadata": {
      "id": 24,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 24,
      "pairs": [
        {
          "left": "Jesus was able to feed five thousand people using four loaves of bread and five fish.",
          "right": ""
        },
        {
          "left": "What is the greatest thing you have ever seen? And who accomplished it?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 24,
        "quote": "Jesus was able to feed five thousand people using four loaves of bread and five fish.",
        "question": "What is the greatest thing you have ever seen? And who accomplished it?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 25,
    "front_text": "Martha complained to Jesus that Mary was not helping her, but instead sat at the Lord's feet listening to what He said, \"Martha, Martha.\" The Lord answered, \"You are worried and upset about many things, but only one thing is needed. Mary has chosen what is better, and it will not be taken away from her.\"",
    "back_text": "",
    "metadata": {
      "id": 25,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 25,
      "pairs": [
        {
          "left": "Martha complained to Jesus that Mary was not helping her, but instead sat at the Lord's feet listening to what He said, \"Martha, Martha.\" The Lord answered, \"You are worried and upset about many things, but only one thing is needed. Mary has chosen what is better, and it will not be taken away from her.\"",
          "right": ""
        },
        {
          "left": "What can you do to spend more time with God in addition to doing things for God?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 25,
        "quote": "Martha complained to Jesus that Mary was not helping her, but instead sat at the Lord's feet listening to what He said, \"Martha, Martha.\" The Lord answered, \"You are worried and upset about many things, but only one thing is needed. Mary has chosen what is better, and it will not be taken away from her.\"",
        "question": "What can you do to spend more time with God in addition to doing things for God?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 26,
    "front_text": "Jesus said if you want to be great, you must be servant of all.",
    "back_text": "",
    "metadata": {
      "id": 26,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 26,
      "pairs": [
        {
          "left": "Jesus said if you want to be great, you must be servant of all.",
          "right": ""
        },
        {
          "left": "Who is the greatest person you have ever known? What made this person great?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 26,
        "quote": "Jesus said if you want to be great, you must be servant of all.",
        "question": "Who is the greatest person you have ever known? What made this person great?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 27,
    "front_text": "The leper was thankful for being healed.",
    "back_text": "",
    "metadata": {
      "id": 27,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 27,
      "pairs": [
        {
          "left": "The leper was thankful for being healed.",
          "right": ""
        },
        {
          "left": "What is the best gift you have received? And have given?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 27,
        "quote": "The leper was thankful for being healed.",
        "question": "What is the best gift you have received? And have given?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 28,
    "front_text": "\"I tell you the truth,\" Jesus said, \"This poor widow has put in more than all the others. All these people gave their gifts out of their wealth; but she, out of her poverty put in all she had to live on.\"",
    "back_text": "",
    "metadata": {
      "id": 28,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 28,
      "pairs": [
        {
          "left": "\"I tell you the truth,\" Jesus said, \"This poor widow has put in more than all the others. All these people gave their gifts out of their wealth; but she, out of her poverty put in all she had to live on.\"",
          "right": ""
        },
        {
          "left": "Share about the most generous person you have ever known.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 28,
        "quote": "\"I tell you the truth,\" Jesus said, \"This poor widow has put in more than all the others. All these people gave their gifts out of their wealth; but she, out of her poverty put in all she had to live on.\"",
        "question": "Share about the most generous person you have ever known."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 29,
    "front_text": "John the Baptist was waiting for Jesus to begin His ministry, and when Jesus appeared, John said: \"The friend who attends the bridegroom waits and listens for Him, and is full of joy when He hears the bridegroom's voice. That joy is mine, and it is now complete.\"",
    "back_text": "",
    "metadata": {
      "id": 29,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 29,
      "pairs": [
        {
          "left": "John the Baptist was waiting for Jesus to begin His ministry, and when Jesus appeared, John said: \"The friend who attends the bridegroom waits and listens for Him, and is full of joy when He hears the bridegroom's voice. That joy is mine, and it is now complete.\"",
          "right": ""
        },
        {
          "left": "What was the happiest moment in your life? What made you so happy?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 29,
        "quote": "John the Baptist was waiting for Jesus to begin His ministry, and when Jesus appeared, John said: \"The friend who attends the bridegroom waits and listens for Him, and is full of joy when He hears the bridegroom's voice. That joy is mine, and it is now complete.\"",
        "question": "What was the happiest moment in your life? What made you so happy?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 30,
    "front_text": "For God so loved the world that He gave his one and only Son, that whoever believes in Him shall not perish but have eternal life.",
    "back_text": "",
    "metadata": {
      "id": 30,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 30,
      "pairs": [
        {
          "left": "For God so loved the world that He gave his one and only Son, that whoever believes in Him shall not perish but have eternal life.",
          "right": ""
        },
        {
          "left": "What is the most loving deed that you have seen in your life? Why did the person do it?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 30,
        "quote": "For God so loved the world that He gave his one and only Son, that whoever believes in Him shall not perish but have eternal life.",
        "question": "What is the most loving deed that you have seen in your life? Why did the person do it?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 31,
    "front_text": "Jesus said, \"I am the good shepherd, the good shepherd lays down His life for the sheep.\"",
    "back_text": "",
    "metadata": {
      "id": 31,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 31,
      "pairs": [
        {
          "left": "Jesus said, \"I am the good shepherd, the good shepherd lays down His life for the sheep.\"",
          "right": ""
        },
        {
          "left": "What would you give up your life for?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 31,
        "quote": "Jesus said, \"I am the good shepherd, the good shepherd lays down His life for the sheep.\"",
        "question": "What would you give up your life for?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 32,
    "front_text": "Luke said, \"That he recorded his writings so that Theophilus may know the certainty of the things he was taught.\"",
    "back_text": "",
    "metadata": {
      "id": 32,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 32,
      "pairs": [
        {
          "left": "Luke said, \"That he recorded his writings so that Theophilus may know the certainty of the things he was taught.\"",
          "right": ""
        },
        {
          "left": "If you were to write a book about an important event you have witnessed, what event would that be?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 32,
        "quote": "Luke said, \"That he recorded his writings so that Theophilus may know the certainty of the things he was taught.\"",
        "question": "If you were to write a book about an important event you have witnessed, what event would that be?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 33,
    "front_text": "The disciples said to Jesus, \"You are the Messiah, the Son of the Living God.\"",
    "back_text": "",
    "metadata": {
      "id": 33,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 33,
      "pairs": [
        {
          "left": "The disciples said to Jesus, \"You are the Messiah, the Son of the Living God.\"",
          "right": ""
        },
        {
          "left": "Share about the person who you admire the most in your life.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 33,
        "quote": "The disciples said to Jesus, \"You are the Messiah, the Son of the Living God.\"",
        "question": "Share about the person who you admire the most in your life."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 34,
    "front_text": "The apostles were brought before the Sanhedrin, and was commanded by the high priest not to teach the good news. Peter and the other apostles replied, \"We must obey God rather than men!\"",
    "back_text": "",
    "metadata": {
      "id": 34,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 34,
      "pairs": [
        {
          "left": "The apostles were brought before the Sanhedrin, and was commanded by the high priest not to teach the good news. Peter and the other apostles replied, \"We must obey God rather than men!\"",
          "right": ""
        },
        {
          "left": "Share about an incident where you had a tough choice to make, yet you obeyed God rather than men.",
          "right": ""
        }
      ],
      "source_card": {
        "id": 34,
        "quote": "The apostles were brought before the Sanhedrin, and was commanded by the high priest not to teach the good news. Peter and the other apostles replied, \"We must obey God rather than men!\"",
        "question": "Share about an incident where you had a tough choice to make, yet you obeyed God rather than men."
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 35,
    "front_text": "A lame beggar asked Peter for money, and Peter said, \"Silver and gold I do not have, but in the name of Jesus Christ, walk.\" When Peter healed the lame beggar, the beggar went with them into the temple courts, walking and jumping, and praising God.",
    "back_text": "",
    "metadata": {
      "id": 35,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 35,
      "pairs": [
        {
          "left": "A lame beggar asked Peter for money, and Peter said, \"Silver and gold I do not have, but in the name of Jesus Christ, walk.\" When Peter healed the lame beggar, the beggar went with them into the temple courts, walking and jumping, and praising God.",
          "right": ""
        },
        {
          "left": "What was the most joyful thing that you have seen in your life?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 35,
        "quote": "A lame beggar asked Peter for money, and Peter said, \"Silver and gold I do not have, but in the name of Jesus Christ, walk.\" When Peter healed the lame beggar, the beggar went with them into the temple courts, walking and jumping, and praising God.",
        "question": "What was the most joyful thing that you have seen in your life?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 36,
    "front_text": "If any of you lacks wisdom, he should ask God, who gives generously to all without finding fault, and it will be given to him.",
    "back_text": "",
    "metadata": {
      "id": 36,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 36,
      "pairs": [
        {
          "left": "If any of you lacks wisdom, he should ask God, who gives generously to all without finding fault, and it will be given to him.",
          "right": ""
        },
        {
          "left": "What knowledge or skill do you desire most from God? Why?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 36,
        "quote": "If any of you lacks wisdom, he should ask God, who gives generously to all without finding fault, and it will be given to him.",
        "question": "What knowledge or skill do you desire most from God? Why?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 37,
    "front_text": "Then Jesus cried out, \"When a man believes in me, he does not believe in me only, but in the one who sent me. I have come into the world as a light, so that no one who believes in me should stay in darkness.\"",
    "back_text": "",
    "metadata": {
      "id": 37,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 37,
      "pairs": [
        {
          "left": "Then Jesus cried out, \"When a man believes in me, he does not believe in me only, but in the one who sent me. I have come into the world as a light, so that no one who believes in me should stay in darkness.\"",
          "right": ""
        },
        {
          "left": "What is a very important truth that you now realize which you did not know during your younger days?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 37,
        "quote": "Then Jesus cried out, \"When a man believes in me, he does not believe in me only, but in the one who sent me. I have come into the world as a light, so that no one who believes in me should stay in darkness.\"",
        "question": "What is a very important truth that you now realize which you did not know during your younger days?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 38,
    "front_text": "The wise men opened their treasures and presented the baby Jesus with gifts of gold and of incense and of myrrh.",
    "back_text": "",
    "metadata": {
      "id": 38,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 38,
      "pairs": [
        {
          "left": "The wise men opened their treasures and presented the baby Jesus with gifts of gold and of incense and of myrrh.",
          "right": ""
        },
        {
          "left": "If you could have been with the wise men when they visited Jesus, what personal possession would you have taken with you as a gift? Or what gift would you have brought with you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 38,
        "quote": "The wise men opened their treasures and presented the baby Jesus with gifts of gold and of incense and of myrrh.",
        "question": "If you could have been with the wise men when they visited Jesus, what personal possession would you have taken with you as a gift? Or what gift would you have brought with you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 39,
    "front_text": "When Jesus had finished washing their feet, He put on his clothes and returned to His place and said, \"Now that I, your Lord and Teacher, have washed your feet, you also should wash one another's feet. I have set you an example that you should do as I have done for you.\"",
    "back_text": "",
    "metadata": {
      "id": 39,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 39,
      "pairs": [
        {
          "left": "When Jesus had finished washing their feet, He put on his clothes and returned to His place and said, \"Now that I, your Lord and Teacher, have washed your feet, you also should wash one another's feet. I have set you an example that you should do as I have done for you.\"",
          "right": ""
        },
        {
          "left": "What is the most touching service that anyone has done for you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 39,
        "quote": "When Jesus had finished washing their feet, He put on his clothes and returned to His place and said, \"Now that I, your Lord and Teacher, have washed your feet, you also should wash one another's feet. I have set you an example that you should do as I have done for you.\"",
        "question": "What is the most touching service that anyone has done for you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 40,
    "front_text": "One night the Lord spoke to Paul in a vision: \"Do not be afraid; keep on speaking, do not be silent. For I am with you, and no one is going to attack and harm you.\"",
    "back_text": "",
    "metadata": {
      "id": 40,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 40,
      "pairs": [
        {
          "left": "One night the Lord spoke to Paul in a vision: \"Do not be afraid; keep on speaking, do not be silent. For I am with you, and no one is going to attack and harm you.\"",
          "right": ""
        },
        {
          "left": "What is the most memorable message that God has ever relayed to you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 40,
        "quote": "One night the Lord spoke to Paul in a vision: \"Do not be afraid; keep on speaking, do not be silent. For I am with you, and no one is going to attack and harm you.\"",
        "question": "What is the most memorable message that God has ever relayed to you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 41,
    "front_text": "The apostles left the Sanhedrin, rejoicing because they had been counted worthy of suffering disgrace for the Name.",
    "back_text": "",
    "metadata": {
      "id": 41,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 41,
      "pairs": [
        {
          "left": "The apostles left the Sanhedrin, rejoicing because they had been counted worthy of suffering disgrace for the Name.",
          "right": ""
        },
        {
          "left": "What was the most difficult persecution that you have encountered? How did you deal with it?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 41,
        "quote": "The apostles left the Sanhedrin, rejoicing because they had been counted worthy of suffering disgrace for the Name.",
        "question": "What was the most difficult persecution that you have encountered? How did you deal with it?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 42,
    "front_text": "James 1:19 says: \"My dear brothers, take note of this: Everyone should be quick to listen, slow to speak and slow to become angry, for man's anger does not bring about the righteous life that God desires.\"",
    "back_text": "",
    "metadata": {
      "id": 42,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 42,
      "pairs": [
        {
          "left": "James 1:19 says: \"My dear brothers, take note of this: Everyone should be quick to listen, slow to speak and slow to become angry, for man's anger does not bring about the righteous life that God desires.\"",
          "right": ""
        },
        {
          "left": "Share about a person who brings out the best in others. How does he/she do it?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 42,
        "quote": "James 1:19 says: \"My dear brothers, take note of this: Everyone should be quick to listen, slow to speak and slow to become angry, for man's anger does not bring about the righteous life that God desires.\"",
        "question": "Share about a person who brings out the best in others. How does he/she do it?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 43,
    "front_text": "Jesus preached the Sermon on the mount, and the teachings, which were about humility, meekness and love.",
    "back_text": "",
    "metadata": {
      "id": 43,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 43,
      "pairs": [
        {
          "left": "Jesus preached the Sermon on the mount, and the teachings, which were about humility, meekness and love.",
          "right": ""
        },
        {
          "left": "What was the best sermon you have ever heard? What was it about?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 43,
        "quote": "Jesus preached the Sermon on the mount, and the teachings, which were about humility, meekness and love.",
        "question": "What was the best sermon you have ever heard? What was it about?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 44,
    "front_text": "Jesus called His twelve disciples to Him and gave them authority to drive out evil spirits and to heal every disease and sickness.",
    "back_text": "",
    "metadata": {
      "id": 44,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 44,
      "pairs": [
        {
          "left": "Jesus called His twelve disciples to Him and gave them authority to drive out evil spirits and to heal every disease and sickness.",
          "right": ""
        },
        {
          "left": "If you have to pick 3 people to do an important task, who would you choose?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 44,
        "quote": "Jesus called His twelve disciples to Him and gave them authority to drive out evil spirits and to heal every disease and sickness.",
        "question": "If you have to pick 3 people to do an important task, who would you choose?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 45,
    "front_text": "The disciples came to Jesus and asked, \"Why do You speak to the people in parables?\" He replied, \"The knowledge of the secrets of the kingdom of heaven has been given to you.\"",
    "back_text": "",
    "metadata": {
      "id": 45,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 45,
      "pairs": [
        {
          "left": "The disciples came to Jesus and asked, \"Why do You speak to the people in parables?\" He replied, \"The knowledge of the secrets of the kingdom of heaven has been given to you.\"",
          "right": ""
        },
        {
          "left": "What is your favorite parable? Why?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 45,
        "quote": "The disciples came to Jesus and asked, \"Why do You speak to the people in parables?\" He replied, \"The knowledge of the secrets of the kingdom of heaven has been given to you.\"",
        "question": "What is your favorite parable? Why?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 46,
    "front_text": "Jesus said, \"It is not the healthy who need a doctor, but the sick. I have not come to call the righteous, but sinners to repentance.\"",
    "back_text": "",
    "metadata": {
      "id": 46,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 46,
      "pairs": [
        {
          "left": "Jesus said, \"It is not the healthy who need a doctor, but the sick. I have not come to call the righteous, but sinners to repentance.\"",
          "right": ""
        },
        {
          "left": "What purposes define your life?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 46,
        "quote": "Jesus said, \"It is not the healthy who need a doctor, but the sick. I have not come to call the righteous, but sinners to repentance.\"",
        "question": "What purposes define your life?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 47,
    "front_text": "The fruit of the Spirit is love, joy, peace...",
    "back_text": "",
    "metadata": {
      "id": 47,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 47,
      "pairs": [
        {
          "left": "The fruit of the Spirit is love, joy, peace...",
          "right": ""
        },
        {
          "left": "What is the quality you most like in a man/woman?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 47,
        "quote": "The fruit of the Spirit is love, joy, peace...",
        "question": "What is the quality you most like in a man/woman?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 48,
    "front_text": "At the wedding in Cana, Jesus turned the water into wine, and the master said it is the best wine he had ever tasted.",
    "back_text": "",
    "metadata": {
      "id": 48,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 48,
      "pairs": [
        {
          "left": "At the wedding in Cana, Jesus turned the water into wine, and the master said it is the best wine he had ever tasted.",
          "right": ""
        },
        {
          "left": "What is the greatest transformation you have ever seen or experienced?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 48,
        "quote": "At the wedding in Cana, Jesus turned the water into wine, and the master said it is the best wine he had ever tasted.",
        "question": "What is the greatest transformation you have ever seen or experienced?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 49,
    "front_text": "Jesus asked Peter three times if Peter loved Him. Each time Peter said that he did.",
    "back_text": "",
    "metadata": {
      "id": 49,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 49,
      "pairs": [
        {
          "left": "Jesus asked Peter three times if Peter loved Him. Each time Peter said that he did.",
          "right": ""
        },
        {
          "left": "From whom do you want most to hear that they love you?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 49,
        "quote": "Jesus asked Peter three times if Peter loved Him. Each time Peter said that he did.",
        "question": "From whom do you want most to hear that they love you?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 50,
    "front_text": "All the believers were together and had everything in common. Selling their possessions and goods, they gave to anyone as he had need. They broke bread in their homes and ate together with glad and sincere hearts, praising God and enjoying the favor of all the people. And the Lord added to their number daily those who were being saved.",
    "back_text": "",
    "metadata": {
      "id": 50,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 50,
      "pairs": [
        {
          "left": "All the believers were together and had everything in common. Selling their possessions and goods, they gave to anyone as he had need. They broke bread in their homes and ate together with glad and sincere hearts, praising God and enjoying the favor of all the people. And the Lord added to their number daily those who were being saved.",
          "right": ""
        },
        {
          "left": "What is the most beautiful thing you have ever been part of?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 50,
        "quote": "All the believers were together and had everything in common. Selling their possessions and goods, they gave to anyone as he had need. They broke bread in their homes and ate together with glad and sincere hearts, praising God and enjoying the favor of all the people. And the Lord added to their number daily those who were being saved.",
        "question": "What is the most beautiful thing you have ever been part of?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 51,
    "front_text": "A few days before He was crucified, Jesus had a last supper with His disciples.",
    "back_text": "",
    "metadata": {
      "id": 51,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 51,
      "pairs": [
        {
          "left": "A few days before He was crucified, Jesus had a last supper with His disciples.",
          "right": ""
        },
        {
          "left": "Who among your friends would you most like to have a dinner with?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 51,
        "quote": "A few days before He was crucified, Jesus had a last supper with His disciples.",
        "question": "Who among your friends would you most like to have a dinner with?"
      }
    }
  },
  {
    "game_id": "game-inspirational-talk-2",
    "sort_order": 52,
    "front_text": "In the parable of the talents, the Lord said unto him, \"Well done, thou good and faithful servant: Thou hast been faithful over a few things, I will make thee ruler over many things: Enter thou into the joy of thy Lord.\"",
    "back_text": "",
    "metadata": {
      "id": 52,
      "contentItemId": "game-inspirational-talk-2",
      "sortOrder": 52,
      "pairs": [
        {
          "left": "In the parable of the talents, the Lord said unto him, \"Well done, thou good and faithful servant: Thou hast been faithful over a few things, I will make thee ruler over many things: Enter thou into the joy of thy Lord.\"",
          "right": ""
        },
        {
          "left": "How would you like to be greeted upon entering heaven?",
          "right": ""
        }
      ],
      "source_card": {
        "id": 52,
        "quote": "In the parable of the talents, the Lord said unto him, \"Well done, thou good and faithful servant: Thou hast been faithful over a few things, I will make thee ruler over many things: Enter thou into the joy of thy Lord.\"",
        "question": "How would you like to be greeted upon entering heaven?"
      }
    }
  }
]$game_cards$::jsonb) as seed(
  game_id text, sort_order integer, front_text text, back_text text, metadata jsonb
)
on conflict (game_id, sort_order) do update set
  front_text = excluded.front_text,
  back_text = excluded.back_text,
  metadata = excluded.metadata;

insert into public.game_placements (game_id, pillar_id, category_id, sort_order)
select
  g.id,
  p.id,
  c.id,
  g.sort_order
from public.games g
cross join public.pillars p
join public.categories c
  on c.pillar_id = p.id
  and lower(trim(c.name)) = 'games'
where lower(trim(p.name)) in ('family', 'work', 'ministry')
  and g.id in (
    'game-bible-action',
    'game-bible-draw',
    'game-bible-groups',
    'game-bible-proverbs',
    'game-bible-question',
    'game-bible-talk',
    'game-inspirational-talk-1',
    'game-inspirational-talk-2'
  )
on conflict (game_id, pillar_id, category_id) do update
set sort_order = excluded.sort_order;

revoke all on table
  public.games,
  public.game_placements,
  public.game_rules,
  public.game_cards
from public, anon, authenticated;

grant select, insert, update, delete on table
  public.games,
  public.game_placements,
  public.game_rules,
  public.game_cards
to authenticated;

grant all on table
  public.games,
  public.game_placements,
  public.game_rules,
  public.game_cards
to service_role;

alter table public.games enable row level security;
alter table public.game_placements enable row level security;
alter table public.game_rules enable row level security;
alter table public.game_cards enable row level security;

drop policy if exists games_authenticated_select on public.games;
create policy games_authenticated_select
  on public.games for select to authenticated
  using (
    is_active
    or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  );

drop policy if exists games_admin_manage on public.games;
create policy games_admin_manage
  on public.games for all to authenticated
  using (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'))
  with check (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'));

drop policy if exists game_placements_authenticated_select on public.game_placements;
create policy game_placements_authenticated_select
  on public.game_placements for select to authenticated
  using (
    exists (
      select 1
      from public.games g
      where g.id = game_placements.game_id
        and (
          g.is_active
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
        )
    )
  );

drop policy if exists game_placements_admin_manage on public.game_placements;
create policy game_placements_admin_manage
  on public.game_placements for all to authenticated
  using (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'))
  with check (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'));

drop policy if exists game_rules_authenticated_select on public.game_rules;
create policy game_rules_authenticated_select
  on public.game_rules for select to authenticated
  using (
    exists (
      select 1
      from public.games g
      where g.id = game_rules.game_id
        and (
          g.is_active
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
        )
    )
  );

drop policy if exists game_rules_admin_manage on public.game_rules;
create policy game_rules_admin_manage
  on public.game_rules for all to authenticated
  using (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'))
  with check (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'));

drop policy if exists game_cards_authenticated_select on public.game_cards;
create policy game_cards_authenticated_select
  on public.game_cards for select to authenticated
  using (
    exists (
      select 1
      from public.games g
      where g.id = game_cards.game_id
        and (
          g.is_active
          or coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
        )
    )
  );

drop policy if exists game_cards_admin_manage on public.game_cards;
create policy game_cards_admin_manage
  on public.game_cards for all to authenticated
  using (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'))
  with check (coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin'));

drop policy if exists game_assets_active_read on storage.objects;
create policy game_assets_active_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'game-assets'
    and (storage.foldername(name))[1] = 'games'
    and exists (
      select 1
      from public.games g
      where g.id = (storage.foldername(name))[2]
        and g.is_active
    )
  );

drop policy if exists game_assets_admin_manage on storage.objects;
create policy game_assets_admin_manage
  on storage.objects for all to authenticated
  using (
    bucket_id = 'game-assets'
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  )
  with check (
    bucket_id = 'game-assets'
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') in ('admin', 'super_admin')
  );

do $$
declare
  expected record;
  actual_count integer;
begin
  if exists (
    select 1
    from (values
      ('game-bible-action'),
      ('game-bible-draw'),
      ('game-bible-groups'),
      ('game-bible-proverbs'),
      ('game-bible-question'),
      ('game-bible-talk'),
      ('game-inspirational-talk-1'),
      ('game-inspirational-talk-2')
    ) as expected_games(game_id)
    left join public.games g on g.id = expected_games.game_id
    where g.id is null
  ) then
    raise exception 'One or more canonical seeded games are missing.';
  end if;

  for expected in
    select * from (values
      ('game-bible-action', 50),
      ('game-bible-draw', 50),
      ('game-bible-groups', 50),
      ('game-bible-proverbs', 50),
      ('game-bible-question', 50),
      ('game-bible-talk', 250),
      ('game-inspirational-talk-1', 50),
      ('game-inspirational-talk-2', 52)
    ) as expected_counts(game_id, card_count)
  loop
    select count(*) into actual_count
    from public.game_cards
    where game_id = expected.game_id;
    if actual_count <> expected.card_count then
      raise exception 'Unexpected card count for %: expected %, got %.',
        expected.game_id, expected.card_count, actual_count;
    end if;

    select count(*) into actual_count
    from public.game_rules
    where game_id = expected.game_id;
    if actual_count <> 1 then
      raise exception 'Expected one source rules record for %, got %.',
        expected.game_id, actual_count;
    end if;
  end loop;

  if exists (
    select 1
    from (values
      ('game-bible-action'),
      ('game-bible-draw'),
      ('game-bible-groups'),
      ('game-bible-proverbs'),
      ('game-bible-question'),
      ('game-bible-talk'),
      ('game-inspirational-talk-1'),
      ('game-inspirational-talk-2')
    ) as expected_games(game_id)
    cross join (values ('Family'), ('Work'), ('Ministry')) as expected_pillars(name)
    left join public.pillars p
      on lower(trim(p.name)) = lower(trim(expected_pillars.name))
    left join public.categories c
      on c.pillar_id = p.id
      and lower(trim(c.name)) = 'games'
    left join public.game_placements gp
      on gp.game_id = expected_games.game_id
      and gp.pillar_id = p.id
      and gp.category_id = c.id
    where p.id is null or c.id is null or gp.id is null
  ) then
    raise exception 'A canonical game is missing a Family/Work/Ministry Games placement.';
  end if;

  if exists (
    select 1
    from public.game_cards
    group by game_id, sort_order
    having count(*) > 1
  ) then
    raise exception 'Duplicate (game_id, sort_order) game cards found.';
  end if;

  if exists (
    select 1 from public.game_cards gc
    left join public.games g on g.id = gc.game_id
    where g.id is null
  ) or exists (
    select 1 from public.game_placements gp
    left join public.games g on g.id = gp.game_id
    left join public.pillars p on p.id = gp.pillar_id
    left join public.categories c on c.id = gp.category_id
    where g.id is null or p.id is null or c.id is null
  ) then
    raise exception 'Unknown game, pillar, or category reference found in game content.';
  end if;
end;
$$;

commit;
