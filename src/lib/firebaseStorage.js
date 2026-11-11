import { onAuthStateChanged, signInWithEmailAndPassword, signOut } from "firebase/auth";
import { deleteObject, getBlob, getDownloadURL, ref, uploadBytes } from "firebase/storage";
import {
  firebaseAuth,
  firebaseStorage,
  isFirebaseConfigured,
  missingFirebaseSettings
} from "./firebase";

export const FIREBASE_NOT_CONFIGURED_MESSAGE = `Firebase Storage is not configured for this admin build. Add ${missingFirebaseSettings.join(", ") || "the VITE_FIREBASE_* settings"} to the environment.`;
export const FIREBASE_SIGN_IN_REQUIRED_MESSAGE = "Sign in to Firebase Storage before uploading files.";

function toStorageError(error, fallbackCode) {
  return {
    code: error?.code || fallbackCode,
    message: error?.message || "Firebase Storage request failed."
  };
}

export function assertFirebaseConfigured() {
  if (!isFirebaseConfigured) {
    throw new Error(FIREBASE_NOT_CONFIGURED_MESSAGE);
  }
}

function requireFirebaseSession() {
  assertFirebaseConfigured();
  if (!firebaseAuth.currentUser) {
    throw new Error(FIREBASE_SIGN_IN_REQUIRED_MESSAGE);
  }
  return firebaseAuth.currentUser;
}

export function subscribeToStorageAuth(callback) {
  if (!firebaseAuth) {
    callback(null);
    return () => {};
  }
  return onAuthStateChanged(firebaseAuth, callback);
}

export async function connectFirebaseStorage(email, password) {
  assertFirebaseConfigured();
  const credential = await signInWithEmailAndPassword(
    firebaseAuth,
    String(email || "").trim(),
    String(password || "")
  );
  // Refresh once so role/admin custom claims from Storage rules are present.
  let claims = {};
  try {
    claims = (await credential.user.getIdTokenResult(true)).claims;
  } catch {
    // Uploads still work if the refresh fails; the token from sign-in is valid.
  }
  return { user: credential.user, claims };
}

export async function disconnectFirebaseStorage() {
  if (firebaseAuth) {
    await signOut(firebaseAuth);
  }
}

export async function uploadStorageObject(path, file, options = {}) {
  try {
    requireFirebaseSession();
    const contentType = options.contentType || file?.type || undefined;
    const cacheControl = options.cacheControl
      ? `public, max-age=${String(options.cacheControl).replace(/^public,\s*max-age=/, "")}`
      : "public, max-age=31536000";
    const metadata = { cacheControl };
    if (contentType) metadata.contentType = contentType;
    await uploadBytes(ref(firebaseStorage, path), file, metadata);
    return { error: null };
  } catch (error) {
    return { error: toStorageError(error, "storage/upload-failed") };
  }
}

export async function getStorageUrl(path) {
  try {
    assertFirebaseConfigured();
    const url = await getDownloadURL(ref(firebaseStorage, path));
    return { data: { publicUrl: url, signedUrl: url }, error: null };
  } catch (error) {
    return { data: null, error: toStorageError(error, "storage/url-failed") };
  }
}

export async function resolveStorageAssetUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  if (/^https?:\/\//i.test(raw)) return raw;
  const { data } = await getStorageUrl(raw);
  return data?.publicUrl || "";
}

export async function deleteStorageObjects(paths) {
  const targets = (Array.isArray(paths) ? paths : [paths]).filter(Boolean);
  if (targets.length === 0) return { error: null };
  try {
    requireFirebaseSession();
    await Promise.all(targets.map(async (path) => {
      try {
        await deleteObject(ref(firebaseStorage, path));
      } catch (error) {
        if (error?.code !== "storage/object-not-found") throw error;
      }
    }));
    return { error: null };
  } catch (error) {
    return { error: toStorageError(error, "storage/delete-failed") };
  }
}

export async function downloadStorageFile(path) {
  requireFirebaseSession();
  return getBlob(ref(firebaseStorage, path));
}
