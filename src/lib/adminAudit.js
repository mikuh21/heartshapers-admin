import { createClient } from "@supabase/supabase-js";
import { supabase } from "./supabase";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

function sanitizeAuditDetails(value) {
  if (Array.isArray(value)) return value.map(sanitizeAuditDetails);
  if (!value || typeof value !== "object") return value;

  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    /password|token|secret|credential|pin|api[_ -]?key/i.test(key)
      ? "[redacted]"
      : sanitizeAuditDetails(item)
  ]));
}

export async function logAdminAction({
  action,
  targetType = null,
  targetId = null,
  targetName = null,
  details = {}
}, accessToken = null) {
  try {
    const { data: userData, error } = accessToken
      ? await supabase.auth.getUser(accessToken)
      : await supabase.auth.getUser();
    const actor = userData?.user;

    if (error || !actor) {
      console.error("Admin audit log actor unavailable.", {
        action,
        code: error?.code || "AUTH_USER_UNAVAILABLE"
      });
      return false;
    }

    const client = accessToken
      ? createClient(supabaseUrl, anonKey, {
          global: { headers: { Authorization: `Bearer ${accessToken}` } },
          auth: { persistSession: false, autoRefreshToken: false }
        })
      : supabase;
    const { error: insertError } = await client.from("admin_logs").insert({
      action,
      admin_email: actor.email || null,
      details: sanitizeAuditDetails({
        ...details,
        ...(targetType ? { target_type: targetType } : {}),
        ...(targetId == null ? {} : { target_id: String(targetId) }),
        ...(targetName ? { target_name: targetName } : {})
      })
    });

    if (insertError) {
      console.error("Admin audit log write failed.", {
        action,
        code: insertError.code || "UNKNOWN"
      });
      return false;
    }

    return true;
  } catch (error) {
    console.error("Admin audit log write failed.", {
      action,
      code: error?.code || error?.name || "UNKNOWN"
    });
    return false;
  }
}
