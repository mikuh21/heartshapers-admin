import { supabase } from "./supabase";

const ADMIN_USERS_FUNCTION =
  import.meta.env.VITE_ADMIN_USER_FUNCTION || "admin-user-management";

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
    )
  };
}

export function isAdminUser(user) {
  if (!user) return false;

  const appMetadata = user.app_metadata || {};
  const userMetadata = user.user_metadata || {};
  const candidates = [
    appMetadata.role,
    appMetadata.is_admin,
    appMetadata.isAdmin,
    appMetadata.admin,
    userMetadata.role,
    userMetadata.is_admin,
    userMetadata.isAdmin,
    userMetadata.admin,
    user.role
  ];

  const match = candidates.some((value) => {
    if (typeof value === "boolean") return value;
    if (typeof value === "string") return value.toLowerCase() === "admin";
    return false;
  });

  return match;
}

export async function listUsers() {
  const { data, error } = await supabase.functions.invoke(ADMIN_USERS_FUNCTION, {
    body: { action: "list" }
  });

  if (error) {
    throw new Error("User management is unavailable right now.");
  }

  const users = Array.isArray(data?.users) ? data.users : [];
  return users.map(normalizeUser);
}

export async function updateUserStatus(userId, disabled) {
  const { data, error } = await supabase.functions.invoke(ADMIN_USERS_FUNCTION, {
    body: {
      action: "update-status",
      userId,
      disabled
    }
  });

  if (error) {
    throw new Error("Unable to update this user account right now.");
  }

  return normalizeUser(data?.user || data || null);
}
