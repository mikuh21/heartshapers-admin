const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");
const crypto = require("node:crypto");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASSWORD = defineSecret("SMTP_PASSWORD");
const SMTP_FROM = defineSecret("SMTP_FROM");
const OTP_PEPPER = defineSecret("OTP_PEPPER");

initializeApp();
const db = getFirestore();

function requireAdmin(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to review payments.");
  const rawRoles = request.auth.token.roles;
  const roles = [...(Array.isArray(rawRoles) ? rawRoles : [rawRoles]), request.auth.token.role]
    .map((value) => String(value || "").trim().toLowerCase()).filter(Boolean);
  if (!roles.some((role) => ["admin", "super_admin"].includes(role))) {
    throw new HttpsError("permission-denied", "Only administrators can review payments.");
  }
}

exports.reviewCartPayment = onCall({ region: "asia-southeast1" }, async (request) => {
  requireAdmin(request);
  const { user_id, reference_number, proof_image_url, action, note } = request.data || {};
  if (!user_id || !reference_number || !proof_image_url || !["verify", "reject"].includes(action)) {
    throw new HttpsError("invalid-argument", "Missing or invalid payment review details.");
  }
  const rejectionNote = String(note || "").trim();
  if (action === "reject" && !rejectionNote) {
    throw new HttpsError("invalid-argument", "A rejection reason is required.");
  }

  const paymentCollections = [
    { name: "payment_submissions", itemField: "book_id", purchaseCollection: "book_purchases" },
    { name: "game_payment_submissions", itemField: "game_id", purchaseCollection: "game_purchases" },
  ];
  const adminId = request.auth.uid;
  const adminEmail = request.auth.token.email || "";

  return db.runTransaction(async (tx) => {
    const pending = [];
    for (const config of paymentCollections) {
      const snap = await tx.get(db.collection(config.name)
        .where("user_id", "==", user_id)
        .where("reference_number", "==", reference_number)
        .where("proof_image_url", "==", proof_image_url)
        .where("status", "==", "pending"));
      snap.docs.forEach((paymentDoc) => pending.push({ config, ref: paymentDoc.ref, row: paymentDoc.data() }));
    }
    if (!pending.length) throw new HttpsError("failed-precondition", "No pending items were found for this transaction.");

    // Read all existing purchase documents before issuing writes, preserving atomic cart review.
    const purchaseReads = [];
    if (action === "verify") {
      for (const item of pending) {
        const purchaseId = String(item.row.user_id) + "_" + String(item.row[item.config.itemField]);
        const purchaseRef = db.collection(item.config.purchaseCollection).doc(purchaseId);
        purchaseReads.push({ item, purchaseRef, purchaseSnapshot: await tx.get(purchaseRef) });
      }
    }

    const reviewedAt = new Date().toISOString();
    for (const item of pending) {
      tx.update(item.ref, {
        status: action === "verify" ? "verified" : "rejected",
        admin_id: adminId,
        reviewed_at: reviewedAt,
        admin_notes: action === "reject" ? rejectionNote : "",
      });
    }
    for (const purchase of purchaseReads) {
      if (!purchase.purchaseSnapshot.exists) {
        tx.create(purchase.purchaseRef, {
          user_id: String(purchase.item.row.user_id),
          [purchase.item.config.itemField]: String(purchase.item.row[purchase.item.config.itemField]),
          payment_id: purchase.item.ref.id,
          purchased_at: reviewedAt,
        });
      }
    }

    const logRef = db.collection("admin_logs").doc();
    tx.set(logRef, {
      action: action === "verify" ? "cart_payment_verified" : "cart_payment_rejected",
      admin_email: adminEmail,
      details: {
        user_id, reference_number, proof_image_url,
        items_reviewed: pending.length,
        rejection_reason: action === "reject" ? rejectionNote : null,
      },
      created_at: FieldValue.serverTimestamp(),
    });
    return { status: action === "verify" ? "verified" : "rejected", items_reviewed: pending.length };
  });
});

