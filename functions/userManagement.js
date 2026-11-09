const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { defineSecret } = require("firebase-functions/params");

const REGION = "asia-southeast1";
const db = getFirestore();
const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASSWORD = defineSecret("SMTP_PASSWORD");
const SMTP_FROM = defineSecret("SMTP_FROM");
const VERIFY_CONTINUE_URL = defineSecret("VERIFY_CONTINUE_URL");

function roleOf(request) {
  const roles = request.auth?.token?.roles;
  const role = request.auth?.token?.role;
  const candidates = [...(Array.isArray(roles) ? roles : [roles]), role];
  const normalized = candidates.map((value) => String(value || "").trim().toLowerCase()).filter(Boolean);
  if (normalized.includes("super_admin")) return "super_admin";
  if (normalized.includes("admin")) return "admin";
  return normalized[0] || "";
}

function requireAdmin(request, superAdmin = false) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const role = roleOf(request);
  if (superAdmin ? role !== "super_admin" : !["admin", "super_admin"].includes(role)) {
    throw new HttpsError("permission-denied", "You do not have permission for this operation.");
  }
}

function publicUser(user) {
  const claims = user.customClaims || {};
  const metadata = user.metadata || {};
  const tier = String(claims.membership_tier || "regular").toLowerCase() === "vip" ? "vip" : "regular";
  return {
    id: user.uid,
    email: user.email || "",
    full_name: user.displayName || user.customClaims?.full_name || "",
    created_at: metadata.creationTime || null,
    email_verified: Boolean(user.emailVerified),
    disabled: Boolean(user.disabled),
    membership_tier: tier,
    role: String(claims.role || claims.roles || "user").toLowerCase(),
  };
}

async function listAllUsers() {
  const auth = getAuth();
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

async function sendVerificationEmail(user) {
  const link = await getAuth().generateEmailVerificationLink(user.email, {
    url: VERIFY_CONTINUE_URL.value(),
    handleCodeInApp: false
  });
  const nodemailer = require("nodemailer");
  const transport = nodemailer.createTransport({
    host: SMTP_HOST.value(),
    port: Number(SMTP_PORT.value() || 587),
    secure: Number(SMTP_PORT.value() || 587) === 465,
    auth: { user: SMTP_USER.value(), pass: SMTP_PASSWORD.value() }
  });
  await transport.sendMail({
    from: SMTP_FROM.value(),
    to: user.email,
    subject: "Verify your HEARTSHAPERS account",
    text: `Hello ${user.displayName || "there"},\n\nPlease verify your HEARTSHAPERS account using this link:\n${link}\n\nIf you did not request this account, you can ignore this email.`,
    html: `<p>Hello ${user.displayName || "there"},</p><p>Please verify your HEARTSHAPERS account:</p><p><a href="${link}">Verify email address</a></p><p>If you did not request this account, you can ignore this email.</p>`
  });
}

async function sendPasswordResetEmail(user) {
  const link = await getAuth().generatePasswordResetLink(user.email, {
    url: VERIFY_CONTINUE_URL.value(),
    handleCodeInApp: false
  });
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
    subject: "Reset your HEARTSHAPERS password",
    text: `Hello ${user.displayName || "there"},\n\nUse this link to reset your HEARTSHAPERS password:\n${link}\n\nIf you did not request a password reset, you can ignore this email.`,
    html: `<p>Hello ${user.displayName || "there"},</p><p>Use this link to reset your HEARTSHAPERS password:</p><p><a href="${link}">Reset password</a></p><p>If you did not request a password reset, you can ignore this email.</p>`
  });
}
const MAIL_SECRETS = [SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, SMTP_FROM, VERIFY_CONTINUE_URL];

