const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

function requireAdmin(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to review payments.");
  const role = String(request.auth.token.role || request.auth.token.roles || "").toLowerCase();
  if (!["admin", "super_admin"].includes(role)) {
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
