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
  return result.data?.logs || [];
}