exports.sendUserVerificationEmail = onCall({ region: REGION, secrets: MAIL_SECRETS }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to request a verification email.");
  const user = await getAuth().getUser(request.auth.uid);
  if (user.disabled) throw new HttpsError("permission-denied", "This account is disabled.");
  if (!user.email) throw new HttpsError("failed-precondition", "This account has no email address.");
  if (user.emailVerified) throw new HttpsError("failed-precondition", "This email address is already verified.");

  const throttleRef = db.collection("email_delivery_limits").doc(`verify_${user.uid}`);
  const now = Date.now();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(throttleRef);
    const lastSentAt = Number(snapshot.data()?.verificationEmailLastSentAt || 0);
    if (now - lastSentAt < 60_000) {
      throw new HttpsError("resource-exhausted", "Please wait before requesting another verification email.");
    }
    transaction.set(throttleRef, {
      verificationEmailLastSentAt: now,
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  try {
    await sendVerificationEmail(user);
    return { sent: true };
  } catch (error) {
    console.error("User verification email delivery failed.", {
      uid: user.uid,
      code: error.code || error.name || "MAIL_FAILED",
    });
    throw new HttpsError("internal", "Unable to send the verification email right now.");
  }
});

exports.sendManagedPasswordResetEmail = onCall({ region: REGION, secrets: MAIL_SECRETS }, async (request) => {
  requireAdmin(request);
  const user = await getAuth().getUser(request.auth.uid);
  if (user.disabled) throw new HttpsError("permission-denied", "This account is disabled.");
  if (!user.email) throw new HttpsError("failed-precondition", "This account has no email address.");

  const throttleRef = db.collection("email_delivery_limits").doc(`reset_${user.uid}`);
  const now = Date.now();
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(throttleRef);
    const lastSentAt = Number(snapshot.data()?.passwordResetEmailLastSentAt || 0);
    if (now - lastSentAt < 60_000) {
      throw new HttpsError("resource-exhausted", "Please wait before requesting another password reset email.");
    }
    transaction.set(throttleRef, {
      passwordResetEmailLastSentAt: now,
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  });

  try {
    await sendPasswordResetEmail(user);
    return { sent: true };
  } catch (error) {
    console.error("Administrator password reset email delivery failed.", {
      uid: user.uid,
      code: error.code || error.name || "MAIL_FAILED",
    });
    throw new HttpsError("internal", "Unable to send the password reset email right now.");
  }
});

exports.listManagedUsers = onCall({ region: REGION }, async (request) => {
  requireAdmin(request);
  const users = await listAllUsers();
  return { users: users.filter((user) => !["admin", "super_admin"].includes(String(user.customClaims?.role || "").toLowerCase())).map(publicUser) };
});

exports.createManagedUser = onCall({ region: REGION, secrets: MAIL_SECRETS }, async (request) => {
  requireAdmin(request);
  const { full_name, email, password, membership_tier = "regular" } = request.data || {};
  const name = String(full_name || "").trim();
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!name) throw new HttpsError("invalid-argument", "FULL_NAME_REQUIRED");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) throw new HttpsError("invalid-argument", "EMAIL_INVALID");
  if (typeof password !== "string" || password.length < 8 || password.length > 16 || !/[^A-Za-z0-9]/.test(password)) {
    throw new HttpsError("invalid-argument", "PASSWORD_INVALID");
  }
  try {
    const user = await getAuth().createUser({ email: normalizedEmail, password, displayName: name, emailVerified: false, disabled: false });
    await getAuth().setCustomUserClaims(user.uid, { role: "user", membership_tier: String(membership_tier).toLowerCase() === "vip" ? "vip" : "regular" });
    await db.collection("users").doc(user.uid).set({
      uid: user.uid, email: normalizedEmail, full_name: name, role: "user",
      membership_tier: String(membership_tier).toLowerCase() === "vip" ? "vip" : "regular",
      email_verified: false, disabled: false, created_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()
    }, { merge: true });
    let emailSent = false;
    try { await sendVerificationEmail({ ...user, displayName: name }); emailSent = true; }
    catch (mailError) { console.error("Verification email delivery failed.", { uid: user.uid, code: mailError.code || mailError.name || "MAIL_FAILED" }); }
    return { user: publicUser({ ...user, customClaims: { role: "user", membership_tier }, displayName: name }), email_sent: emailSent };
  } catch (error) {
    if (error.code === "auth/email-already-exists") throw new HttpsError("already-exists", "EMAIL_ALREADY_EXISTS");
    throw new HttpsError("internal", "USER_CREATE_FAILED");
  }
});

