import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  where,
  orderBy,
  updateDoc,
  serverTimestamp
} from "firebase/firestore";
import { firestore } from "./firebase";
import { getFirebaseAssetDownloadUrl, uploadFirebaseAsset } from "./firebaseAssetStorage";

/**
 * Firebase-first Games catalog reads. Collection IDs and document IDs intentionally
 * mirror the legacy relational entity names so the future data-transfer stage can
 * map records without rewriting the admin UI.
 */
const gamesRef = collection(firestore, "games");
const pillarsRef = collection(firestore, "pillars");
const categoriesRef = collection(firestore, "categories");

function rows(snapshot) {
  return snapshot.docs.map((item) => ({ id: item.id, ...item.data() }));
}

async function resolveCover(game) {
  const path = game.cover_image_url?.trim();
  if (!path) return null;
  if (path.startsWith("games/")) {
    try {
      return await getFirebaseAssetDownloadUrl(path);
    } catch (error) {
      console.warn("Firebase game cover URL could not be resolved.", { gameId: game.id });
      return null;
    }
  }
  try {
    const url = new URL(path);
    return ["https:", "http:"].includes(url.protocol) ? url.href : null;
  } catch {
    return null;
  }
}

export async function listFirebaseGamesWithCounts() {
  const [gamesSnapshot, pillarsSnapshot, placementsSnapshot] = await Promise.all([
    getDocs(query(gamesRef, where("deleted_at", "==", null), orderBy("sort_order", "asc"))),
    getDocs(query(pillarsRef, where("deleted_at", "==", null), orderBy("name", "asc"))),
    getDocs(collection(firestore, "game_placements"))
  ]);
  const games = rows(gamesSnapshot);
  const pillars = rows(pillarsSnapshot);
  const placements = rows(placementsSnapshot);
  const results = await Promise.all(games.map(async (game) => {
    const [coverDisplayUrl, cardsSnapshot] = await Promise.all([
      resolveCover(game),
      getDocs(collection(firestore, "games", game.id, "game_cards"))
    ]);
    const gamePlacements = placements.filter((placement) => placement.game_id === game.id);
    return {
      ...game,
      cover_display_url: coverDisplayUrl,
      cardCount: cardsSnapshot.size,
      placementCount: gamePlacements.length,
      pillarIds: gamePlacements.map((placement) => placement.pillar_id)
    };
  }));
  return { games: results, pillars };
}

export async function loadFirebaseGameDetails(gameId) {
  const [rulesSnapshot, cardsSnapshot, placementsSnapshot] = await Promise.all([
    getDocs(query(collection(firestore, "games", gameId, "game_rules"), orderBy("sort_order", "asc"))),
    getDocs(query(collection(firestore, "games", gameId, "game_cards"), orderBy("sort_order", "asc"))),
    getDocs(query(collection(firestore, "game_placements"), where("game_id", "==", gameId), orderBy("sort_order", "asc")))
  ]);
  return {
    rules: { data: rows(rulesSnapshot), error: null },
    cards: { data: rows(cardsSnapshot), error: null },
    placements: { data: rows(placementsSnapshot), error: null }
  };
}

export async function loadFirebaseGameAccess(gameId) {
  const snapshot = await getDoc(doc(firestore, "games", gameId));
  if (!snapshot.exists() || snapshot.data().deleted_at) {
    throw new Error("This game could not be found or has already been deleted.");
  }
  const data = snapshot.data();
  return { id: snapshot.id, is_locked: data.is_locked, price: data.price };
}

export async function updateFirebaseGameAccess(gameId, isLocked, changes = {}) {
  const gameRef = doc(firestore, "games", gameId);
  const snapshot = await getDoc(gameRef);
  if (!snapshot.exists() || snapshot.data().deleted_at) {
    throw new Error("This game could not be found or has already been deleted.");
  }
  const update = {
    is_locked: isLocked,
    updated_at: serverTimestamp()
  };
  for (const key of ["title", "subtitle", "description", "sort_order", "price"]) {
    if (changes[key] !== undefined) update[key] = key === "price" ? Number(changes[key]) || 0 : changes[key];
  }
  await updateDoc(gameRef, update);
  return { id: snapshot.id, ...snapshot.data(), ...update, updated_at: new Date().toISOString() };
}

export async function updateFirebaseGameInformation(gameId, changes) {
  return updateFirebaseGameAccess(gameId, changes.is_locked ?? true, changes);
}

