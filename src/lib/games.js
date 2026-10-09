import { supabase } from "./supabase";

export async function createGame(game) {
  const { data, error } = await supabase
    .from("games")
    .insert({
      id: game.id,
      title: game.title,
      game_type: game.game_type,
      subtitle: game.subtitle || null,
      description: game.description || null,
      sort_order: game.sort_order,
      price: Number(game.price) || 0,
      is_locked: true
    })
    .select("id,title,subtitle,description,cover_image_url,game_type,is_locked,price,sort_order,created_at,updated_at")
    .single();

  if (error?.code === "23505") {
    throw new Error("A game with this ID already exists.");
  }
  if (error) {
    console.error("Game creation failed.", { code: error.code || "UNKNOWN" });
    throw new Error("Unable to create the game. Please try again.");
  }
  return data;
}

export async function listGamesWithCounts() {
  const [
    { data: games, error: gamesError },
    { data: pillars, error: pillarsError },
    { data: placements, error: placementsError }
  ] = await Promise.all([
    supabase
      .from("games")
      .select("id,title,subtitle,description,cover_image_url,game_type,is_locked,price,sort_order,created_at,updated_at")
      .order("sort_order", { ascending: true }),
    supabase.from("pillars").select("id,name").order("name", { ascending: true }),
    supabase.from("game_placements").select("game_id,pillar_id")
  ]);

  if (gamesError) throw gamesError;
  if (pillarsError) throw pillarsError;
  if (placementsError) throw placementsError;

  const counts = await Promise.all((games || []).map(async (game) => {
    const { count, error } = await supabase
      .from("game_cards")
      .select("id", { count: "exact", head: true })
      .eq("game_id", game.id);

    if (error) throw error;
    return [game.id, count || 0];
  }));

  const cardCounts = new Map(counts);
  const placementCounts = new Map();
  for (const placement of placements || []) {
    placementCounts.set(
      placement.game_id,
      (placementCounts.get(placement.game_id) || 0) + 1
    );
  }

  return {
    games: (games || []).map((game) => ({
      ...game,
      cardCount: cardCounts.get(game.id) || 0,
      placementCount: placementCounts.get(game.id) || 0,
      pillarIds: (placements || [])
        .filter((placement) => placement.game_id === game.id)
        .map((placement) => placement.pillar_id)
    })),
    pillars: pillars || []
  };
}

export async function loadGameDetails(gameId) {
  const [
    { data: rules, error: rulesError },
    { data: cards, error: cardsError },
    { data: placements, error: placementsError }
  ] = await Promise.all([
    supabase
      .from("game_rules")
      .select("id,game_id,sort_order,rule_text,metadata,created_at,updated_at")
      .eq("game_id", gameId)
      .order("sort_order", { ascending: true }),
    supabase
      .from("game_cards")
      .select("id,game_id,sort_order,front_text,back_text,metadata")
      .eq("game_id", gameId)
      .order("sort_order", { ascending: true }),
    supabase
      .from("game_placements")
      .select("id,pillar_id,category_id,sort_order")
      .eq("game_id", gameId)
      .order("sort_order", { ascending: true })
  ]);

  return {
    rules: { data: rules || [], error: rulesError },
    cards: { data: cards || [], error: cardsError },
    placements: { data: placements || [], error: placementsError }
  };
}

export async function loadPlacementNames(placements) {
  const pillarIds = [...new Set(placements.map((placement) => placement.pillar_id))];
  const categoryIds = [...new Set(placements.map((placement) => placement.category_id))];
  if (pillarIds.length === 0 || categoryIds.length === 0) return [];

  const [
    { data: pillars, error: pillarsError },
    { data: categories, error: categoriesError }
  ] = await Promise.all([
    supabase.from("pillars").select("id,name").in("id", pillarIds),
    supabase.from("categories").select("id,name").in("id", categoryIds)
  ]);

  if (pillarsError) throw pillarsError;
  if (categoriesError) throw categoriesError;

  const pillarNames = new Map((pillars || []).map((pillar) => [pillar.id, pillar.name]));
  const categoryNames = new Map((categories || []).map((category) => [category.id, category.name]));
  return placements.map((placement) => ({
    ...placement,
    pillarName: pillarNames.get(placement.pillar_id) || "Unknown pillar",
    categoryName: categoryNames.get(placement.category_id) || "Unknown category"
  }));
}

export async function updateGameInformation(gameId, changes) {
  const { data, error } = await supabase
    .from("games")
    .update({
      title: changes.title,
      subtitle: changes.subtitle || null,
      description: changes.description || null,
      sort_order: changes.sort_order
    })
    .eq("id", gameId)
    .select("id,title,subtitle,description,cover_image_url,game_type,is_locked,price,sort_order,created_at,updated_at")
    .single();

  if (error) throw error;
  return data;
}

export async function loadGameAccess(gameId) {
  const { data, error } = await supabase
    .from("games")
    .select("id,is_locked,price")
    .eq("id", gameId)
    .single();

  if (error) throw error;
  return data;
}

