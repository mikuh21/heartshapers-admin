const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

function requireAdmin(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before optimizing a PDF.");
  const rawRoles = request.auth.token.roles;
  const roles = [...(Array.isArray(rawRoles) ? rawRoles : [rawRoles]), request.auth.token.role]
    .map(value => String(value || "").trim().toLowerCase()).filter(Boolean);
  if (!roles.some(role => ["admin", "super_admin"].includes(role))) {
    throw new HttpsError("permission-denied", "Only administrators can optimize PDFs.");
  }
}

async function getIdentityToken(audience) {
  const response = await fetch("http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=" +
    encodeURIComponent(audience) + "&format=full", { headers: { "Metadata-Flavor": "Google" } });
  if (!response.ok) throw new Error("Unable to obtain Cloud Run identity token.");
  return response.text();
}

exports.processPdfAsset = onCall({
  region: "asia-southeast1",
  memory: "1GiB",
  timeoutSeconds: 540,
  maxInstances: 5
}, async request => {
  requireAdmin(request);
  const assetType = String(request.data?.assetType || "");
  const assetId = String(request.data?.assetId || "");
  const sourcePath = String(request.data?.sourcePath || "");
  const bookPathParts = sourcePath.split("/");
  const bookFolders = bookPathParts.slice(1, -1);
  const validBookPath = bookPathParts.length >= 3 && bookPathParts.length <= 4 &&
    bookPathParts[0] === "pdfs" &&
    bookFolders.every(segment => segment && segment !== "." && segment !== ".." && !/[\\\\\\u0000-\\u001f]/.test(segment)) &&
    /^[A-Za-z0-9._-]+\\.pdf$/i.test(bookPathParts[bookPathParts.length - 1]) &&
    !bookFolders.includes("optimized");
  if (!["book", "game"].includes(assetType) ||
      !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(assetId) ||
      (assetType === "book" && !validBookPath) ||
      (assetType === "game" && (sourcePath.includes("..") || sourcePath.includes("\\\\") ||
        !new RegExp("^games/" + assetId + "/source/[A-Za-z0-9._-]+\\.pdf$", "i").test(sourcePath)))) {
    throw new HttpsError("invalid-argument", "Invalid PDF asset details.");
  }

  const expectedCurrentPath = request.data?.expectedCurrentPath == null ? null : String(request.data.expectedCurrentPath);
  if (expectedCurrentPath !== null) {
    const collectionName = assetType === "book" ? "books" : "games";
    const snapshot = await getFirestore().collection(collectionName).doc(assetId).get();
    const row = snapshot.data();
    const activePath = assetType === "book" ? row?.pdf_url : row?.source_pdf_path;
    if (!snapshot.exists || row?.deleted_at || activePath !== expectedCurrentPath) {
      throw new HttpsError("failed-precondition", "The active PDF changed before optimization. No Firestore reference was changed.");
    }
  }

  const workerUrl = String(process.env.PDF_WORKER_URL || "").replace(/\/$/, "");
  if (!workerUrl) throw new HttpsError("failed-precondition", "PDF_WORKER_URL is not configured for this function.");
  try {
    const token = await getIdentityToken(workerUrl);
    const response = await fetch(workerUrl + "/optimize", {
      method: "POST",
      headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ assetType, assetId, sourcePath }),
      signal: AbortSignal.timeout(500000)
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(result.error || "The PDF worker rejected the file.");
    const sourceDirectory = sourcePath.slice(0, sourcePath.lastIndexOf("/"));
    if (typeof result.optimizedPath !== "string" ||
        (assetType === "book" && !result.optimizedPath.startsWith(sourceDirectory + "/optimized/" + assetId + "/")) ||
        (assetType === "game" && !result.optimizedPath.startsWith("games/" + assetId + "/source/optimized-"))) {
      throw new Error("The PDF worker returned an invalid optimized Storage path.");
    }
    if (!(Number(result.optimizedBytes) > 0) || !(Number(result.originalBytes) > 0)) {
      throw new Error("The PDF worker returned invalid file sizes.");
    }
    if (Number(result.optimizedBytes) >= Number(result.originalBytes)) {
      await getStorage().bucket().file(result.optimizedPath).delete({ ignoreNotFound: true }).catch(() => {});
      return { optimized: false, path: sourcePath, originalBytes: Number(result.originalBytes), optimizedBytes: Number(result.optimizedBytes) };
    }
    return {
      optimized: true,
      path: result.optimizedPath,
      originalPath: sourcePath,
      originalBytes: Number(result.originalBytes),
      optimizedBytes: Number(result.optimizedBytes),
      savedBytes: Number(result.originalBytes) - Number(result.optimizedBytes)
    };
  } catch (error) {
    console.error("PDF processing failed", { assetType, assetId, message: error.message });
    throw new HttpsError("failed-precondition", error.message || "PDF optimization failed; the original file remains unchanged.");
  }
});
