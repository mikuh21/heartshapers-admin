const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const crypto = require("node:crypto");
const sharp = require("sharp");
function requireAdmin(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before optimizing a game cover.");
  const rawRoles = request.auth.token.roles;
  const roles = [...(Array.isArray(rawRoles) ? rawRoles : [rawRoles]), request.auth.token.role].map((value) => String(value || "").trim().toLowerCase()).filter(Boolean);
  if (!roles.some((role) => ["admin", "super_admin"].includes(role))) throw new HttpsError("permission-denied", "Only administrators can optimize game covers.");
}
exports.processGameCover = onCall({ region: "asia-southeast1", memory: "1GiB", timeoutSeconds: 120 }, async (request) => {
  requireAdmin(request);
  const gameId = String(request.data?.gameId || "").trim();
  const sourcePath = String(request.data?.sourcePath || "");
  const expectedCurrentCoverPath = request.data?.expectedCurrentCoverPath == null ? null : String(request.data.expectedCurrentCoverPath);
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(gameId) || sourcePath.includes("..") || sourcePath.includes("\\") ||
      !sourcePath.startsWith(`games/${gameId}/cover/`) ||
      !/^games\/[A-Za-z0-9][A-Za-z0-9_-]{0,127}\/cover\/[A-Za-z0-9._-]+\.(?:jpe?g|png|webp)$/i.test(sourcePath)) {
    throw new HttpsError("invalid-argument", "Invalid game cover image path.");
  }
  const db = getFirestore();
  if (expectedCurrentCoverPath !== null) {
    const game = await db.collection("games").doc(gameId).get();
    if (!game.exists || game.data().deleted_at || game.data().cover_image_url !== expectedCurrentCoverPath || sourcePath !== expectedCurrentCoverPath)
      throw new HttpsError("failed-precondition", "The game cover changed before optimization. The active cover was not changed.");
  } else if (!sourcePath.includes("/staging-")) throw new HttpsError("invalid-argument", "New game covers must use a temporary staging path.");
  const bucket = getStorage().bucket();
  const source = bucket.file(sourcePath);
  const [metadata] = await source.getMetadata().catch(() => { throw new HttpsError("not-found", "The source game cover could not be found in Storage."); });
  const size = Number(metadata.size || 0);
  if (!size || size > 25 * 1024 * 1024) throw new HttpsError("failed-precondition", "The game cover must be smaller than 25 MB.");
  const [input] = await source.download();
  try {
    const image = sharp(input, { failOn: "error", limitInputPixels: 40000000 });
    const details = await image.metadata();
    if (!["jpeg", "png", "webp"].includes(details.format)) throw new Error("Only JPEG, PNG, and WebP game covers are supported.");
    const output = await image.rotate().resize({ width: 1200, height: 1200, fit: "inside", withoutEnlargement: true }).webp({ quality: 78, effort: 5 }).toBuffer();
    const outputPath = `games/${gameId}/cover/${crypto.randomUUID()}.webp`;
    await bucket.file(outputPath).save(output, { resumable: false, metadata: {
      contentType: "image/webp", cacheControl: "public,max-age=31536000,immutable", metadata: { optimizedBy: "sharp", sourcePath }
    }});
    return { optimizedPath: outputPath, originalBytes: size, optimizedBytes: output.length };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("invalid-argument", error?.message || "The selected game cover could not be optimized.");
  }
});
