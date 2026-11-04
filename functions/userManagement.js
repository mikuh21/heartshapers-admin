const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

const REGION = "asia-southeast1";
const db = getFirestore();

function roleOf(request) {
  const roles = request.auth?.token?.roles;
  const role = request.auth?.token?.role;
  const candidates = Array.isArray(roles) ? roles : [roles, role];
  return candidates.map((value) => String(value || "").trim().toLowerCase()).find(Boolean) || "";
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

exports.listManagedUsers = onCall({ region: REGION }, async (request) => {
  requireAdmin(request);
  const users = await listAllUsers();
  return { users: users.filter((user) => !["admin", "super_admin"].includes(String(user.customClaims?.role || "").toLowerCase())).map(publicUser) };
});

exports.createManagedUser = onCall({ region: REGION }, async (request) => {
  requireAdmin(request);
  const { full_name, email, password, membership_tier = "regular" } = request.data || {};
  const name = String(full_name || "").trim();
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!name) throw new HttpsError("invalid-argument", "FULL_NAME_REQUIRED");
  if (!/^[^\\s@]+@gmail\\.com$/i.test(normalizedEmail)) throw new HttpsError("invalid-argument", "EMAIL_INVALID");
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
    return { user: publicUser({ ...user, customClaims: { role: "user", membership_tier }, displayName: name }) };
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

exports.createManagedAdmin = onCall({ region: REGION }, async (request) => {
  requireAdmin(request, true);
  const { full_name, email, password } = request.data || {};
  const name = String(full_name || "").trim();
  const normalizedEmail = String(email || "").trim().toLowerCase();
  if (!name) throw new HttpsError("invalid-argument", "Full name is required.");
  if (!/^[^\\s@]+@gmail\\.com$/i.test(normalizedEmail)) throw new HttpsError("invalid-argument", "Please enter a valid Gmail address.");
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
    return { admin: publicUser({ ...user, customClaims: { role: "admin", full_name: name }, displayName: name }) };
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
