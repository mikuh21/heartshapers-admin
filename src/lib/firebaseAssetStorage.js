import {
  deleteObject,
  getDownloadURL,
  ref,
  uploadBytes
} from "firebase/storage";
import { firebaseStorage } from "./firebase";

const CACHE_CONTROL = "public,max-age=31536000,immutable";

function assertStoragePath(path) {
  if (
    typeof path !== "string"
    || !path.trim()
    || path.startsWith("/")
    || path.split("/").some((segment) => !segment || segment === "." || segment === "..")
  ) {
    throw new Error("A valid relative Firebase Storage path is required.");
  }
}

/**
 * Uploads an asset to Firebase Storage with immutable cache metadata.
 * Callers should use versioned paths whenever an asset is replaced so
 * existing cached downloads remain valid and new assets receive new cache keys.
 */
export async function uploadFirebaseAsset(path, fileOrBlob, contentType) {
  assertStoragePath(path);
  if (!fileOrBlob || typeof fileOrBlob.size !== "number") {
    throw new Error("A valid file or Blob is required for upload.");
  }
  const resolvedContentType = contentType || fileOrBlob.type;
  if (!resolvedContentType) {
    throw new Error("The uploaded asset must have a content type.");
  }

  const storageRef = ref(firebaseStorage, path);
  const snapshot = await uploadBytes(storageRef, fileOrBlob, {
    contentType: resolvedContentType,
    cacheControl: CACHE_CONTROL
  });
  return {
    path: snapshot.ref.fullPath,
    downloadUrl: await getDownloadURL(snapshot.ref),
    size: snapshot.metadata.size,
    contentType: snapshot.metadata.contentType || resolvedContentType
  };
}

export async function getFirebaseAssetDownloadUrl(path) {
  assertStoragePath(path);
  return getDownloadURL(ref(firebaseStorage, path));
}

/**
 * Removes a Firebase Storage object. It deliberately does not remove Firestore
 * documents; callers must commit record changes and preserve protected history
 * before invoking asset cleanup.
 */
export async function deleteFirebaseAsset(path) {
  assertStoragePath(path);
  await deleteObject(ref(firebaseStorage, path));
}
