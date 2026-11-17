import { getFunctions, httpsCallable } from "firebase/functions";
import { firebaseApp } from "./firebase";

const functions = getFunctions(firebaseApp, "asia-southeast1");
const call = (name) => httpsCallable(functions, name);
export async function logAdminAction({ action, targetType = null, targetId = null, targetName = null, details = {} }) {
  try {
    await call("writeAdminAuditLog")({ action, targetType, targetId, targetName, details });
    return true;
  } catch (error) {
    console.error("Admin audit log write failed.", { action, code: error?.code || "UNKNOWN" });
    return false;
  }
}
export async function listAdminAuditLogs() {
  const result = await call("listAdminAuditLogs")({});
  const logs = Array.isArray(result.data?.logs) ? result.data.logs : [];
  const getMillis = (value) => {
    if (!value) return 0;
    if (typeof value?.toDate === "function") return value.toDate().getTime();
    if (typeof value === "number" || typeof value === "string") return new Date(value).getTime() || 0;
    const seconds = value.seconds ?? value._seconds;
    const nanos = value.nanoseconds ?? value._nanoseconds ?? 0;
    return Number.isFinite(Number(seconds)) ? Number(seconds) * 1000 + Number(nanos) / 1e6 : 0;
  };
  return logs.sort((left, right) => getMillis(right.created_at) - getMillis(left.created_at));
}
