import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  orderBy,
  setDoc,
  updateDoc,
  serverTimestamp,
} from "firebase/firestore";
import { getDownloadURL, ref, uploadBytes } from "firebase/storage";
import { firestore, firebaseStorage } from "./firebase";

/**
 * Firestore catalog contract shared with the Heartshapers mobile client:
 * books/{id}, games/{id}, gameRules/{id}, gameCards/{id},
 * gamePlacements/{id}, pillars/{id}, categories/{id}.
 * This module is additive: existing Supabase admin screens remain operational
 * until their Firebase writes and security rules are explicitly migrated.
 */

const BOOK_FIELDS = [
  "title", "author", "cover_image_url", "pdf_url", "pillar", "subcategory",
  "description", "keywords", "price", "is_locked",
];

function cleanPayload(payload, fields) {
  return Object.fromEntries(fields
    .filter((field) => payload[field] !== undefined)
    .map((field) => [field, payload[field]]));
}

export async function listFirebaseBooks({ includeDeleted = false } = {}) {
  const snapshot = await getDocs(query(collection(firestore, "books"), orderBy("created_at", "desc")));
  return snapshot.docs
    .map((item) => ({ id: item.id, ...item.data() }))
    .filter((item) => includeDeleted || (item.deleted_at == null && item.is_deleted !== true));
}

export async function saveFirebaseBook(bookId, payload) {
  if (!bookId) throw new Error("A book ID is required.");
  const bookRef = doc(firestore, "books", String(bookId));
  const existing = await getDoc(bookRef);
  const data = cleanPayload(payload, BOOK_FIELDS);
  data.updated_at = serverTimestamp();
  if (existing.exists()) {
    await updateDoc(bookRef, data);
  } else {
    data.created_at = serverTimestamp();
    data.deleted_at = null;
    await setDoc(bookRef, data);
  }
  return { id: String(bookId), ...data };
}

export async function softDeleteFirebaseBook(bookId) {
  if (!bookId) throw new Error("A book ID is required.");
  await updateDoc(doc(firestore, "books", String(bookId)), {
    deleted_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  });
}

export async function listFirebaseGames({ includeDeleted = false } = {}) {
  const snapshot = await getDocs(query(collection(firestore, "games"), orderBy("sort_order", "asc")));
  return snapshot.docs
    .map((item) => ({ id: item.id, ...item.data() }))
    .filter((item) => includeDeleted || (item.deleted_at == null && item.is_deleted !== true));
}

export async function saveFirebaseGame(gameId, payload) {
  if (!gameId) throw new Error("A game ID is required.");
  const fields = [
    "title", "subtitle", "description", "cover_image_url", "source_pdf_path",
    "game_type", "sort_order", "price", "is_locked",
  ];
  const gameRef = doc(firestore, "games", String(gameId));
  const existing = await getDoc(gameRef);
  const data = cleanPayload(payload, fields);
  data.updated_at = serverTimestamp();
  if (existing.exists()) {
    await updateDoc(gameRef, data);
  } else {
    data.created_at = serverTimestamp();
    data.deleted_at = null;
    await setDoc(gameRef, data);
  }
  return { id: String(gameId), ...data };
}

export async function saveFirebaseGameChildren(gameId, childCollection, children) {
  if (!gameId || !Array.isArray(children)) throw new Error("Game ID and child rows are required.");
  if (!["gameRules", "gameCards", "gamePlacements"].includes(childCollection)) {
    throw new Error("Unsupported game child collection.");
  }
  // Child IDs must be supplied by the publisher to keep retries idempotent.
  await Promise.all(children.map((child) => {
    if (!child?.id) throw new Error("Each game child row requires a stable ID.");
    return setDoc(doc(firestore, childCollection, String(child.id)), {
      ...child,
      game_id: String(gameId),
      updated_at: serverTimestamp(),
      created_at: child.created_at ?? serverTimestamp(),
    }, { merge: true });
  }));
}

export async function uploadFirebaseCatalogAsset(path, file) {
  if (!path || !file) throw new Error("Storage path and file are required.");
  const storageRef = ref(firebaseStorage, path);
  await uploadBytes(storageRef, file, {
    contentType: file.type || "application/octet-stream",
    cacheControl: "public,max-age=31536000,immutable",
  });
  return { path, downloadUrl: await getDownloadURL(storageRef) };
}

export async function getFirebaseCatalogDocument(collectionName, documentId) {
  if (!collectionName || !documentId) return null;
  const snapshot = await getDoc(doc(firestore, collectionName, String(documentId)));
  return snapshot.exists() ? { id: snapshot.id, ...snapshot.data() } : null;
}