// Mobile cart submissions are validated and written here so prices, ownership,
// and payment status never depend on client-supplied Firestore writes.
exports.submitCartPayment = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before submitting a payment.");
  const uid = request.auth.uid;
  await requireActiveMobileDevice(request);
  if ((await getAuth().getUser(uid)).disabled) throw new HttpsError("permission-denied", "This account is disabled.");
  const { items, amount, reference_number, proof_image_url } = request.data || {};
  const reference = String(reference_number || "").trim();
  const proofPath = String(proof_image_url || "");
  if (!Array.isArray(items) || items.length < 1 || items.length > 20 || !reference || reference.length > 120 ||
      !proofPath.startsWith(`payment-proofs/${uid}/payments/`) || proofPath.includes("..")) {
    throw new HttpsError("invalid-argument", "Invalid cart payment details.");
  }
  const normalized = items.map((item) => ({ type: item?.type, id: String(item?.id || "").trim() }));
  if (normalized.some((item) => !["book", "game"].includes(item.type) || !item.id) ||
      new Set(normalized.map((item) => `${item.type}:${item.id}`)).size !== normalized.length) {
    throw new HttpsError("invalid-argument", "Your cart contains invalid or duplicate items.");
  }
  const configs = {
    book: { catalog: "books", purchases: "book_purchases", overrides: "user_book_access", itemField: "book_id", payments: "payment_submissions" },
    game: { catalog: "games", purchases: "game_purchases", overrides: "user_game_access", itemField: "game_id", payments: "game_payment_submissions" },
  };
  const refs = normalized.map((item) => {
    const config = configs[item.type];
    return { ...item, config,
      catalogRef: db.collection(config.catalog).doc(item.id),
      purchaseRef: db.collection(config.purchases).doc(`${uid}_${item.id}`),
      accessRef: db.collection(config.overrides).doc(`${uid}_${item.id}`),
      paymentRef: db.collection(config.payments).doc(),
    };
  });
  const profileRef = db.collection("users").doc(uid);
  return db.runTransaction(async (tx) => {
    const profile = await tx.get(profileRef);
    if (profile.exists && profile.data().disabled === true) throw new HttpsError("permission-denied", "This account is disabled.");
    const membership = String(request.auth.token.membership_tier || profile.data()?.membership_tier || "regular").toLowerCase();
    if (membership === "vip") throw new HttpsError("failed-precondition", "VIP membership includes all content.");
  const snapshots = await Promise.all(refs.flatMap((item) => [
      tx.get(item.catalogRef),
      tx.get(item.purchaseRef),
      tx.get(item.accessRef),
      tx.get(db.collection(item.config.payments)
        .where("user_id", "==", uid)
        .where(item.config.itemField, "==", item.id)
        .where("status", "==", "pending")),
    ]));
    let total = 0;
    const writes = [];
    for (let index = 0; index < refs.length; index += 1) {
      const item = refs[index];
      const [catalogSnap, purchaseSnap, accessSnap, pendingSnap] = snapshots.slice(index * 4, index * 4 + 4);
      if (!catalogSnap.exists || catalogSnap.data().deleted_at) throw new HttpsError("not-found", "A cart item is no longer available.");
      const catalog = catalogSnap.data();
      const access = accessSnap.exists ? accessSnap.data().access_status : null;
      const price = Number(catalog.price);
      if (!pendingSnap.empty) throw new HttpsError("already-exists", "Your payment is already under review.");
      if (purchaseSnap.exists || access === "free" || !(catalog.is_locked === true || access === "locked") || !Number.isFinite(price) || price <= 0) {
        throw new HttpsError("failed-precondition", "A cart item is already available or cannot be purchased.");
      }
      const cents = Math.round(price * 100);
      total += cents;
      writes.push({ item, cents });
    }
    if (!Number.isFinite(Number(amount)) || Math.round(Number(amount) * 100) !== total) {
      throw new HttpsError("failed-precondition", "The cart total changed. Please refresh and try again.");
    }
    const submittedAt = FieldValue.serverTimestamp();
    for (const { item, cents } of writes) {
      tx.create(item.paymentRef, {
        user_id: uid, [item.config.itemField]: item.id, status: "pending",
        reference_number: reference, proof_image_url: proofPath,
        amount: cents / 100, cart_amount: total / 100,
        created_at: submittedAt, admin_notes: "",
      });
    }
    return { submitted: true, items: writes.length };
  });
});

