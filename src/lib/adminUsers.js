import { getFunctions, httpsCallable } from "firebase/functions";
import { firebaseApp } from "./firebase";

const firebaseFunctions = getFunctions(firebaseApp, "asia-southeast1");
async function callUserManagement(name, payload = {}) {
  try {
    const result = await httpsCallable(firebaseFunctions, name)(payload);
    return result.data || {};
  } catch (error) {
    const code = String(error?.code || "").split("/").pop();
    if (code === "already-exists") throw new Error("An account with this email already exists.");
    if (code === "permission-denied") throw new Error("You do not have permission to perform this action.");
    if (code === "unauthenticated") throw new Error("Your administrator session has expired. Sign in again.");
    throw new Error(String(error?.message || "User management is unavailable right now."));
  }
}

export const ADMIN_WEB_ALLOWED_ROLES = ["admin", "super_admin"];
export const NORMAL_MOBILE_ROLE = "user";

function extractRoleValue(value) {
  if (!value) return null;
  if (Array.isArray(value)) {
    return value.map((item) => String(item).trim().toLowerCase()).find(Boolean) || null;
  }
  if (typeof value === "string") {
    return value.trim().toLowerCase();
  }
  return String(value).trim().toLowerCase();
}

export function getAuthRole(user) {
  if (!user) return null;

  const appMetadata = user.app_metadata || {};
  const userMetadata = user.user_metadata || {};
  const sources = [
    appMetadata.role,
    appMetadata.roles,
    appMetadata.access_level,
    userMetadata.role,
    userMetadata.roles,
    userMetadata.access_level,
    user.role
  ];

  const normalizedRoles = sources
    .flatMap((value) => Array.isArray(value) ? value : [value])
    .map((value) => String(value || "").trim().toLowerCase())
    .filter(Boolean);
  if (normalizedRoles.includes("super_admin")) return "super_admin";
  return normalizedRoles.find(Boolean) || null;
}

function normalizeUser(rawUser = {}) {
  const appMetadata = rawUser.app_metadata || {};
  const userMetadata = rawUser.user_metadata || {};
  const fullName =
    userMetadata.full_name ||
    userMetadata.fullName ||
    appMetadata.full_name ||
    appMetadata.fullName ||
    rawUser.full_name ||
    rawUser.name ||
    "";

  return {
    id: rawUser.id,
    email: rawUser.email || "",
    full_name: fullName,
    created_at: rawUser.created_at || rawUser.createdAt || null,
    email_verified: Boolean(
      rawUser.email_confirmed_at ||
        rawUser.email_verified ||
        rawUser.confirmed_at ||
        appMetadata.email_verified ||
        userMetadata.email_verified
    ),
    disabled: Boolean(
      rawUser.disabled ||
        rawUser.banned_until ||
        appMetadata.disabled ||
        appMetadata.is_disabled ||
        userMetadata.disabled ||
        userMetadata.is_disabled
    ),
    membership_tier: String(appMetadata.membership_tier || rawUser.membership_tier || "regular").trim().toLowerCase() === "vip"
      ? "vip"
      : "regular"
  };
}

export function isNormalUser(user) {
  return getAuthRole(user) === NORMAL_MOBILE_ROLE;
}

export function isAdminWebUser(user) {
  const role = getAuthRole(user);
  return ADMIN_WEB_ALLOWED_ROLES.includes(role);
}

export function isSuperAdmin(user) {
  return getAuthRole(user) === "super_admin";
}

export function isAdminUser(user) {
  return isAdminWebUser(user);
}

export async function listUsers() {
  const data = await callUserManagement("listManagedUsers");
  return (Array.isArray(data.users) ? data.users : []).map(normalizeUser);
}


export async function getBookUserAccess(bookId) {
  const data = await callUserManagement("getManagedBookUserAccess", { bookId });
  return {
    book: data.book,
    users: (data.users || []).map(normalizeUser),
    purchasedUserIds: data.purchasedUserIds || [],
    accessOverrides: data.accessOverrides || []
  };
}

export async function updateBookUserAccess({ bookId, userId, accessStatus }) {
  const data = await callUserManagement("setManagedBookUserAccess", { bookId, userId, accessStatus });
  return data.accessStatus;
}

export async function getGameUserAccess(gameId) {
  const data = await callUserManagement("getManagedGameUserAccess", { gameId });
  return {
    game: data.game,
    users: (data.users || []).map(normalizeUser),
    purchasedUserIds: data.purchasedUserIds || [],
    accessOverrides: data.accessOverrides || []
  };
}

export async function updateGameUserAccess({ gameId, userId, accessStatus }) {
  const data = await callUserManagement("setManagedGameUserAccess", { gameId, userId, accessStatus });
  return data.accessStatus;
}

export async function updateUserStatus(userId, disabled) {
  const data = await callUserManagement("updateManagedUserStatus", { userId, disabled });
  return normalizeUser(data.user || data || null);
}

function getCreateUserErrorMessage(code, status) {
  const messages = {
    FULL_NAME_REQUIRED: "Full name is required.",
    EMAIL_INVALID: "Please enter a valid Gmail address.",
    PASSWORD_INVALID: "Password must be 8–16 characters and contain at least one special character.",
    EMAIL_ALREADY_EXISTS: "An account with this email already exists.",
    USER_CREATE_FAILED: "Unable to create the user account right now. Please try again.",
    VERIFICATION_EMAIL_FAILED: "Unable to send the verification email. Please try again.",
    UNAUTHORIZED: "Your administrator session is no longer authorized. Sign in again and retry.",
    FORBIDDEN: "You do not have permission to create user accounts.",
  };

  return messages[code] || (status === 401
    ? messages.UNAUTHORIZED
    : status === 403
      ? messages.FORBIDDEN
      : "Unable to create the user account right now. Please try again.");
}

export async function createUser({ full_name, email, password, membership_tier = "regular" }) {
  const data = await callUserManagement("createManagedUser", { full_name, email, password, membership_tier });
  if (!data?.user) throw new Error("Unable to create the user account right now. Please try again.");
  return normalizeUser(data.user);
}

export async function listAdmins() {
  const data = await callUserManagement("listManagedAdmins");
  return (Array.isArray(data.admins) ? data.admins : []).map(normalizeUser);
}

export async function createAdmin({ full_name, email, password }) {
  const data = await callUserManagement("createManagedAdmin", { full_name, email, password });
  if (!data?.admin) throw new Error("Unable to create the administrator account. Please try again.");
  return normalizeUser(data.admin);
}

export async function updateAdminStatus(userId, disabled) {
  const data = await callUserManagement("updateManagedAdminStatus", { userId, disabled });
  if (!data?.admin) throw new Error("Unable to update this administrator account right now.");
  return normalizeUser(data.admin);
}
