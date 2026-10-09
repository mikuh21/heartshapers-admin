/// <reference lib="deno.ns" />

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

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

async function insertAdminAuditLog(client: any, event: AdminAuditEvent): Promise<void> {
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

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function getRole(user: any): string | null {
  const appMetadata = user?.app_metadata || {};

  const role = appMetadata.role;

  if (!role) {
    return null;
  }

  return String(role).trim().toLowerCase();
}

function isAdminIdentity(user: any): boolean {
  const role = getRole(user);

  return role === "admin" || role === "super_admin";
}

function normalizeUser(user: any) {
  const userMetadata = user?.user_metadata || {};

  return {
    id: user?.id,
    email: user?.email || "",
    full_name:
      userMetadata?.full_name ||
      userMetadata?.fullName ||
      userMetadata?.name ||
      "",
    created_at: user?.created_at || null,
    email_verified: Boolean(
      user?.email_confirmed_at || user?.confirmed_at,
    ),
    disabled: Boolean(user?.banned_until),
  };
}

async function listAllNormalUsers(adminClient: any) {
  const normalUsers = [];
  const perPage = 1000;
  let page = 1;

  while (true) {
    const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
    if (error) throw error;

    const pageUsers = data?.users || [];
    normalUsers.push(...pageUsers.filter((user: any) =>
      String(user?.app_metadata?.role || "user").trim().toLowerCase() === "user"
    ));

    if (pageUsers.length < perPage) break;
    page += 1;
  }

  return normalUsers;
}

async function listAllRowsForBook(adminClient: any, table: string, columns: string, bookId: string) {
  const rows: any[] = [];
  const perPage = 1000;
  let from = 0;

  while (true) {
    const { data, error } = await adminClient
      .from(table)
      .select(columns)
      .eq("book_id", bookId)
      .order("user_id", { ascending: true })
      .range(from, from + perPage - 1);
    if (error) throw error;

    const pageRows = data || [];
    rows.push(...pageRows);
    if (pageRows.length < perPage) break;
    from += perPage;
  }

  return rows;
}

async function listAllRowsForGame(adminClient: any, columns: string, gameId: string) {
  const rows: any[] = [];
  const perPage = 1000;
  let from = 0;

  while (true) {
    const { data, error } = await adminClient
      .from("user_game_access")
      .select(columns)
      .eq("game_id", gameId)
      .order("user_id", { ascending: true })
      .range(from, from + perPage - 1);
    if (error) throw error;

    const pageRows = data || [];
    rows.push(...pageRows);
    if (pageRows.length < perPage) break;
    from += perPage;
  }

  return rows;
}

function logBookAccessFailure(operation: string, table: string, error: any) {
  console.error("Book access data request failed.", {
    operation,
    table,
    code: error?.code || null,
    message: error?.message || "Unknown backend error",
    status: error?.status || error?.statusCode || null
  });
}

function logGameAccessFailure(operation: string, table: string, error: any) {
  console.error("Game access data request failed.", {
    operation,
    table,
    code: error?.code || null,
    message: error?.message || "Unknown backend error",
    status: error?.status || error?.statusCode || null
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Handle browser CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  try {
    // Verify required Supabase environment variables
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
      console.error("Missing required Supabase environment variables");

      return jsonResponse(
        {
          error: "Server configuration error",
        },
        500,
      );
    }

    // Get the user's access token
    const authHeader = req.headers.get("Authorization");

    if (!authHeader?.startsWith("Bearer ")) {
      console.error("Missing or invalid authorization header");

      return jsonResponse(
        {
          error: "Unauthorized",
        },
        401,
      );
    }

    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    // Authenticate the requesting user
    const userClient = createClient(
      SUPABASE_URL,
      ANON_KEY,
      {
        global: {
          headers: {
            Authorization: `Bearer ${jwt}`,
          },
        },
      },
    );

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      console.error(
        "Unable to authenticate requesting user:",
        userError?.message,
      );

      return jsonResponse(
        {
          error: "Unauthorized",
        },
        401,
      );
    }

    const role = getRole(user);

    console.log(
      "Authenticated request:",
      user.email,
      "role:",
      role,
    );

    // Only admins and super admins can access this function
    if (!isAdminIdentity(user)) {
      const auditClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false }
      });
      const attemptedBody = await req.clone().json().catch(() => ({}));
      await insertAdminAuditLog(auditClient, {
        action: attemptedBody?.action === "admin_login_access_denied"
          ? "admin_login_access_denied"
          : "unauthorized_admin_action_attempt",
        actorEmail: user.email,
        targetType: "admin_endpoint",
        details: { requested_action: String(attemptedBody?.action || "unknown"), requester_role: role || "none" }
      });
      console.error(
        "Forbidden user attempted access:",
        user.email,
        "role:",
        role,
      );

      return jsonResponse(
        {
          error: "Forbidden",
        },
        403,
      );
    }

    // Create a privileged server-side client
    const adminClient = createClient(
      SUPABASE_URL,
      SERVICE_ROLE_KEY,
      {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const body = await req.json();
    const action = body?.action;

    console.log("Requested action:", action);

    if (action === "book-access") {
      const bookId = String(body?.bookId || "").trim();
      if (!bookId) return jsonResponse({ error: "A book ID is required." }, 400);

      let normalUsers;
      try {
        normalUsers = await listAllNormalUsers(adminClient);
      } catch (error) {
        logBookAccessFailure("list normal Auth users", "auth.users", error);
        return jsonResponse({ error: "Unable to load user access information." }, 500);
      }

      const { data: book, error: bookError } = await adminClient
        .from("books")
        .select("id, title, is_locked")
        .eq("id", bookId)
        .maybeSingle();
      if (bookError) {
        logBookAccessFailure("read selected book", "books", bookError);
        return jsonResponse({ error: "Unable to load user access information." }, 500);
      }
      if (!book) {
        return jsonResponse({ error: "Unable to load user access information." }, 404);
      }

      const [purchaseResult, overrideResult] = await Promise.allSettled([
        listAllRowsForBook(adminClient, "book_purchases", "user_id", bookId),
        listAllRowsForBook(adminClient, "user_book_access", "user_id, access_status", bookId)
      ]);
      if (purchaseResult.status === "rejected") {
        logBookAccessFailure("read purchases for selected book", "book_purchases", purchaseResult.reason);
        return jsonResponse({ error: "Unable to load user access information." }, 500);
      }
      if (overrideResult.status === "rejected") {
        logBookAccessFailure("read overrides for selected book", "user_book_access", overrideResult.reason);
        return jsonResponse({ error: "Unable to load user access information." }, 500);
      }
      const purchases = purchaseResult.value;
      const overrides = overrideResult.value;

      return jsonResponse({
        book: { id: book.id, title: book.title, is_locked: Boolean(book.is_locked) },
        users: normalUsers.map(normalizeUser),
        purchasedUserIds: (purchases || []).map((purchase: any) => purchase.user_id),
        accessOverrides: (overrides || []).map((override: any) => ({
          user_id: override.user_id,
          access_status: override.access_status
        }))
      });
    }

    if (action === "set-book-access") {
      const bookId = String(body?.bookId || "").trim();
      const userId = String(body?.userId || "").trim();
      const accessStatus = String(body?.accessStatus || "").trim().toLowerCase();

      if (!bookId || !userId || !["free", "locked"].includes(accessStatus)) {
        return jsonResponse({ error: "A book, user, and valid access status are required." }, 400);
      }

      const [{ data: targetData, error: targetError }, { data: book, error: bookError }] = await Promise.all([
        adminClient.auth.admin.getUserById(userId),
        adminClient.from("books").select("id, title").eq("id", bookId).maybeSingle()
      ]);
      const targetUser = targetData?.user;
      const targetRole = getRole(targetUser) || "user";
      if (targetError || !targetUser || targetRole !== "user") {
        return jsonResponse({ error: "Unable to update user access." }, 404);
      }
      if (bookError || !book) {
        return jsonResponse({ error: "Unable to update user access." }, 404);
      }

      const { data: purchase, error: purchaseError } = await adminClient
        .from("book_purchases")
        .select("id")
        .eq("user_id", userId)
        .eq("book_id", bookId)
        .maybeSingle();
      if (purchaseError) {
        return jsonResponse({ error: "Unable to update user access." }, 500);
      }
      if (purchase) {
        return jsonResponse({ error: "Verified purchases cannot be changed here." }, 409);
      }

      const { error: updateError } = await adminClient
        .from("user_book_access")
        .upsert({
          user_id: userId,
          book_id: bookId,
          access_status: accessStatus,
          granted_by: user.id,
          updated_at: new Date().toISOString()
        }, { onConflict: "user_id,book_id" });

      if (updateError) {
        console.error("Unable to update per-user book access.", { code: updateError.code || "ACCESS_UPDATE_FAILED" });
        return jsonResponse({ error: "Unable to update user access." }, 500);
      }

      await insertAdminAuditLog(adminClient, {
        action: "book_user_access_updated",
        actorEmail: user.email,
        targetType: "book",
        targetId: bookId,
        targetName: book.title,
        details: {
          user_name: targetUser.user_metadata?.full_name || targetUser.email || "User",
          user_email: targetUser.email || null,
          status: accessStatus === "free" ? "Free" : "Locked"
        }
      });

      return jsonResponse({ accessStatus });
    }

    if (action === "game-access") {
      const gameId = String(body?.gameId || "").trim();
      if (!gameId) return jsonResponse({ error: "A game ID is required." }, 400);

      let normalUsers;
      try {
        normalUsers = await listAllNormalUsers(adminClient);
      } catch (error) {
        logGameAccessFailure("list normal Auth users", "auth.users", error);
        return jsonResponse({ error: "Unable to load game user access information." }, 500);
      }

      const { data: game, error: gameError } = await adminClient
        .from("games")
        .select("id,title,is_locked")
        .eq("id", gameId)
        .maybeSingle();
      if (gameError) {
        logGameAccessFailure("read selected game", "games", gameError);
        return jsonResponse({ error: "Unable to load game user access information." }, 500);
      }
      if (!game) {
        return jsonResponse({ error: "Unable to load game user access information." }, 404);
      }

      let overrides;
      try {
        overrides = await listAllRowsForGame(adminClient, "user_id, access_status", gameId);
      } catch (error) {
        logGameAccessFailure("read overrides for selected game", "user_game_access", error);
        return jsonResponse({ error: "Unable to load game user access information." }, 500);
      }

      return jsonResponse({
        game: { id: game.id, title: game.title, is_locked: Boolean(game.is_locked) },
        users: normalUsers.map(normalizeUser),
        accessOverrides: (overrides || []).map((override: any) => ({
          user_id: override.user_id,
          access_status: override.access_status
        }))
      });
    }

    if (action === "set-game-access") {
      const gameId = String(body?.gameId || "").trim();
      const userId = String(body?.userId || "").trim();
      const accessStatus = String(body?.accessStatus || "").trim().toLowerCase();

      if (!gameId || !userId || !["free", "locked"].includes(accessStatus)) {
        return jsonResponse({ error: "A game, user, and valid access status are required." }, 400);
      }

      const [{ data: targetData, error: targetError }, { data: game, error: gameError }] = await Promise.all([
        adminClient.auth.admin.getUserById(userId),
        adminClient.from("games").select("id, title").eq("id", gameId).maybeSingle()
      ]);
      const targetUser = targetData?.user;
      const targetRole = getRole(targetUser) || "user";
      if (targetError || !targetUser || targetRole !== "user") {
        return jsonResponse({ error: "Unable to update game user access." }, 404);
      }
      if (gameError || !game) {
        return jsonResponse({ error: "Unable to update game user access." }, 404);
      }

      const { error: updateError } = await adminClient
        .from("user_game_access")
        .upsert({
          user_id: userId,
          game_id: gameId,
          access_status: accessStatus,
          granted_by: user.id,
          updated_at: new Date().toISOString()
        }, { onConflict: "user_id,game_id" });

      if (updateError) {
        console.error("Unable to update per-user game access.", { code: updateError.code || "ACCESS_UPDATE_FAILED" });
        return jsonResponse({ error: "Unable to update game user access." }, 500);
      }

      await insertAdminAuditLog(adminClient, {
        action: "game_user_access_updated",
        actorEmail: user.email,
        targetType: "game",
        targetId: gameId,
        targetName: game.title,
        details: {
          user_name: targetUser.user_metadata?.full_name || targetUser.email || "User",
          user_email: targetUser.email || null,
          status: accessStatus === "free" ? "Free" : "Locked"
        }
      });

      return jsonResponse({ accessStatus });
    }

    // LIST NORMAL MOBILE USERS
    if (action === "list") {
      const { data, error } =
        await adminClient.auth.admin.listUsers();

      if (error) {
        console.error(
          "Failed to list users:",
          error.message,
        );

        return jsonResponse(
          {
            error: error.message,
          },
          500,
        );
      }

      // Only return normal mobile users.
      // Admin and super_admin accounts must not appear here.
      const normalUsers = (data?.users || [])
        .filter(
          (user: any) =>
            String(
              user?.app_metadata?.role || "user",
            )
              .trim()
              .toLowerCase() === "user",
        )
        .map(normalizeUser);

      console.log(
        "Successfully loaded users:",
        normalUsers.length,
      );

      return jsonResponse({
        users: normalUsers,
      });
    }

    // CREATE A NORMAL MOBILE USER
    if (action === "create-user") {
      const fullName = String(body?.full_name || "").trim();
      const email = String(body?.email || "").trim();
      const password = String(body?.password || "");

      if (!fullName) {
        console.error("Create-user validation failed: FULL_NAME_REQUIRED");
        return jsonResponse({ error: "FULL_NAME_REQUIRED" }, 400);
      }
      if (!/^[^\s@]+@gmail\.com$/i.test(email)) {
        console.error("Create-user validation failed: EMAIL_INVALID");
        return jsonResponse({ error: "EMAIL_INVALID" }, 400);
      }
      if (
        password.length < 8 ||
        password.length > 16 ||
        !/[^A-Za-z0-9]/.test(password)
      ) {
        console.error(
          "Create-user validation failed: PASSWORD_INVALID",
          {
            passwordLength: password.length,
            hasSpecialCharacter: /[^A-Za-z0-9]/.test(password),
          },
        );
        return jsonResponse({ error: "PASSWORD_INVALID" }, 400);
      }

      let createdUser: any;
      console.log("Creating normal user account for:", email);
      try {
        const { data, error } = await adminClient.auth.admin.createUser({
          email,
          password,
          email_confirm: false,
          user_metadata: {
            full_name: fullName,
          },
          app_metadata: {
            role: "user",
          },
        });

        if (error || !data?.user) {
          const message = String(error?.message || "").toLowerCase();
          await insertAdminAuditLog(adminClient, {
            action: "user_creation_failed",
            actorEmail: user.email,
            targetType: "user",
            targetName: fullName,
            details: { user_email: email, failure_code: error?.code || "USER_CREATE_FAILED" }
          });
          if (
            message.includes("already registered") ||
            message.includes("already exists") ||
            message.includes("already been registered")
          ) {
            return jsonResponse({ error: "EMAIL_ALREADY_EXISTS" }, 409);
          }
          if (message.includes("password") || message.includes("email")) {
            return jsonResponse({ error: message.includes("email") ? "EMAIL_INVALID" : "PASSWORD_INVALID" }, 400);
          }

          console.error("Failed to create normal user account.");
          return jsonResponse({ error: "USER_CREATE_FAILED" }, 500);
        }

        createdUser = data.user;
        console.log("Successfully created normal user:", createdUser.id);
      } catch {
        console.error("Failed to create normal user account.");
        return jsonResponse({ error: "USER_CREATE_FAILED" }, 500);
      }

      const emailClient = createClient(SUPABASE_URL, ANON_KEY, {
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      });
      let verificationError: { message: string } | null = null;
      console.log("Sending verification email for:", email);
      try {
        const { error } = await emailClient.auth.resend({
          type: "signup",
          email,
          options: {
            emailRedirectTo: "heartshapers://auth/callback",
          },
        });
        verificationError = error;
      } catch (error: unknown) {
        verificationError = {
          message: error instanceof Error ? error.message : "Unknown verification email error",
        };
      }

      if (verificationError) {
        console.error("Verification email failed:", verificationError.message);
        let cleanupFailed = false;
        try {
          const { error: deleteError } = await adminClient.auth.admin.deleteUser(createdUser.id);
          cleanupFailed = Boolean(deleteError);
        } catch {
          cleanupFailed = true;
        }
        if (cleanupFailed) {
          console.error("Failed to clean up user after verification email failure.");
        }
        await insertAdminAuditLog(adminClient, {
          action: "user_creation_failed",
          actorEmail: user.email,
          targetType: "user",
          targetId: createdUser.id,
          targetName: fullName,
          details: { failure_code: "VERIFICATION_EMAIL_FAILED", cleanup_failed: cleanupFailed }
        });
        return jsonResponse({ error: "VERIFICATION_EMAIL_FAILED" }, 500);
      }

      await insertAdminAuditLog(adminClient, {
        action: "user_created",
        actorEmail: user.email,
        targetType: "user",
        targetId: createdUser.id,
        targetName: fullName,
        details: { user_email: email }
      });
      return jsonResponse({ user: normalizeUser(createdUser) }, 201);
    }

    // ENABLE OR DISABLE A USER
    if (action === "update-status") {
      const userId = body?.userId;
      const disabled = Boolean(body?.disabled);

      if (!userId) {
        return jsonResponse(
          {
            error: "A user ID is required",
          },
          400,
        );
      }

      const { data, error } =
        await adminClient.auth.admin.updateUserById(
          userId,
          {
            ban_duration: disabled
              ? "876000h"
              : "none",
          },
        );

      if (error || !data?.user) {
        await insertAdminAuditLog(adminClient, {
          action: "user_status_change_failed",
          actorEmail: user.email,
          targetType: "user",
          targetId: userId,
          details: { requested_status: disabled ? "disabled" : "enabled", failure_code: error?.code || "STATUS_UPDATE_FAILED" }
        });
        console.error(
          "Failed to update user:",
          error?.message,
        );

        return jsonResponse(
          {
            error:
              error?.message ||
              "Unable to update user",
          },
          500,
        );
      }

      console.log(
        "Successfully updated user status:",
        userId,
      );

      await insertAdminAuditLog(adminClient, {
        action: disabled ? "user_disabled" : "user_enabled",
        actorEmail: user.email,
        targetType: "user",
        targetId: userId,
        targetName: data.user.user_metadata?.full_name || data.user.email || null,
        details: { status: disabled ? "disabled" : "enabled" }
      });

      return jsonResponse({
        user: normalizeUser(data.user),
      });
    }

    // Unsupported action
    return jsonResponse(
      {
        error: "Unsupported action",
      },
      400,
    );
  } catch (error: unknown) {
    console.error(
      "Unexpected function error:",
      error,
    );

    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : "Unexpected server error",
      },
      500,
    );
  }
});