async function requireContentEntitlement(uid, type, itemId, request) {
  const isBook = type === "book";
  const collectionName = isBook ? "books" : "games";
  const purchaseCollection = isBook ? "book_purchases" : "game_purchases";
  const accessCollection = isBook ? "user_book_access" : "user_game_access";
  const itemField = isBook ? "book_id" : "game_id";
  const [user, item, purchase, access] = await Promise.all([
    getAuth().getUser(uid),
    db.collection(collectionName).doc(itemId).get(),
    db.collection(purchaseCollection).doc(`${uid}_${itemId}`).get(),
    db.collection(accessCollection).doc(`${uid}_${itemId}`).get(),
  ]);
  if (user.disabled || (await db.collection("users").doc(uid).get()).data()?.disabled === true) {
    throw new HttpsError("permission-denied", "This account is disabled.");
  }
  const roleValues = [...(Array.isArray(request.auth.token.roles) ? request.auth.token.roles : [request.auth.token.roles]), request.auth.token.role]
    .map((value) => String(value || "").toLowerCase());
  if (roleValues.some((role) => ["admin", "super_admin"].includes(role))) return;
  await requireActiveMobileDevice(request);
  if (!item.exists || item.data().deleted_at) throw new HttpsError("not-found", "This content is unavailable.");
  const tier = String(request.auth.token.membership_tier || user.customClaims?.membership_tier || "regular").toLowerCase();
  if (tier === "vip") return;
  if (purchase.exists) return;
  const status = access.exists ? access.data().access_status : null;
  if (status === "free" || (!item.data().is_locked && status !== "locked")) return;
  throw new HttpsError("permission-denied", "Your account does not have access to this content.");
}

async function requireActiveMobileDevice(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const tokenDeviceId = String(request.auth.token.device_id || "");
  if (!tokenDeviceId) throw new HttpsError("failed-precondition", "This app installation is not linked to the account. Sign out and sign in again.");
  const [user, bindingSnapshot] = await Promise.all([
    getAuth().getUser(request.auth.uid),
    db.collection("device_bindings").doc(request.auth.uid).get(),
  ]);
  if (user.disabled) throw new HttpsError("permission-denied", "This account is disabled.");
  if (!bindingSnapshot.exists || bindingSnapshot.data().device_id !== tokenDeviceId) {
    throw new HttpsError("permission-denied", "This account is linked to a different mobile device. Contact an administrator to reset its device link.");
  }
}

exports.claimMobileDevice = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before linking this device.");
  const deviceId = String(request.data?.deviceId || "");
  const platform = String(request.data?.platform || "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(deviceId) || !["android", "ios"].includes(platform)) {
    throw new HttpsError("invalid-argument", "Invalid mobile device details.");
  }

  const auth = getAuth();
  const user = await auth.getUser(request.auth.uid);
  if (user.disabled) throw new HttpsError("permission-denied", "This account is disabled.");
  const bindingRef = db.collection("device_bindings").doc(user.uid);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(bindingRef);
    const existingDeviceId = String(snapshot.data()?.device_id || "");
    if (existingDeviceId && existingDeviceId !== deviceId) {
      throw new HttpsError("failed-precondition", "This account is already linked to another mobile device. Contact an administrator to move it.");
    }
    transaction.set(bindingRef, {
      device_id: deviceId,
      platform,
      linked_at: snapshot.data()?.linked_at || FieldValue.serverTimestamp(),
      last_seen_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  await auth.setCustomUserClaims(user.uid, { ...(user.customClaims || {}), device_id: deviceId });
  return { linked: true };
});