export async function softDeleteFirebaseGame(gameId) {
  if (typeof gameId !== "string" || gameId !== gameId.trim() || !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(gameId)) {
    throw new Error("The selected game ID is invalid. No data was changed.");
  }
  const gameRef = doc(firestore, "games", gameId);
  const snapshot = await getDoc(gameRef);
  if (!snapshot.exists() || snapshot.data().deleted_at) {
    throw new Error("This game could not be found or has already been deleted.");
  }
  await updateDoc(gameRef, { deleted_at: new Date().toISOString(), updated_at: serverTimestamp() });
  // Deliberately preserve cards, rules, placements, purchases/payment history, and assets.
  return { id: gameId, removedAssetCount: 0 };
}

export async function loadFirebasePlacementNames(placements) {
  const pillarIds = [...new Set(placements.map((placement) => placement.pillar_id).filter(Boolean))];
  const categoryIds = [...new Set(placements.map((placement) => placement.category_id).filter(Boolean))];
  const [pillarsSnapshot, categoriesSnapshot] = await Promise.all([
    pillarIds.length ? getDocs(query(pillarsRef, where("__name__", "in", pillarIds))) : Promise.resolve(null),
    categoryIds.length ? getDocs(query(categoriesRef, where("__name__", "in", categoryIds))) : Promise.resolve(null)
  ]);
  const pillarNames = new Map((pillarsSnapshot ? rows(pillarsSnapshot) : []).map((item) => [item.id, item.name]));
  const categoryNames = new Map((categoriesSnapshot ? rows(categoriesSnapshot) : []).map((item) => [item.id, item.name]));
  return placements.map((placement) => ({
    ...placement,
    pillarName: pillarNames.get(placement.pillar_id) || "Unknown pillar",
    categoryName: categoryNames.get(placement.category_id) || "Unknown category"
  }));
}

export async function updateFirebaseGameWithCover(gameId, isLocked, changes = {}, coverFile = null) {
  const gameRef = doc(firestore, "games", gameId);
  const snapshot = await getDoc(gameRef);
  if (!snapshot.exists() || snapshot.data().deleted_at) throw new Error("This game could not be found or has been deleted.");
  const update = {
    is_locked: isLocked,
    updated_at: serverTimestamp()
  };
  for (const key of ["title", "subtitle", "description", "price", "sort_order"]) {
    if (changes[key] !== undefined) update[key] = key === "price" ? Number(changes[key]) || 0 : changes[key];
  }
  let coverDisplayUrl = null;
  if (coverFile) {
    const extension = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[coverFile.type];
    if (!extension) throw new Error("Choose a JPEG, PNG, or WebP cover image.");
    const path = `games/${gameId}/cover/${crypto.randomUUID()}.${extension}`;
    const uploaded = await uploadFirebaseAsset(path, coverFile, coverFile.type);
    update.cover_image_url = uploaded.path;
    coverDisplayUrl = uploaded.downloadUrl;
  }
  await updateDoc(gameRef, update);
  if (!coverDisplayUrl) coverDisplayUrl = await resolveCover({ ...snapshot.data(), ...update, id: gameId });
  return { id: gameId, ...snapshot.data(), ...update, cover_display_url: coverDisplayUrl };
}

export async function updateFirebaseGameCover(gameId, currentCoverPath, nextCoverPath) {
  const gameRef = doc(firestore, "games", gameId);
  const snapshot = await getDoc(gameRef);
  if (!snapshot.exists() || snapshot.data().deleted_at) throw new Error("The game could not be found or has been deleted.");
  if ((snapshot.data().cover_image_url || null) !== (currentCoverPath || null)) {
    throw new Error("The game cover changed during optimization; the original was retained.");
  }
  await updateDoc(gameRef, { cover_image_url: nextCoverPath, updated_at: serverTimestamp() });
  return { id: gameId };
}

export async function updateFirebaseGameCardMetadata(gameId, cardId, currentMetadata, nextMetadata) {
  const cardRef = doc(firestore, "games", gameId, "game_cards", cardId);
  const snapshot = await getDoc(cardRef);
  if (!snapshot.exists()) throw new Error("The game card could not be found.");
  if (JSON.stringify(snapshot.data().metadata || {}) !== JSON.stringify(currentMetadata || {})) {
    throw new Error("Card metadata changed during optimization; the original asset remains active.");
  }
  await updateDoc(cardRef, { metadata: nextMetadata, updated_at: serverTimestamp() });
  return { id: cardId };
}