export async function updateGameAccess(gameId, isLocked, changes = {}) {
  const { data, error } = await supabase
    .from("games")
    .update({
      ...(changes.title !== undefined ? { title: changes.title } : {}),
      ...(changes.subtitle !== undefined ? { subtitle: changes.subtitle || null } : {}),
      ...(changes.description !== undefined ? { description: changes.description || null } : {}),
      ...(changes.sort_order !== undefined ? { sort_order: changes.sort_order } : {}),
      ...(changes.price !== undefined ? { price: Number(changes.price) || 0 } : {}),
      is_locked: isLocked
    })
    .eq("id", gameId)
    .select("id,title,subtitle,description,game_type,is_locked,price,sort_order,created_at,updated_at")
    .single();

  if (error) throw error;
  return data;
}

export async function deleteGame(gameId) {
  const { data: assets, error: assetError } = await supabase.storage
    .from("game-assets")
    .list(`games/${gameId}`, { limit: 1 });

  if (assetError) {
    console.error("Unable to check game assets before deletion.", {
      gameId,
      code: assetError.code || "GAME_ASSET_CHECK_FAILED"
    });
    throw new Error("Unable to safely check this game's associated assets. The game was not deleted.");
  }
  if (assets?.length) {
    throw new Error("This game still has associated storage assets. Remove those assets before deleting the game.");
  }

  const { data, error } = await supabase
    .from("games")
    .delete()
    .eq("id", gameId)
    .select("id")
    .maybeSingle();

  if (error) {
    console.error("Game deletion failed.", {
      gameId,
      code: error.code || "GAME_DELETE_FAILED"
    });
    throw new Error("Unable to delete this game. Its game data was left unchanged.");
  }
  if (!data) {
    throw new Error("This game could not be found or you do not have permission to delete it.");
  }

  return data;
}

export async function updateGameRule(ruleId, ruleText) {
  const { error } = await supabase
    .from("game_rules")
    .update({ rule_text: ruleText })
    .eq("id", ruleId);

  if (error) throw error;
}

function validateGameCardData(cardData) {
  if (!cardData || typeof cardData !== "object" || Array.isArray(cardData)) {
    throw new Error("Card data is required.");
  }
  if (!Number.isInteger(cardData.sort_order) || cardData.sort_order < 1) {
    throw new Error("A positive card sort order is required.");
  }
  if (typeof cardData.front_text !== "string" || typeof cardData.back_text !== "string") {
    throw new Error("Card text fields must be provided.");
  }
  if (!cardData.metadata || typeof cardData.metadata !== "object" || Array.isArray(cardData.metadata)) {
    throw new Error("Card metadata must be an object.");
  }
  if (!Array.isArray(cardData.metadata.pairs)) {
    throw new Error("Card metadata must include a pairs array.");
  }
}

export async function createGameCard(gameId, cardData) {
  if (typeof gameId !== "string" || !gameId.trim()) {
    throw new Error("A valid game ID is required.");
  }
  validateGameCardData(cardData);

  const { data, error } = await supabase
    .from("game_cards")
    .insert({
      game_id: gameId,
      sort_order: cardData.sort_order,
      front_text: cardData.front_text,
      back_text: cardData.back_text,
      metadata: cardData.metadata
    })
    .select("id,game_id,sort_order,front_text,back_text,metadata,created_at,updated_at")
    .single();

  if (error?.code === "23505") {
    const conflict = new Error("Card sort order conflict.");
    conflict.code = error.code;
    throw conflict;
  }
  if (error) {
    console.error("Game card creation failed.", { code: error.code || "UNKNOWN" });
    throw new Error("Unable to create the game card. Please try again.");
  }
  return data;
}

export async function updateGameCard(cardId, cardData) {
  if (typeof cardId !== "string" || !cardId.trim()) {
    throw new Error("A valid card ID is required.");
  }
  validateGameCardData(cardData);

  const { data, error } = await supabase
    .from("game_cards")
    .update({
      front_text: cardData.front_text,
      back_text: cardData.back_text,
      metadata: cardData.metadata
    })
    .eq("id", cardId)
    .select("id,game_id,sort_order,front_text,back_text,metadata,created_at,updated_at")
    .single();

  if (error) {
    console.error("Game card update failed.", { code: error.code || "UNKNOWN" });
    throw new Error("Unable to save the game card. Please try again.");
  }
  return data;
}

export async function createGameRule(gameId, ruleText) {
  const { data: existingRule, error: lookupError } = await supabase
    .from("game_rules")
    .select("id")
    .eq("game_id", gameId)
    .limit(1)
    .maybeSingle();

  if (lookupError) {
    console.error("Game rule duplicate check failed.", {
      code: lookupError.code || "UNKNOWN"
    });
    throw new Error("Unable to check for an existing rule. Please try again.");
  }
  if (existingRule) {
    throw new Error("A rule already exists for this game.");
  }

  const { data, error } = await supabase
    .from("game_rules")
    .insert({
      game_id: gameId,
      sort_order: 1,
      rule_text: ruleText,
      metadata: {}
    })
    .select("id,game_id,sort_order,rule_text,metadata,created_at,updated_at")
    .single();

  if (error?.code === "23505") {
    throw new Error("A rule already exists for this game.");
  }
  if (error) {
    console.error("Game rule creation failed.", { code: error.code || "UNKNOWN" });
    throw new Error("Unable to create the game rule. Please try again.");
  }
  return data;
}