exports.getProtectedBookPdfUrl = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to read this book.");
  const bookId = String(request.data?.bookId || "").trim();
  const storagePath = String(request.data?.storagePath || "");
  if (!bookId || !storagePath.startsWith("pdfs/") || storagePath.includes("..") || storagePath.includes("\\")) {
    throw new HttpsError("invalid-argument", "Invalid book PDF reference.");
  }
  const book = await db.collection("books").doc(bookId).get();
  if (!book.exists || book.data().deleted_at) throw new HttpsError("not-found", "This book is unavailable.");
  const rawCatalogPath = String(book.data().pdf_url || "").replace(/^\/+/, "");
  const legacyStorageMarker = "/storage/v1/object/";
  const legacyBucketMarker = "/pdfs/";
  let catalogPath = rawCatalogPath;
  if (/^https?:\/\//i.test(rawCatalogPath)) {
    const markerIndex = rawCatalogPath.indexOf(legacyStorageMarker);
    const bucketIndex = markerIndex >= 0
      ? rawCatalogPath.indexOf(legacyBucketMarker, markerIndex + legacyStorageMarker.length)
      : -1;
    if (bucketIndex >= 0) {
      const encodedPath = rawCatalogPath.slice(bucketIndex + legacyBucketMarker.length).split("?")[0];
      try {
        const objectPath = decodeURIComponent(encodedPath);
        catalogPath = objectPath.startsWith("pdfs/") ? objectPath : `pdfs/${objectPath}`;
      } catch {
        catalogPath = "";
      }
    }
  } else if (catalogPath && !catalogPath.startsWith("pdfs/")) {
    catalogPath = `pdfs/${catalogPath}`;
  }
  if (catalogPath !== storagePath) throw new HttpsError("permission-denied", "The PDF does not belong to this book.");
  await requireContentEntitlement(request.auth.uid, "book", bookId, request);
  const [url] = await getStorage().bucket().file(storagePath).getSignedUrl({
    action: "read", expires: Date.now() + 15 * 60 * 1000,
  });
  return { url, expiresInSeconds: 900 };
});

exports.getProtectedGameAssetUrls = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to open this game.");
  const paths = request.data?.paths;
  if (!Array.isArray(paths) || paths.length < 1 || paths.length > 100 ||
      paths.some((path) => typeof path !== "string" || path.includes("..") || path.includes("\\") || !/^games\/[^/]+\/cards\/.+/.test(path))) {
    throw new HttpsError("invalid-argument", "Invalid game card asset paths.");
  }
  const gameIds = [...new Set(paths.map((path) => path.split("/")[1]))];
  await Promise.all(gameIds.map((gameId) => requireContentEntitlement(request.auth.uid, "game", gameId, request)));
  const expiresAt = Date.now() + 15 * 60 * 1000;
  const bucket = getStorage().bucket();
  const urls = await Promise.all(paths.map(async (path) => {
    const [url] = await bucket.file(path).getSignedUrl({ action: "read", expires: expiresAt });
    return url;
  }));
  return { urls, expiresInSeconds: 900 };
});

// Game rules and card documents can contain paid content, so mobile clients
// must fetch them through this entitlement-checked callable instead of reading
// the nested Firestore collections directly.
exports.getProtectedGameContent = onCall({ region: "asia-southeast1" }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to open this game.");
  const gameId = String(request.data?.gameId || "").trim();
  const contentType = String(request.data?.contentType || "");
  if (!gameId || gameId.length > 128 || !["rules", "cards"].includes(contentType)) {
    throw new HttpsError("invalid-argument", "Invalid game content request.");
  }
  await requireContentEntitlement(request.auth.uid, "game", gameId, request);
  const collectionName = contentType === "cards" ? "game_cards" : "game_rules";
  const snapshot = await db.collection("games").doc(gameId)
    .collection(collectionName).orderBy("sort_order", "asc").get();
  const items = snapshot.docs.map((document) => ({ id: document.id, ...document.data() }));
  return { items };
});

