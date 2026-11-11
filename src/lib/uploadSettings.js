import { supabase } from "./supabase";

const BYTES_PER_MB = 1024 * 1024;
export const MAX_UPLOAD_SIZE_MB = 25;
export const DEFAULT_UPLOAD_SETTINGS = {
  maximum_upload_size_mb: 10,
  acceptable_file_types: ["pdf", "jpeg", "png", "webp"]
};
export const SUPPORTED_UPLOAD_TYPES = ["pdf", "jpeg", "png", "webp"];

export function normalizeUploadType(value) {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized) return "";
  return normalized === "jpg" || normalized === "jpeg" ? "jpeg" : normalized;
}

export function normalizeUploadSettings(rawValue = {}) {
  const configuredMaximum = Number(rawValue.maximum_upload_size_mb);
  const maximum = Number.isFinite(configuredMaximum)
    ? Math.max(0, Math.min(MAX_UPLOAD_SIZE_MB, Math.trunc(configuredMaximum)))
    : DEFAULT_UPLOAD_SETTINGS.maximum_upload_size_mb;
  const types = Array.isArray(rawValue.acceptable_file_types)
    ? rawValue.acceptable_file_types
      .map(normalizeUploadType)
      .filter((type) => SUPPORTED_UPLOAD_TYPES.includes(type))
    : DEFAULT_UPLOAD_SETTINGS.acceptable_file_types;

  return {
    maximum_upload_size_mb: maximum,
    acceptable_file_types: [...new Set(types)].length > 0
      ? [...new Set(types)]
      : [...DEFAULT_UPLOAD_SETTINGS.acceptable_file_types]
  };
}

export async function loadGameUploadLimit() {
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "upload_settings")
    .maybeSingle();

  if (error) {
    throw new Error(`Unable to load the configured upload limit: ${error.message || "Settings request failed."}`);
  }

  const maximumMb = normalizeUploadSettings(data?.value || DEFAULT_UPLOAD_SETTINGS).maximum_upload_size_mb;

  return {
    maximumMb,
    maximumBytes: maximumMb * BYTES_PER_MB
  };
}

export function gameUploadSizeError(limit) {
  return `Game files must be ${limit.maximumMb} MB or smaller, based on the current Upload Settings.`;
}

export function describeGameStorageUploadError(error, limit) {
  const code = String(error?.code || "");
  const message = error?.message || String(error || "Unknown Storage error.");
  const status = Number(error?.statusCode || error?.status);
  if (code === "storage/unauthenticated" || /sign in to firebase storage/i.test(message)) {
    return new Error(
      `Firebase Storage needs an authenticated admin session before it can accept this upload. Sign in again from the banner at the top of the admin. Storage response: ${message}`
    );
  }
  if (code === "storage/unauthorized") {
    return new Error(
      `Firebase Storage denied this upload. Confirm the signed-in account has an admin role in the deployed Storage rules. Storage response: ${message}`
    );
  }
  if (/bucket not found|bucket does not exist/i.test(message)) {
    return new Error(
      `The configured Firebase Storage bucket could not be reached. Verify VITE_FIREBASE_STORAGE_BUCKET and the deployed Storage rules. Storage response: ${message}`
    );
  }
  if (
    status === 413
    || /entitytoolarge|payload too large|maximum.{0,20}size|file size limit/i.test(message)
  ) {
    return new Error(
      `Firebase Storage rejected the file within the ${limit.maximumMb} MB Admin upload limit. Check the bucket's file-size limits. Storage response: ${message}`
    );
  }
  return error;
}
