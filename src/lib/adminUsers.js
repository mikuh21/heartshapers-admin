import { supabase } from "./supabase";

const ADMIN_USERS_FUNCTION =
  import.meta.env.VITE_ADMIN_USER_FUNCTION || "admin-user-management";
const ADMIN_MANAGEMENT_FUNCTION =
  import.meta.env.VITE_ADMIN_MANAGEMENT_FUNCTION || "admin-management";

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

  for (const value of sources) {
    const normalized = extractRoleValue(value);
    if (normalized) return normalized;
  }

  return null;
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
    )
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

export async function createUser({ full_name, email, password }) {
  let data;
  let error;
  try {
    ({ data, error } = await supabase.functions.invoke(ADMIN_USERS_FUNCTION, {
      body: {
        action: "create-user",
        full_name,
        email,
        password
      }
    }));
  } catch {
    throw new Error("Unable to create the user account right now. Please try again.");
  }

  if (error) {
    let code = null;
    try {
      const response = error.context;
      if (response && typeof response.json === "function") {
        code = (await response.json())?.error || null;
      }
    } catch {
      code = null;
    }

    throw new Error(getCreateUserErrorMessage(code, error.context?.status));
  }

  if (data?.error) {
    throw new Error(getCreateUserErrorMessage(data.error));
  }

  if (!data?.user) {
    throw new Error("Unable to create the user account right now. Please try again.");
  }

  return normalizeUser(data.user);
}

export async function listAdmins() {
  const { data, error } = await supabase.functions.invoke(ADMIN_MANAGEMENT_FUNCTION, {
    body: { action: "list" }
  });

  if (error) {
    throw new Error("Administrator management is unavailable right now.");
  }

  const admins = Array.isArray(data?.admins) ? data.admins : [];
  return admins.map(normalizeUser);
}

export async function createAdmin({ full_name, email, password }) {
  const { data, error } = await supabase.functions.invoke(ADMIN_MANAGEMENT_FUNCTION, {
    body: {
      action: "create",
      full_name,
      email,
      password
    }
  });

  if (error) {
    throw new Error("Unable to create the administrator account. Please try again.");
  }

  if (data?.error) {
    throw new Error(data.error || "Unable to create the administrator account. Please try again.");
  }

  return normalizeUser(data?.admin || data || null);
}

export async function updateAdminStatus(userId, disabled) {
  const { data, error } = await supabase.functions.invoke(ADMIN_MANAGEMENT_FUNCTION, {
    body: {
      action: "update-status",
      userId,
      disabled
    }
  });

  if (error) {
    throw new Error("Unable to update this administrator account right now.");
  }

  if (data?.error) {
    throw new Error(data.error || "Unable to update this administrator account right now.");
  }

  return normalizeUser(data?.admin || data || null);
}
