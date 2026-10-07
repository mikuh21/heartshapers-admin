type AdminAuditEvent = {
  action: string;
  actorEmail?: string | null;
  targetType?: string | null;
  targetId?: string | null;
  targetName?: string | null;
  details?: Record<string, unknown>;
};

function sanitizeAuditDetails(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sanitizeAuditDetails);
  if (!value || typeof value !== "object") return value;

  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    /password|token|secret|credential|pin|api[_ -]?key/i.test(key)
      ? "[redacted]"
      : sanitizeAuditDetails(item)
  ]));
}

export async function insertAdminAuditLog(client: any, event: AdminAuditEvent): Promise<void> {
  try {
    const { error } = await client.from("admin_logs").insert({
      action: event.action,
      admin_email: event.actorEmail || null,
      details: sanitizeAuditDetails({
        ...(event.details || {}),
        ...(event.targetType ? { target_type: event.targetType } : {}),
        ...(event.targetId ? { target_id: event.targetId } : {}),
        ...(event.targetName ? { target_name: event.targetName } : {})
      })
    });

    if (error) {
      console.error("Admin audit log write failed.", {
        action: event.action,
        code: error.code || "UNKNOWN"
      });
    }
  } catch (error) {
    console.error("Admin audit log write failed.", {
      action: event.action,
      code: error instanceof Error ? error.name : "UNKNOWN"
    });
  }
}