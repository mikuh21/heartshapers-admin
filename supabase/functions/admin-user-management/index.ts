import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
  throw new Error("Missing Supabase environment variables");
}

function isAdminIdentity(user: any) {
  const appMetadata = user?.app_metadata || {};
  const userMetadata = user?.user_metadata || {};

  const values = [
    appMetadata.role,
    appMetadata.is_admin,
    appMetadata.isAdmin,
    appMetadata.admin,
    userMetadata.role,
    userMetadata.is_admin,
    userMetadata.isAdmin,
    userMetadata.admin
  ];

  return values.some((value) => {
    if (typeof value === "boolean") return value;
    if (typeof value === "string") return value.toLowerCase() === "admin";
    return false;
  });
}

function normalizeUser(user: any) {
  const appMetadata = user?.app_metadata || {};
  const userMetadata = user?.user_metadata || {};

  return {
    id: user?.id,
    email: user?.email || "",
    full_name:
      userMetadata?.full_name ||
      userMetadata?.fullName ||
      appMetadata?.full_name ||
      appMetadata?.fullName ||
      user?.user_metadata?.name ||
      "",
    created_at: user?.created_at || null,
    email_verified: Boolean(
      user?.email_confirmed_at ||
        user?.confirmed_at ||
        appMetadata?.email_verified ||
        userMetadata?.email_verified
    ),
    disabled: Boolean(
      user?.banned_until ||
      appMetadata?.disabled ||
      appMetadata?.is_disabled ||
      userMetadata?.disabled ||
      userMetadata?.is_disabled
    )
  };
}

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    if (!jwt) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: {
        headers: {
          Authorization: `Bearer ${jwt}`
        }
      }
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }

    if (!isAdminIdentity(userData.user)) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" }
      });
    }

    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });

    const body = await req.json();
    const action = body?.action;

    if (action === "list") {
      const { data, error } = await adminClient.auth.admin.listUsers();
      if (error) {
        return new Response(JSON.stringify({ error: "Unable to load users" }), {
          status: 500,
          headers: { "Content-Type": "application/json" }
        });
      }

      return new Response(
        JSON.stringify({
          users: (data?.users || []).map(normalizeUser)
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    if (action === "update-status") {
      const userId = body?.userId;
      const disabled = Boolean(body?.disabled);

      if (!userId) {
        return new Response(JSON.stringify({ error: "A user is required" }), {
          status: 400,
          headers: { "Content-Type": "application/json" }
        });
      }

      const { data, error } = await adminClient.auth.admin.updateUserById(userId, {
        app_metadata: {
          is_disabled: disabled,
          disabled,
          updated_by_admin: true
        }
      });

      if (error || !data?.user) {
        return new Response(JSON.stringify({ error: "Unable to update user status" }), {
          status: 500,
          headers: { "Content-Type": "application/json" }
        });
      }

      return new Response(
        JSON.stringify({
          user: normalizeUser(data.user)
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ error: "Unsupported action" }), {
      status: 400,
      headers: { "Content-Type": "application/json" }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: "User management is unavailable right now." }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});
