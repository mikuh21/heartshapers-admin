import { getFunctions, httpsCallable } from "firebase/functions";
import { firebaseApp } from "./firebase";

const BYTES_PER_MB = 1024 * 1024;
export const MAX_UPLOAD_SIZE_MB = 25;
export const DEFAULT_UPLOAD_SETTINGS = {
  maximum_upload_size_mb: 10,
  acceptable_file_types: ["pdf", "jpeg", "png", "webp"]
};
export const SUPPORTED_UPLOAD_TYPES = ["pdf", "jpeg", "png", "webp"];

const adminFunctions = getFunctions(firebaseApp, "asia-southeast1");
const getAdminSetting = httpsCallable(adminFunctions, "getAdminSetting");

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
  let value;
  try {
    const result = await getAdminSetting({ key: "upload_settings" });
    value = result.data?.value;
  } catch (error) {
    throw new Error(`Unable to load the configured upload limit from Firebase: ${error.message || "Settings request failed."}`);
  }

  const maximumMb = normalizeUploadSettings(value || DEFAULT_UPLOAD_SETTINGS).maximum_upload_size_mb;
  return {
    maximumMb,
    maximumBytes: maximumMb * BYTES_PER_MB
  };
}

export function gameUploadSizeError(limit) {
  return `Game files must be ${limit.maximumMb} MB or smaller, based on the current Upload Settings.`;
}

export function describeGameStorageUploadError(error, limit) {
  const message = error?.message || String(error || "Unknown Firebase Storage error.");
  const code = String(error?.code || "");
  if (/storage\/bucket-not-found|bucket not found/i.test(message + " " + code)) {
    return new Error(
      `Firebase Storage could not access the configured bucket. Verify the Firebase project configuration, bucket name, and Storage permissions. Storage response: ${message}`
    );
  }
  if (
    Number(error?.statusCode || error?.status) === 413
    || /storage\/unauthorized/i.test(code)
    || /entitytoolarge|payload too large|maximum.{0,20}size|file size limit/i.test(message)
  ) {
    return new Error(
      `Firebase Storage rejected the file within the ${limit.maximumMb} MB Admin upload limit. Check Firebase Storage rules and project limits. Storage response: ${message}`
    );
  }
  return error instanceof Error ? error : new Error(message);
}
