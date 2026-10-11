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
      cover_image_url: game.cover_image_url || null,
      sort_order: game.sort_order,
      price: Number(game.price) || 0,
      is_locked: true
    })
    .select("id,title,subtitle,description,cover_image_url,source_pdf_path,game_type,is_locked,price,sort_order,created_at,updated_at")
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

export async function createPdfGame(gameData, coverFile, sourcePdfFile, pageFiles) {
  const uploadedPaths = [];
  let preserveUploadedAssets = false;
  const coverExtension = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp"
  }[coverFile?.type];

  if (!coverExtension) {
    throw new Error("Choose a JPEG, PNG, or WebP cover image.");
  }
  if (!Array.isArray(pageFiles) || pageFiles.length === 0) {
    throw new Error("Select at least one PDF page for the card deck.");
  }
  if (
    !sourcePdfFile
    || (sourcePdfFile.type !== "application/pdf" && !sourcePdfFile.name?.toLowerCase().endsWith(".pdf"))
    || sourcePdfFile.size > 50 * 1024 * 1024
  ) {
    throw new Error("Choose a valid game content PDF.");
  }

  const coverPath = `games/${gameData.id}/cover/cover.${coverExtension}`;
  const sourcePdfPath = `games/${gameData.id}/source/content.pdf`;
  try {
    const { error: coverError } = await supabase.storage
      .from("game-assets")
      .upload(coverPath, coverFile, { contentType: coverFile.type, upsert: false });
    if (coverError) throw coverError;
    uploadedPaths.push(coverPath);

    const { error: sourcePdfError } = await supabase.storage
      .from("game-assets")
      .upload(sourcePdfPath, sourcePdfFile, { contentType: "application/pdf", upsert: false });
    if (sourcePdfError) throw sourcePdfError;
    uploadedPaths.push(sourcePdfPath);

    const cardRows = [];
    for (let index = 0; index < pageFiles.length; index += 1) {
      const { pageNumber, blob } = pageFiles[index];
      const path = `games/${gameData.id}/cards/page-${String(index + 1).padStart(4, "0")}.png`;
      const { error: pageError } = await supabase.storage
        .from("game-assets")
        .upload(path, blob, { contentType: "image/png", upsert: false });
      if (pageError) throw pageError;
      uploadedPaths.push(path);
      cardRows.push({
        sort_order: index + 1,
        front_text: "",
        back_text: "",
        metadata: {
          pairs: [],
          content_type: "pdf_page",
          pdf_page_number: pageNumber,
          pdf_page_path: path,
          page_order: index + 1
        }
      });
    }

    const { data: game, error: publishError } = await supabase.rpc("create_pdf_game", {
      p_game: {
        ...gameData,
        cover_image_url: coverPath,
        source_pdf_path: sourcePdfPath
      },
      p_cards: cardRows,
      p_rules: gameData.rules
    });
    if (publishError?.code === "23505") {
      throw new Error("A game with this ID already exists.");
    }
    if (publishError) {
      if (!publishError.code) {
        const { data: recoveredGame, error: lookupError } = await supabase
          .from("games")
          .select("id,title,subtitle,description,cover_image_url,source_pdf_path,game_type,is_locked,price,sort_order,created_at,updated_at")
          .eq("id", gameData.id)
          .maybeSingle();

        if (lookupError) {
          preserveUploadedAssets = true;
          console.error("Unable to confirm PDF game publication after a network error.", {
            gameId: gameData.id,
            code: lookupError.code || "PDF_GAME_RECOVERY_FAILED"
          });
          throw new Error("Unable to confirm whether the PDF game was published. Check the Games list before retrying.");
        }
        if (recoveredGame?.cover_image_url === coverPath) {
          const { data: recoveredCards, error: cardsLookupError } = await supabase
            .from("game_cards")
            .select("sort_order,metadata")
            .eq("game_id", gameData.id)
            .order("sort_order", { ascending: true });
          if (cardsLookupError) {
            preserveUploadedAssets = true;
            console.error("Unable to verify PDF game cards after a network error.", {
              gameId: gameData.id,
              code: cardsLookupError.code || "PDF_CARD_RECOVERY_FAILED"
            });
            throw new Error("Unable to verify the published PDF game. Check the Games list before retrying.");
          }

          const expectedPaths = cardRows.map((card) => card.metadata.pdf_page_path);
          const recoveredCardsMatch = recoveredCards?.length === expectedPaths.length
            && recoveredCards.every((card, index) => (
              card.sort_order === index + 1
              && card.metadata?.pdf_page_path === expectedPaths[index]
            ));
          if (recoveredCardsMatch) return recoveredGame;
          preserveUploadedAssets = true;
          console.error("PDF game publication state is incomplete after a network error.", {
            gameId: gameData.id
          });
          throw new Error("The PDF game publication could not be verified. Check the Games list before retrying.");
        }
      }
      console.error("Atomic PDF game publishing failed.", {
        code: publishError.code || "PDF_GAME_PUBLISH_FAILED"
      });
      throw new Error("Unable to publish the PDF game. Please try again.");
    }
    return game;
  } catch (error) {
    const cleanupErrors = [];
    if (uploadedPaths.length > 0 && !preserveUploadedAssets) {
      const { error: removeError } = await supabase.storage
        .from("game-assets")
        .remove(uploadedPaths);
      if (removeError) cleanupErrors.push(removeError);
    }
    if (cleanupErrors.length > 0) {
      console.error("PDF game creation cleanup failed.", {
        gameId: gameData.id,
        codes: cleanupErrors.map((cleanupError) => cleanupError.code || "CLEANUP_FAILED")
      });
      throw new Error("Unable to complete the PDF game, and some uploaded data could not be cleaned up. Contact an administrator.");
    }
    if (error instanceof Error) throw error;
    console.error("PDF game creation failed.", { code: error?.code || "UNKNOWN" });
    throw new Error("Unable to create the PDF game. Please try again.");
  }
}

export async function listGamesWithCounts() {
  const [
    { data: games, error: gamesError },
    { data: pillars, error: pillarsError },
    { data: placements, error: placementsError }
  ] = await Promise.all([
    supabase
      .from("games")
      .select("id,title,subtitle,description,cover_image_url,source_pdf_path,game_type,is_locked,price,sort_order,created_at,updated_at")
      .order("sort_order", { ascending: true }),
    supabase.from("pillars").select("id,name").order("name", { ascending: true }),
    supabase.from("game_placements").select("game_id,pillar_id")
  ]);

  if (gamesError) throw gamesError;
  if (pillarsError) throw pillarsError;
  if (placementsError) throw placementsError;

  const coverDisplays = await Promise.all((games || []).map(async (game) => {
    if (!game.cover_image_url?.startsWith("games/")) {
      return [game.id, game.cover_image_url];
    }
    const { data, error } = await supabase.storage
      .from("game-assets")
      .createSignedUrl(game.cover_image_url, 3600);
    if (error) throw error;
    return [game.id, data.signedUrl];
  }));
  const coverDisplayUrls = new Map(coverDisplays);

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
      cover_display_url: coverDisplayUrls.get(game.id) || null,
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
    .select("id,title,subtitle,description,cover_image_url,source_pdf_path,game_type,is_locked,price,sort_order,created_at,updated_at")
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
    .select("id,title,subtitle,description,cover_image_url,source_pdf_path,game_type,is_locked,price,sort_order,created_at,updated_at")
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
