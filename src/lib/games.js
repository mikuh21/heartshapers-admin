import { supabase } from "./supabase";
import {
  describeGameStorageUploadError,
  gameUploadSizeError,
  loadGameUploadLimit
} from "./uploadSettings";

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
  const priceText = String(gameData.price ?? "");
  if (!/^\d+(\.\d{1,2})?$/.test(priceText) || !Number.isFinite(Number(priceText)) || Number(priceText) < 0) {
    throw new Error("Enter a valid price of zero or greater, with up to two decimal places.");
  }
  if (typeof gameData.is_locked !== "boolean") {
    throw new Error("Choose whether the game is Free or Locked.");
  }
  if (
    !sourcePdfFile
    || (sourcePdfFile.type !== "application/pdf" && !sourcePdfFile.name?.toLowerCase().endsWith(".pdf"))
  ) {
    throw new Error("Choose a valid game content PDF.");
  }
  const uploadLimit = await loadGameUploadLimit();
  if (coverFile.size > uploadLimit.maximumBytes || sourcePdfFile.size > uploadLimit.maximumBytes) {
    throw new Error(gameUploadSizeError(uploadLimit));
  }

  const coverPath = `games/${gameData.id}/cover/cover.${coverExtension}`;
  const sourcePdfPath = `games/${gameData.id}/source/content.pdf`;
  try {
    const { error: coverError } = await supabase.storage
      .from("game-assets")
      .upload(coverPath, coverFile, { contentType: coverFile.type, upsert: false });
    if (coverError) throw describeGameStorageUploadError(coverError, uploadLimit);
    uploadedPaths.push(coverPath);

    const { error: sourcePdfError } = await supabase.storage
      .from("game-assets")
      .upload(sourcePdfPath, sourcePdfFile, { contentType: "application/pdf", upsert: false });
    if (sourcePdfError) throw describeGameStorageUploadError(sourcePdfError, uploadLimit);
    uploadedPaths.push(sourcePdfPath);

    const cardRows = [];
    for (let index = 0; index < pageFiles.length; index += 1) {
      const { pageNumber, blob } = pageFiles[index];
      const path = `games/${gameData.id}/cards/page-${String(index + 1).padStart(4, "0")}.png`;
      const { error: pageError } = await supabase.storage
        .from("game-assets")
        .upload(path, blob, { contentType: "image/png", upsert: false });
      if (pageError) throw describeGameStorageUploadError(pageError, uploadLimit);
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
        id: gameData.id,
        title: gameData.title,
        game_type: "pdf_deck",
        subtitle: gameData.subtitle || null,
        description: gameData.description || null,
        price: priceText,
        is_locked: gameData.is_locked,
        sort_order: gameData.sort_order,
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
    if (game?.game_type !== "pdf_deck" || game?.cover_image_url !== coverPath) {
      preserveUploadedAssets = true;
      console.error("PDF game creation returned an unexpected field mapping.", {
        gameId: gameData.id,
        gameTypeCorrect: game?.game_type === "pdf_deck",
        coverPathCorrect: game?.cover_image_url === coverPath
      });
      throw new Error("The database returned an invalid PDF game field mapping. Uploaded files were retained because the game may already have been created. Verify the database function and game record before retrying.");
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

export async function downloadPdfGameSource(gameId, sourcePdfPath) {
  if (
    typeof gameId !== "string"
    || typeof sourcePdfPath !== "string"
    || !sourcePdfPath.startsWith(`games/${gameId}/source/`)
  ) {
    throw new Error("The PDF source path does not belong to this game.");
  }

  const { data, error } = await supabase.storage
    .from("game-assets")
    .download(sourcePdfPath);
  if (error) {
    throw new Error(`Unable to load the game's source PDF: ${error.message || "Unknown storage error"}`);
  }
  return data;
}

export async function updatePdfGame(gameData, { coverFile = null, sourcePdfFile = null, pageFiles = null }) {
  if (
    typeof gameData?.id !== "string"
    || !gameData.id.trim()
    || !gameData.title?.trim()
  ) {
    throw new Error("A valid PDF game and title are required.");
  }
  const priceText = String(gameData.price ?? "");
  if (!/^\d+(\.\d{1,2})?$/.test(priceText) || !Number.isFinite(Number(priceText)) || Number(priceText) < 0) {
    throw new Error("Enter a valid price of zero or greater, with up to two decimal places.");
  }
  if (typeof gameData.is_locked !== "boolean" || !Number.isInteger(Number(gameData.sort_order))) {
    throw new Error("The game access setting or sort order is invalid.");
  }
  if (typeof gameData.rules !== "string" || !gameData.rules.trim()) {
    throw new Error("Game rules are required.");
  }
  if (coverFile && !{
    "image/jpeg": true,
    "image/png": true,
    "image/webp": true
  }[coverFile.type]) {
    throw new Error("Choose a JPEG, PNG, or WebP cover image.");
  }
  let uploadLimit = null;
  if (sourcePdfFile && (sourcePdfFile.type !== "application/pdf" && !sourcePdfFile.name?.toLowerCase().endsWith(".pdf"))) {
    throw new Error("Choose a valid game content PDF.");
  }
  if (sourcePdfFile || coverFile) {
    uploadLimit = await loadGameUploadLimit();
    if (
      (sourcePdfFile && sourcePdfFile.size > uploadLimit.maximumBytes)
      || (coverFile && coverFile.size > uploadLimit.maximumBytes)
    ) {
      throw new Error(gameUploadSizeError(uploadLimit));
    }
  }
  if (sourcePdfFile && !Array.isArray(pageFiles)) {
    throw new Error("Select card pages from the replacement PDF.");
  }
  if (pageFiles !== null && (!Array.isArray(pageFiles) || pageFiles.length === 0)) {
    throw new Error("Select at least one PDF page for the card deck.");
  }

  const gamePrefix = `games/${gameData.id}/`;
  const { data: oldCards, error: cardsError } = pageFiles === null
    ? { data: [], error: null }
    : await supabase
      .from("game_cards")
      .select("metadata")
      .eq("game_id", gameData.id);
  if (cardsError) {
    throw new Error(`Unable to load existing PDF card assets before replacing them: ${cardsError.message || "Unknown error"}`);
  }

  const oldAssetPaths = [];
  if (sourcePdfFile && gameData.source_pdf_path?.startsWith(gamePrefix)) {
    oldAssetPaths.push(gameData.source_pdf_path);
  }
  if (pageFiles !== null) {
    for (const card of oldCards || []) {
      const path = card.metadata?.pdf_page_path;
      if (typeof path === "string" && path.startsWith(`${gamePrefix}cards/`)) {
        oldAssetPaths.push(path);
      }
    }
  }

  const storage = supabase.storage.from("game-assets");
  const uploadedPaths = [];
  const version = crypto.randomUUID();
  const coverExtension = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp"
  }[coverFile?.type];
  const newCoverPath = coverFile
    ? `${gamePrefix}cover/${version}.${coverExtension}`
    : undefined;
  const newSourcePath = sourcePdfFile
    ? `${gamePrefix}source/${version}.pdf`
    : undefined;
  const cardRows = pageFiles === null
    ? null
    : pageFiles.map(({ pageNumber }, index) => {
      const path = `${gamePrefix}cards/${version}/page-${String(index + 1).padStart(4, "0")}.png`;
      return {
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
      };
    });

  try {
    if (coverFile) {
      const { error } = await storage.upload(newCoverPath, coverFile, {
        contentType: coverFile.type,
        upsert: false
      });
      if (error) throw describeGameStorageUploadError(error, uploadLimit);
      uploadedPaths.push(newCoverPath);
    }

    if (sourcePdfFile) {
      const { error } = await storage.upload(newSourcePath, sourcePdfFile, {
        contentType: "application/pdf",
        upsert: false
      });
      if (error) throw describeGameStorageUploadError(error, uploadLimit);
      uploadedPaths.push(newSourcePath);
    }

    if (pageFiles !== null) {
      for (let index = 0; index < pageFiles.length; index += 1) {
        const path = cardRows[index].metadata.pdf_page_path;
        const { error } = await storage.upload(path, pageFiles[index].blob, {
          contentType: "image/png",
          upsert: false
        });
        if (error) throw describeGameStorageUploadError(error, uploadLimit);
        uploadedPaths.push(path);
      }
    }

    const { data, error } = await supabase.rpc("update_pdf_game", {
      p_game: {
        id: gameData.id,
        title: gameData.title.trim(),
        subtitle: gameData.subtitle?.trim() || null,
        description: gameData.description?.trim() || null,
        price: priceText,
        is_locked: gameData.is_locked,
        sort_order: Number(gameData.sort_order),
        ...(newCoverPath ? { cover_image_url: newCoverPath } : {}),
        ...(newSourcePath ? { source_pdf_path: newSourcePath } : {})
      },
      p_cards: cardRows,
      p_rules: gameData.rules.trim()
    });

    if (error) {
      if (!error.code) {
        console.error("PDF game update outcome could not be confirmed.", {
          gameId: gameData.id,
          uploadedAssetCount: uploadedPaths.length
        });
        throw new Error("The save response was interrupted. The uploaded replacement assets were retained to avoid breaking a possibly completed update. Refresh the Games list and reopen the editor before retrying.");
      }
      throw error;
    }

    const pathsToRemove = [...new Set(oldAssetPaths)].filter((path) => !uploadedPaths.includes(path));
    let assetCleanupWarning = false;
    if (pathsToRemove.length > 0) {
      const { error: cleanupError } = await storage.remove(pathsToRemove);
      if (cleanupError) {
        assetCleanupWarning = true;
        console.error("Replaced PDF game assets could not be removed.", {
          gameId: gameData.id,
          count: pathsToRemove.length,
          code: cleanupError.code || "ASSET_CLEANUP_FAILED"
        });
      }
    }

    return { ...data, assetCleanupWarning };
  } catch (error) {
    if (!error?.code && error?.message?.startsWith("The save response was interrupted.")) {
      throw error;
    }

    const cleanupErrors = [];
    const pathsToClean = uploadedPaths.filter((path) => path !== newCoverPath);
    if (pathsToClean.length > 0) {
      const { error: cleanupError } = await storage.remove(pathsToClean);
      if (cleanupError) cleanupErrors.push(cleanupError);
    }
    const retainedCoverMessage = newCoverPath && uploadedPaths.includes(newCoverPath)
      ? ` The replacement cover at "${newCoverPath}" was retained; the previously saved cover was not removed.`
      : "";
    if (cleanupErrors.length > 0) {
      console.error("Failed PDF game update left temporary assets.", {
        gameId: gameData.id,
        uploadedAssetCount: uploadedPaths.length,
        code: cleanupErrors[0].code || "ASSET_CLEANUP_FAILED"
      });
      throw new Error(`The PDF game was not updated, and some newly uploaded files could not be cleaned up. The existing game content remains active; contact an administrator before retrying.${retainedCoverMessage}`);
    }
    if (error instanceof Error && !error.code) throw error;
    console.error("PDF game update failed.", {
      gameId: gameData.id,
      code: error?.code || "PDF_GAME_UPDATE_FAILED"
    });
    throw new Error(`Unable to save the PDF game. ${error?.message || "Please try again."}${retainedCoverMessage}`);
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
      .is("deleted_at", null)
      .order("sort_order", { ascending: true }),
    supabase.from("pillars").select("id,name").is("deleted_at", null).order("name", { ascending: true }),
    supabase.from("game_placements").select("game_id,pillar_id")
  ]);

  if (gamesError) throw gamesError;
  if (pillarsError) throw pillarsError;
  if (placementsError) throw placementsError;

  const coverDisplays = await Promise.all((games || []).map(async (game) => {
    const coverPath = game.cover_image_url?.trim();
    if (!coverPath) return [game.id, null];

    if (coverPath.startsWith("games/")) {
      const { data, error } = await supabase.storage
        .from("game-assets")
        .createSignedUrl(coverPath, 3600);
      if (error || !data?.signedUrl) {
        console.error("Game cover URL could not be resolved.", {
          gameId: game.id,
          code: error?.code || "SIGNED_COVER_URL_UNAVAILABLE"
        });
        return [game.id, null];
      }
      return [game.id, data.signedUrl];
    }

    try {
      const directUrl = new URL(coverPath);
      if (directUrl.protocol === "https:" || directUrl.protocol === "http:") {
        return [game.id, directUrl.href];
      }
    } catch {
      console.error("Game cover value is not a valid URL or game-assets path.", {
        gameId: game.id
      });
    }
    return [game.id, null];
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
    supabase.from("pillars").select("id,name").is("deleted_at", null).in("id", pillarIds),
    supabase.from("categories").select("id,name").is("deleted_at", null).in("id", categoryIds)
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

export async function updateGameWithCover(gameId, isLocked, changes, coverFile = null) {
  const coverExtension = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp"
  }[coverFile?.type];
  if (coverFile && !coverExtension) {
    throw new Error("Choose a JPEG, PNG, or WebP cover image.");
  }
  const uploadLimit = coverFile ? await loadGameUploadLimit() : null;
  if (coverFile && coverFile.size > uploadLimit.maximumBytes) {
    throw new Error(gameUploadSizeError(uploadLimit));
  }

  const coverPath = coverFile
    ? `games/${gameId}/cover/${crypto.randomUUID()}.${coverExtension}`
    : null;
  if (coverFile) {
    const { error: uploadError } = await supabase.storage
      .from("game-assets")
      .upload(coverPath, coverFile, {
        contentType: coverFile.type,
        upsert: false
      });
    if (uploadError) {
      const detailedError = describeGameStorageUploadError(uploadError, uploadLimit);
      throw new Error(`Unable to upload the new cover image: ${detailedError.message || "Storage upload failed."}`);
    }
  }

  const { data, error } = await supabase
    .from("games")
    .update({
      ...(changes.title !== undefined ? { title: changes.title } : {}),
      ...(changes.subtitle !== undefined ? { subtitle: changes.subtitle || null } : {}),
      ...(changes.description !== undefined ? { description: changes.description || null } : {}),
      ...(changes.price !== undefined ? { price: Number(changes.price) || 0 } : {}),
      ...(coverPath ? { cover_image_url: coverPath } : {}),
      is_locked: isLocked
    })
    .eq("id", gameId)
    .select("id,title,subtitle,description,cover_image_url,source_pdf_path,game_type,is_locked,price,sort_order,created_at,updated_at")
    .single();

  if (error) {
    if (coverPath) {
      console.error("Game update failed after uploading a new cover; the uploaded file was retained.", {
        gameId,
        code: error.code || "GAME_UPDATE_FAILED"
      });
      throw new Error(`Unable to save the game changes. The new cover was uploaded to "${coverPath}" and retained; the previously saved cover was not removed. ${error.message || "Please retry or contact an administrator."}`);
    }
    throw error;
  }

  let coverDisplayUrl = null;
  if (data.cover_image_url?.startsWith("games/")) {
    const { data: signedData, error: signedUrlError } = await supabase.storage
      .from("game-assets")
      .createSignedUrl(data.cover_image_url, 3600);
    if (signedUrlError) {
      console.error("Updated game cover URL could not be resolved.", {
        gameId,
        code: signedUrlError.code || "SIGNED_COVER_URL_UNAVAILABLE"
      });
    } else {
      coverDisplayUrl = signedData?.signedUrl || null;
    }
  } else {
    coverDisplayUrl = data.cover_image_url || null;
  }

  return { ...data, cover_display_url: coverDisplayUrl };
}

function describeGameDeletionError(error) {
  const code = error?.code ? ` (${error.code})` : "";
  return `${error?.message || "Unknown error"}${code}`;
}

async function listGameAssetPaths(storage, folder, rootPath) {
  const paths = [];
  const pageSize = 1000;
  let offset = 0;

  while (true) {
    const { data: entries, error } = await storage.list(folder, {
      limit: pageSize,
      offset,
      sortBy: { column: "name", order: "asc" }
    });
    if (error) {
      throw new Error(`Unable to list game storage at "${folder}": ${describeGameDeletionError(error)}`);
    }
    if (!entries?.length) break;

    for (const entry of entries) {
      const name = entry?.name;
      if (
        typeof name !== "string"
        || !name
        || name === "."
        || name === ".."
        || /[\/\\\u0000-\u001f]/.test(name)
      ) {
        throw new Error(`Storage returned an invalid object name while listing "${folder}". No database records were deleted.`);
      }

      const path = `${folder}/${name}`;
      if (entry.id === null) {
        const nestedPaths = await listGameAssetPaths(storage, path, rootPath);
        for (const nestedPath of nestedPaths) paths.push(nestedPath);
      } else if (path.startsWith(`${rootPath}/`)) {
        paths.push(path);
      } else {
        throw new Error("Storage returned an object outside the selected game's folder. Deletion was stopped.");
      }
    }

    offset += entries.length;
    if (entries.length < pageSize) break;
  }

  return paths;
}

async function assertGameHasNoProtectedRecords(gameId) {
  for (const table of ["game_payment_submissions", "game_purchases"]) {
    const { data, error } = await supabase
      .from(table)
      .select("id")
      .eq("game_id", gameId)
      .limit(1);

    if (error) {
      throw new Error(`Unable to check ${table} before deleting the game: ${describeGameDeletionError(error)}. No storage assets were removed.`);
    }
    if (data?.length) {
      throw new Error(`This game has ${table === "game_purchases" ? "purchase" : "payment"} history that must be preserved. The game and its storage assets were not deleted.`);
    }
  }
}

export async function deleteGame(gameId) {
  if (
    typeof gameId !== "string"
    || gameId !== gameId.trim()
    || !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(gameId)
  ) {
    throw new Error("The selected game ID is invalid. No data was changed.");
  }

  const { data, error } = await supabase
    .from("games")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", gameId)
    .is("deleted_at", null)
    .select("id")
    .maybeSingle();

  if (error) {
    console.error("Game soft deletion failed.", {
      gameId,
      code: error.code || "GAME_SOFT_DELETE_FAILED"
    });
    throw new Error(`Unable to delete this game: ${describeGameDeletionError(error)}. No database records or storage assets were removed.`);
  }
  if (!data) {
    throw new Error("This game could not be found or has already been deleted.");
  }

  // Keep game cards, rules, placements, payment/purchase history, and storage
  // assets intact. The deleted_at filter hides the game from normal listings.
  return { ...data, removedAssetCount: 0 };
}