function otpDigest(email, value) {
  return crypto.createHmac("sha256", OTP_PEPPER.value()).update(`${email}:${value}`).digest("hex");
}
function timingSafeEqualHex(left, right) {
  const a = Buffer.from(String(left || ""), "hex");
  const b = Buffer.from(String(right || ""), "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
exports.passwordResetOtp = onCall({
  region: "asia-southeast1",
  secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM, OTP_PEPPER],
}, async (request) => {
  const action = String(request.data?.action || "");
  const email = String(request.data?.email || "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new HttpsError("invalid-argument", "Enter a valid email address.");
  const resetRef = db.collection("password_reset_otps").doc(crypto.createHash("sha256").update(email).digest("hex"));
  if (action === "request-code") {
    const existing = await resetRef.get();
    if (existing.exists && existing.data().last_sent_at?.toMillis?.() > Date.now() - 60_000) return { ok: true };
    try {
      const user = await getAuth().getUserByEmail(email);
      if (!user.disabled) {
        const code = String(crypto.randomInt(0, 100000)).padStart(5, "0");
        await resetRef.set({ email, code_hash: otpDigest(email, code), expires_at: Date.now() + 10 * 60_000, attempts: 0, last_sent_at: FieldValue.serverTimestamp(), reset_token_hash: null }, { merge: false });
        const nodemailer = require("nodemailer");
        const port = Number(SMTP_PORT.value() || 587);
        const transport = nodemailer.createTransport({ host: SMTP_HOST.value(), port, secure: port === 465, auth: { user: SMTP_USER.value(), pass: SMTP_PASSWORD.value() } });
        await transport.sendMail({ from: SMTP_FROM.value(), to: user.email, subject: "Your HEARTSHAPERS password reset code", text: `Your password reset code is ${code}. It expires in 10 minutes.` });
      }
    } catch (error) {
      if (error?.code !== "auth/user-not-found") {
        console.error("Password reset request failed.", { code: error?.code || error?.name || "UNKNOWN" });
      }
    }
    return { ok: true };
  }
  if (action === "verify-code") {
    const code = String(request.data?.code || "");
    const snap = await resetRef.get();
    if (!snap.exists) throw new HttpsError("failed-precondition", "That code is invalid or has expired.");
    const data = snap.data();
    if (Number(data.expires_at) <= Date.now() || Number(data.attempts || 0) >= 5) {
      await resetRef.delete();
      throw new HttpsError("failed-precondition", "That code is invalid or has expired.");
    }
    if (!/^\d{5}$/.test(code) || !timingSafeEqualHex(data.code_hash, otpDigest(email, code))) {
      await resetRef.update({ attempts: FieldValue.increment(1) });
      throw new HttpsError("permission-denied", "That code is invalid or has expired.");
    }
    const token = crypto.randomBytes(32).toString("hex");
    await resetRef.update({ code_hash: null, reset_token_hash: otpDigest(email, token), reset_token_expires_at: Date.now() + 10 * 60_000 });
    return { ok: true, resetToken: token };
  }
  if (action === "reset-password") {
    const token = String(request.data?.resetToken || "");
    const password = request.data?.newPassword;
    if (typeof password !== "string" || password.length < 8 || password.length > 16 || !/[^A-Za-z0-9]/.test(password)) {
      throw new HttpsError("invalid-argument", "Password must be 8–16 characters and include a special character.");
    }
    const snap = await resetRef.get();
    const data = snap.data();
    if (!data || Number(data.reset_token_expires_at) <= Date.now() || !timingSafeEqualHex(data.reset_token_hash, otpDigest(email, token))) {
      throw new HttpsError("failed-precondition", "This reset session is invalid or has expired.");
    }
    const user = await getAuth().getUserByEmail(email);
    await getAuth().updateUser(user.uid, { password });
    await resetRef.delete();
    return { ok: true };
  }
  throw new HttpsError("invalid-argument", "Unsupported password reset action.");
});


exports.sendPaymentVerificationEmail = onCall({
  region: "asia-southeast1",
  secrets: [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM]
}, async (request) => {
  requireAdmin(request);
  const { user_id, reference_number } = request.data || {};
  if (!user_id || !reference_number) {
    throw new HttpsError("invalid-argument", "A user ID and payment reference number are required.");
  }

  let user;
  try {
    user = await getAuth().getUser(String(user_id));
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "The customer account could not be found.");
    }
    throw new HttpsError("internal", "Unable to retrieve the customer account.");
  }
  if (!user.email) throw new HttpsError("failed-precondition", "The customer account has no email address.");

  const nodemailer = require("nodemailer");
  const port = Number(SMTP_PORT.value() || 587);
  const transport = nodemailer.createTransport({
    host: SMTP_HOST.value(),
    port,
    secure: port === 465,
    auth: { user: SMTP_USER.value(), pass: SMTP_PASSWORD.value() }
  });
  await transport.sendMail({
    from: SMTP_FROM.value(),
    to: user.email,
    subject: "HEARTSHAPERS payment verified",
    text: `Hello ${user.displayName || "there"},\n\nYour payment has been verified successfully. Access to your purchased HEARTSHAPERS content has been granted.\n\nPayment reference: ${String(reference_number)}\n\nThank you for supporting HEARTSHAPERS.`
  });
  return { sent: true };
});