exports.updateManagedUserStatus = onCall({ region: REGION }, async (request) => {
  requireAdmin(request);
  const { userId, disabled } = request.data || {};
  if (!userId || typeof disabled !== "boolean") throw new HttpsError("invalid-argument", "Invalid user status.");
  const target = await getAuth().getUser(String(userId));
  if (["admin", "super_admin"].includes(String(target.customClaims?.role || "").toLowerCase())) {
    throw new HttpsError("failed-precondition", "Administrator accounts must be managed separately.");
  }
  await getAuth().updateUser(String(userId), { disabled });
  await db.collection("users").doc(String(userId)).set({ disabled, updated_at: FieldValue.serverTimestamp() }, { merge: true });
  return { user: publicUser({ ...target, disabled }) };
});

exports.listManagedAdmins = onCall({ region: REGION }, async (request) => {
  requireAdmin(request);
  const users = await listAllUsers();
  return { admins: users.filter((user) => ["admin", "super_admin"].includes(String(user.customClaims?.role || "").toLowerCase())).map(publicUser) };
});

exports.createManagedAdmin = onCall({ region: REGION, secrets: MAIL_SECRETS }, async (request) => {
  requireAdmin(request, true);
  const { full_name, email, password } = request.data || {};
  const name = String(full_name || "").trim();
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!name) throw new HttpsError("invalid-argument", "Full name is required.");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) throw new HttpsError("invalid-argument", "Please enter a valid email address.");
  if (typeof password !== "string" || password.length < 8 || password.length > 16 || !/[^A-Za-z0-9]/.test(password)) {
    throw new HttpsError("invalid-argument", "Password must be 8–16 characters and contain at least one special character.");
  }
  try {
    const user = await getAuth().createUser({ email: normalizedEmail, password, displayName: name, emailVerified: false, disabled: false });
    await getAuth().setCustomUserClaims(user.uid, { role: "admin", full_name: name });
    await db.collection("users").doc(user.uid).set({
      uid: user.uid, email: normalizedEmail, full_name: name, role: "admin",
      email_verified: false, disabled: false, created_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp()
    }, { merge: true });
    let emailSent = false;
    try { await sendVerificationEmail({ ...user, displayName: name }); emailSent = true; }
    catch (mailError) { console.error("Administrator verification email delivery failed.", { uid: user.uid, code: mailError.code || mailError.name || "MAIL_FAILED" }); }
    return { admin: publicUser({ ...user, customClaims: { role: "admin", full_name: name }, displayName: name }), email_sent: emailSent };
  } catch (error) {
    if (error.code === "auth/email-already-exists") throw new HttpsError("already-exists", "An account with this email already exists.");
    throw new HttpsError("internal", "Unable to create the administrator account. Please try again.");
  }
});

exports.updateManagedAdminStatus = onCall({ region: REGION }, async (request) => {
  requireAdmin(request, true);
  const { userId, disabled } = request.data || {};
  if (!userId || typeof disabled !== "boolean") throw new HttpsError("invalid-argument", "Invalid administrator status.");
  if (String(userId) === request.auth.uid) throw new HttpsError("failed-precondition", "You cannot disable your own administrator account.");
  const target = await getAuth().getUser(String(userId));
  if (!["admin", "super_admin"].includes(String(target.customClaims?.role || "").toLowerCase())) {
    throw new HttpsError("failed-precondition", "The selected account is not an administrator.");
  }
  await getAuth().updateUser(String(userId), { disabled });
  await db.collection("users").doc(String(userId)).set({ disabled, updated_at: FieldValue.serverTimestamp() }, { merge: true });
  return { admin: publicUser({ ...target, disabled }) };
});


