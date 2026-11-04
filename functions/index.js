const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");
const { getAuth } = require("firebase-admin/auth");
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASSWORD = defineSecret("SMTP_PASSWORD");
const SMTP_FROM = defineSecret("SMTP_FROM");

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
