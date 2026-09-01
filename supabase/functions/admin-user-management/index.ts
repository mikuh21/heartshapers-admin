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