// Per-user book/game access overrides. Purchase records created by reviewCartPayment
// use stable IDs: {userId}_{bookId} and {userId}_{gameId}.
function validAccessStatus(value) {
  return value === "free" || value === "locked";
}
async function managedAccessUsers() {
  return (await listAllUsers()).filter((user) =>
    !["admin", "super_admin"].includes(String(user.customClaims?.role || "").toLowerCase())
  ).map(publicUser);
}
async function readUserAccess(request, itemId, itemCollection, purchaseCollection, overrideCollection, itemField, label) {
  requireAdmin(request);
  const id = String(itemId || "").trim();
  if (!id) throw new HttpsError("invalid-argument", `A ${label} ID is required.`);
  const itemSnapshot = await db.collection(itemCollection).doc(id).get();
  if (!itemSnapshot.exists || itemSnapshot.data().deleted_at) {
    throw new HttpsError("not-found", `The ${label} was not found or has been deleted.`);
  }
  const [users, purchasesSnapshot, overridesSnapshot] = await Promise.all([
    managedAccessUsers(),
    db.collection(purchaseCollection).where(itemField, "==", id).get(),
    db.collection(overrideCollection).where(itemField, "==", id).get()
  ]);
  const purchasedUserIds = [...new Set(purchasesSnapshot.docs.map((doc) => String(doc.data().user_id || "")).filter(Boolean))];
  const accessOverrides = overridesSnapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  return { [label]: { id: itemSnapshot.id, ...itemSnapshot.data() }, users, purchasedUserIds, accessOverrides };
}
exports.getManagedBookUserAccess = onCall({ region: REGION }, async (request) =>
  readUserAccess(request, request.data?.bookId, "books", "book_purchases", "user_book_access", "book_id", "book")
);
exports.getManagedGameUserAccess = onCall({ region: REGION }, async (request) =>
  readUserAccess(request, request.data?.gameId, "games", "game_purchases", "user_game_access", "game_id", "game")
);
async function setManagedUserAccess(request, itemId, userId, accessStatus, itemCollection, purchaseCollection, overrideCollection, itemField, label) {
  requireAdmin(request);
  const id = String(itemId || "").trim();
  const uid = String(userId || "").trim();
  if (!id || !uid || !validAccessStatus(accessStatus)) {
    throw new HttpsError("invalid-argument", "Invalid access override details.");
  }
  const itemRef = db.collection(itemCollection).doc(id);
  const userRef = db.collection("users").doc(uid);
  const purchaseRef = db.collection(purchaseCollection).doc(`${uid}_${id}`);
  const overrideRef = db.collection(overrideCollection).doc(`${uid}_${id}`);
  return db.runTransaction(async (tx) => {
    const [itemSnap, userSnap, purchaseSnap, overrideSnap] = await Promise.all([
      tx.get(itemRef), tx.get(userRef), tx.get(purchaseRef), tx.get(overrideRef)
    ]);
    if (!itemSnap.exists || itemSnap.data().deleted_at) throw new HttpsError("not-found", `The ${label} was not found or has been deleted.`);
    if (!userSnap.exists || String(userSnap.data().role || "user").toLowerCase() !== "user") {
      throw new HttpsError("not-found", "The selected user was not found.");
    }
    if (purchaseSnap.exists) throw new HttpsError("failed-precondition", "Verified purchases cannot be changed here.");
    const now = FieldValue.serverTimestamp();
    tx.set(overrideRef, {
      user_id: uid, [itemField]: id, access_status: accessStatus,
      updated_at: now, updated_by: request.auth.uid
    }, { merge: true });
    tx.set(db.collection("admin_logs").doc(), {
      action: `${label}_user_access_updated`,
      admin_email: request.auth.token.email || "",
      details: { user_id: uid, [itemField]: id, access_status: accessStatus, previous_access_status: overrideSnap.exists ? overrideSnap.data().access_status || null : null },
      created_at: now
    });
    return { accessStatus };
  });
}
exports.setManagedBookUserAccess = onCall({ region: REGION }, async (request) =>
  setManagedUserAccess(request, request.data?.bookId, request.data?.userId, request.data?.accessStatus, "books", "book_purchases", "user_book_access", "book_id", "book")
);
exports.setManagedGameUserAccess = onCall({ region: REGION }, async (request) =>
  setManagedUserAccess(request, request.data?.gameId, request.data?.userId, request.data?.accessStatus, "games", "game_purchases", "user_game_access", "game_id", "game")
);