// Firebase Auth user and administrator management callables.
Object.assign(exports, require("./userManagement"));

const SETTINGS_KEYS = new Set(["upload_settings", "payment_settings", "cover_optimization_v1", "game_cover_optimization_v1", "pdf_game_card_image_optimization_v1"]);
exports.getAdminSetting = onCall({ region: "asia-southeast1" }, async (request) => {
  requireAdmin(request);
  const key = String(request.data?.key || "");
  if (!SETTINGS_KEYS.has(key)) throw new HttpsError("invalid-argument", "Unsupported admin setting key.");
  const snap = await db.collection("app_settings").doc(key).get();
  return { value: snap.exists ? snap.data().value : null };
});
exports.setAdminSetting = onCall({ region: "asia-southeast1" }, async (request) => {
  requireAdmin(request);
  const key = String(request.data?.key || "");
  if (!SETTINGS_KEYS.has(key) || !Object.prototype.hasOwnProperty.call(request.data || {}, "value")) {
    throw new HttpsError("invalid-argument", "Unsupported setting or missing value.");
  }
  const value = request.data.value;
  if (key === "payment_settings" && (!value || typeof value !== "object" || Array.isArray(value))) {
    throw new HttpsError("invalid-argument", "Payment settings must be an object.");
  }
  if (key === "upload_settings" && (!value || typeof value !== "object" || Array.isArray(value))) {
    throw new HttpsError("invalid-argument", "Upload settings must be an object.");
  }
  await db.collection("app_settings").doc(key).set({
    value, updated_at: FieldValue.serverTimestamp(), updated_by: request.auth.uid
  }, { merge: true });
  return { saved: true };
});
exports.listAdminAuditLogs = onCall({ region: "asia-southeast1" }, async (request) => {
  requireAdmin(request);
  const snap = await db.collection("admin_logs").orderBy("created_at", "desc").limit(500).get();
  return { logs: snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })) };
});
exports.writeAdminAuditLog = onCall({ region: "asia-southeast1" }, async (request) => {
  requireAdmin(request);
  const { action, targetType = null, targetId = null, targetName = null, details = {} } = request.data || {};
  if (typeof action !== "string" || !action.trim() || action.length > 120) {
    throw new HttpsError("invalid-argument", "A valid audit action is required.");
  }
  const redact = (value) => {
    if (Array.isArray(value)) return value.map(redact);
    if (!value || typeof value !== "object") return value;
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [
      key, /password|token|secret|credential|pin|api[_ -]?key/i.test(key) ? "[redacted]" : redact(item)
    ]));
  };
  await db.collection("admin_logs").add({
    action: action.trim(), admin_email: request.auth.token.email || null,
    details: redact({ ...(details && typeof details === "object" ? details : {}),
      ...(targetType ? { target_type: targetType } : {}),
      ...(targetId == null ? {} : { target_id: String(targetId) }),
      ...(targetName ? { target_name: targetName } : {}) }),
    created_at: FieldValue.serverTimestamp()
  });
  return { logged: true };
});
