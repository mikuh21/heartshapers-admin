import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  writeBatch,
  serverTimestamp
} from "firebase/firestore";
import { getBlob, ref } from "firebase/storage";
import { firestore, firebaseStorage } from "./firebase";
import { uploadFirebaseAsset, getFirebaseAssetDownloadUrl } from "./firebaseAssetStorage";
import {
  describeGameStorageUploadError,
  gameUploadSizeError,
  loadGameUploadLimit
} from "./uploadSettings";

function coverExtension(file) {
  return { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[file?.type];
}

async function optimizeCover(file) {
  if (!file || typeof createImageBitmap !== "function" || typeof document === "undefined") return file;
  let bitmap;
  try {
    bitmap = await createImageBitmap(file);
    const scale = Math.min(1, 1200 / Math.max(bitmap.width, bitmap.height));
    if (scale === 1 && file.size <= 350 * 1024) return file;
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext("2d");
    if (!context) return file;
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/webp", 0.78));
    if (!blob || blob.size >= file.size) return file;
    return new File([blob], "cover.webp", { type: "image/webp", lastModified: Date.now() });
  } catch {
    return file;
  } finally {
    bitmap?.close?.();
  }
}

async function optimizePage(blob) {
  if (!blob || typeof createImageBitmap !== "function" || typeof document === "undefined") {
    return { blob, contentType: blob?.type || "image/png", extension: blob?.type === "image/webp" ? "webp" : "png" };
  }
  let bitmap;
  try {
    bitmap = await createImageBitmap(blob);
    const canvas = document.createElement("canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    const context = canvas.getContext("2d");
    if (!context) return { blob, contentType: "image/png", extension: "png" };
    context.drawImage(bitmap, 0, 0);
    const webp = await new Promise((resolve) => canvas.toBlob(resolve, "image/webp", 0.78));
    if (!webp || webp.size >= blob.size) return { blob, contentType: "image/png", extension: "png" };
    return { blob: webp, contentType: "image/webp", extension: "webp" };
  } catch {
    return { blob, contentType: "image/png", extension: "png" };
  } finally {
    bitmap?.close?.();
  }
}

function validateGame(game) {
  if (!game?.id || !game.title?.trim()) throw new Error("A valid game ID and title are required.");
  const price = String(game.price ?? "");
  if (!/^\d+(\.\d{1,2})?$/.test(price) || !Number.isFinite(Number(price)) || Number(price) < 0) {
    throw new Error("Enter a valid price of zero or greater, with up to two decimal places.");
  }
  if (typeof game.is_locked !== "boolean" || !Number.isInteger(Number(game.sort_order))) {
    throw new Error("The game access setting or sort order is invalid.");
  }
}

async function uploadPdfPages(gameId, pageFiles, version) {
  const cards = [];
  for (let index = 0; index < pageFiles.length; index += 1) {
    const { pageNumber, blob } = pageFiles[index];
    const optimized = await optimizePage(blob);
    const path = `games/${gameId}/cards/${version}/page-${String(index + 1).padStart(4, "0")}.${optimized.extension}`;
    await uploadFirebaseAsset(path, optimized.blob, optimized.contentType);
    cards.push({
      id: `page-${String(index + 1).padStart(4, "0")}`,
      game_id: gameId,
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
  return cards;
}

async function writeCollectionInChunks(pathSegments, records) {
  for (let offset = 0; offset < records.length; offset += 450) {
    const batch = writeBatch(firestore);
    records.slice(offset, offset + 450).forEach((record) => {
      batch.set(doc(firestore, ...pathSegments, String(record.id)), {
        ...record,
        created_at: serverTimestamp(),
        updated_at: serverTimestamp()
      });
    });
    await batch.commit();
  }
}

export async function createFirebasePdfGame(gameData, coverFile, sourcePdfFile, pageFiles) {
  validateGame(gameData);
  if (!coverExtension(coverFile)) throw new Error("Choose a JPEG, PNG, or WebP cover image.");
  if (!sourcePdfFile || (sourcePdfFile.type !== "application/pdf" && !sourcePdfFile.name?.toLowerCase().endsWith(".pdf"))) {
    throw new Error("Choose a valid game content PDF.");
  }
  if (!Array.isArray(pageFiles) || !pageFiles.length) throw new Error("Select at least one PDF page for the card deck.");
  const limit = await loadGameUploadLimit();
  if (coverFile.size > limit.maximumBytes || sourcePdfFile.size > limit.maximumBytes) throw new Error(gameUploadSizeError(limit));
  const gameRef = doc(firestore, "games", gameData.id);
  if ((await getDoc(gameRef)).exists()) throw new Error("A game with this ID already exists.");

  const version = crypto.randomUUID();
  const cover = await optimizeCover(coverFile);
  const coverPath = `games/${gameData.id}/cover/${version}.${coverExtension(cover)}`;
  const sourcePath = `games/${gameData.id}/source/${version}.pdf`;
  try {
    await uploadFirebaseAsset(coverPath, cover, cover.type);
    await uploadFirebaseAsset(sourcePath, sourcePdfFile, "application/pdf");
    const cards = await uploadPdfPages(gameData.id, pageFiles, version);
    await writeCollectionInChunks(["games", gameData.id, "game_cards"], cards);
    const rules = [{
      id: "main",
      game_id: gameData.id,
      sort_order: 1,
      rule_text: gameData.rules.trim(),
      metadata: {}
    }];
    await writeCollectionInChunks(["games", gameData.id, "game_rules"], rules);
    const data = {
      id: gameData.id,
      title: gameData.title.trim(),
      game_type: "pdf_deck",
      subtitle: gameData.subtitle?.trim() || null,
      description: gameData.description?.trim() || null,
      price: Number(gameData.price),
      is_locked: gameData.is_locked,
      sort_order: Number(gameData.sort_order),
      cover_image_url: coverPath,
      source_pdf_path: sourcePath,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
      deleted_at: null
    };
    await setDoc(gameRef, data);
    return { ...data, cover_display_url: await getFirebaseAssetDownloadUrl(coverPath) };
  } catch (error) {
    // Keep versioned assets/documents if the outcome may be ambiguous. A retry
    // should first check the Games list rather than risk removing a live asset.
    console.error("Firebase PDF game publish did not complete cleanly.", { gameId: gameData.id });
    throw error instanceof Error ? error : new Error("Unable to publish the PDF game. Please verify the Games list before retrying.");
  }
}

export async function updateFirebasePdfGame(gameData, { coverFile = null, sourcePdfFile = null, pageFiles = null }) {
  validateGame(gameData);
  if (typeof gameData.rules !== "string" || !gameData.rules.trim()) throw new Error("Game rules are required.");
  const gameRef = doc(firestore, "games", gameData.id);
  const snapshot = await getDoc(gameRef);
  if (!snapshot.exists() || snapshot.data().deleted_at) throw new Error("This game could not be found or has been deleted.");
  const existing = snapshot.data();
  const update = {
    title: gameData.title.trim(),
    subtitle: gameData.subtitle?.trim() || null,
    description: gameData.description?.trim() || null,
    price: Number(gameData.price),
    is_locked: gameData.is_locked,
    sort_order: Number(gameData.sort_order),
    updated_at: serverTimestamp()
  };
  const limit = (coverFile || sourcePdfFile) ? await loadGameUploadLimit() : null;
  if ((coverFile && coverFile.size > limit.maximumBytes) || (sourcePdfFile && sourcePdfFile.size > limit.maximumBytes)) {
    throw new Error(gameUploadSizeError(limit));
  }
  const version = crypto.randomUUID();
  if (coverFile) {
    if (!coverExtension(coverFile)) throw new Error("Choose a JPEG, PNG, or WebP cover image.");
    const optimized = await optimizeCover(coverFile);
    const path = `games/${gameData.id}/cover/${version}.${coverExtension(optimized)}`;
    await uploadFirebaseAsset(path, optimized, optimized.type);
    update.cover_image_url = path;
  }
  if (sourcePdfFile) {
    if (sourcePdfFile.type !== "application/pdf" && !sourcePdfFile.name?.toLowerCase().endsWith(".pdf")) throw new Error("Choose a valid game content PDF.");
    const path = `games/${gameData.id}/source/${version}.pdf`;
    await uploadFirebaseAsset(path, sourcePdfFile, "application/pdf");
    update.source_pdf_path = path;
  }
  if (pageFiles !== null) {
    if (!Array.isArray(pageFiles) || !pageFiles.length) throw new Error("Select at least one PDF page for the card deck.");
    const cards = await uploadPdfPages(gameData.id, pageFiles, version);
    const existingCards = await getDocs(collection(firestore, "games", gameData.id, "game_cards"));
    const existingById = new Map(existingCards.docs.map((item) => [item.id, item]));
    for (let offset = 0; offset < cards.length; offset += 450) {
      const batch = writeBatch(firestore);
      cards.slice(offset, offset + 450).forEach((card) => {
        const previous = existingById.get(card.id);
        batch.set(doc(firestore, "games", gameData.id, "game_cards", card.id), {
          ...card,
          created_at: previous?.data()?.created_at || serverTimestamp(),
          updated_at: serverTimestamp()
        });
      });
      await batch.commit();
    }
    const retainedIds = new Set(cards.map((card) => card.id));
    const obsoleteCards = existingCards.docs.filter((item) => !retainedIds.has(item.id));
    for (let offset = 0; offset < obsoleteCards.length; offset += 450) {
      const batch = writeBatch(firestore);
      obsoleteCards.slice(offset, offset + 450).forEach((item) => batch.delete(item.ref));
      await batch.commit();
    }
  }
  const rulesRef = collection(firestore, "games", gameData.id, "game_rules");
  const existingRules = await getDocs(rulesRef);
  const rulesBatch = writeBatch(firestore);
  existingRules.docs.forEach((item) => rulesBatch.delete(item.ref));
  rulesBatch.set(doc(firestore, "games", gameData.id, "game_rules", "main"), {
    id: "main",
    game_id: gameData.id,
    sort_order: 1,
    rule_text: gameData.rules.trim(),
    metadata: {},
    updated_at: serverTimestamp()
  });
  await rulesBatch.commit();
  await updateDoc(gameRef, update);
  return { ...existing, ...update, assetCleanupWarning: false };
}

export async function downloadFirebasePdfGameSource(gameId, sourcePath) {
  if (typeof gameId !== "string" || typeof sourcePath !== "string" || !sourcePath.startsWith(`games/${gameId}/source/`)) {
    throw new Error("The PDF source path does not belong to this game.");
  }
  return getBlob(ref(firebaseStorage, sourcePath));
}
