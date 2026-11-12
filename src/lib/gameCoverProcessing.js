import { getFunctions, httpsCallable } from "firebase/functions";
import { firebaseApp } from "./firebase";
import { getFirebaseAssetDownloadUrl, uploadFirebaseAsset } from "./firebaseAssetStorage";
const functions = getFunctions(firebaseApp, "asia-southeast1");
const processGameCoverCallable = httpsCallable(functions, "processGameCover");
function coverExtension(file) {
  return { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" }[file?.type] || null;
}
export async function processFirebaseGameCover(gameId, fileOrPath, expectedCurrentCoverPath = null) {
  if (!gameId || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(String(gameId))) throw new Error("A valid game ID is required to process its cover.");
  let sourcePath;
  if (typeof fileOrPath === "string") {
    sourcePath = fileOrPath;
    if (!expectedCurrentCoverPath || expectedCurrentCoverPath !== sourcePath) throw new Error("Existing cover optimization requires the current cover path.");
  } else {
    const extension = coverExtension(fileOrPath);
    if (!extension) throw new Error("Choose a JPEG, PNG, or WebP cover image.");
    sourcePath = `games/${gameId}/cover/staging-${crypto.randomUUID()}.${extension}`;
    await uploadFirebaseAsset(sourcePath, fileOrPath, fileOrPath.type);
  }
  const result = await processGameCoverCallable({ gameId: String(gameId), sourcePath, expectedCurrentCoverPath });
  const optimizedPath = result.data?.optimizedPath;
  if (!optimizedPath) throw new Error("The server did not return an optimized game cover.");
  return { path: optimizedPath, downloadUrl: await getFirebaseAssetDownloadUrl(optimizedPath),
    originalBytes: result.data.originalBytes, optimizedBytes: result.data.optimizedBytes };
}
