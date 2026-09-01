/// <reference lib="deno.ns" />

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}

function getTrustedRole(user: any): string | null {
  const metadata = user?.app_metadata || {};
  const role = metadata.role;
  if (!role) return null;
  return String(role).trim().toLowerCase();
}

function normalizeUser(user: any) {
  const metadata = user?.user_metadata || {};

  return {
    id: user?.id,
    email: user?.email || "",
    full_name: metadata?.full_name || metadata?.fullName || metadata?.name || "",
    created_at: user?.created_at || null,
    email_verified: Boolean(user?.email_confirmed_at || user?.confirmed_at),
    disabled: Boolean(user?.banned_until)
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
      console.error("Missing required Supabase environment variables");
      return jsonResponse({ error: "Server configuration error" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      console.error("Missing/invalid Authorization header");
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: {
        headers: {
          Authorization: `Bearer ${jwt}`
        }
      }
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();

    if (userError || !userData.user) {
      console.error("Unable to authenticate requester:", userError?.message);
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const requesterRole = getTrustedRole(userData.user);
    console.log("Authenticated requester:", userData.user.email, "role:", requesterRole);

    if (requesterRole !== "super_admin") {
      console.error("Forbidden requester attempted admin management:", userData.user.email, "role:", requesterRole);
      return jsonResponse({ error: "You do not have permission to perform this action." }, 403);
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
        console.error("Failed to list admin users:", error.message);
        return jsonResponse({ error: "Unable to load administrator accounts." }, 500);
      }

      const admins = (data?.users || []).filter((user: any) => {
        const role = String(user?.app_metadata?.role || "").trim().toLowerCase();
        return role === "admin";
      }).map(normalizeUser);

      return jsonResponse({ admins });
    }

    if (action === "create") {
      const full_name = String(body?.full_name || "").trim();
      const email = String(body?.email || "").trim();
      const password = String(body?.password || "");

      if (!full_name) return jsonResponse({ error: "Full Name is required." }, 400);
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return jsonResponse({ error: "Enter a valid email address." }, 400);
      if (!password || password.length < 8 || password.length > 16 || !/[^A-Za-z0-9]/.test(password)) {
        return jsonResponse({ error: "Password must be 8-16 characters and include at least one special character." }, 400);
      }

      const { data: existingUsers, error: existingError } = await adminClient.auth.admin.listUsers();
      if (existingError) {
        console.error("Unable to check duplicate admin email:", existingError.message);
        return jsonResponse({ error: "Unable to create the administrator account. Please try again." }, 500);
      }

      const duplicateEmail = (existingUsers?.users || []).some((user: any) => user.email?.toLowerCase() === email.toLowerCase());
      if (duplicateEmail) {
        return jsonResponse({ error: "An account with this email already exists." }, 409);
      }

      const { data, error } = await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name
        },
        app_metadata: {
          role: "admin"
        }
      });

      if (error || !data?.user) {
        console.error("Failed to create admin user:", error?.message);
        return jsonResponse({ error: "Unable to create the administrator account. Please try again." }, 500);
      }

      return jsonResponse({ admin: normalizeUser(data.user) }, 201);
    }

    if (action === "update-status") {
      const userId = body?.userId;
      const disabled = Boolean(body?.disabled);

      if (!userId) {
        return jsonResponse({ error: "A user ID is required." }, 400);
      }

      const { data: existingUserData, error: existingUserError } = await adminClient.auth.admin.getUserById(userId);
      if (existingUserError || !existingUserData?.user) {
        console.error("Unable to find target admin user:", existingUserError?.message);
        return jsonResponse({ error: "Unable to find that administrator account." }, 404);
      }

      const targetRole = getTrustedRole(existingUserData.user);
      if (targetRole !== "admin") {
        return jsonResponse({ error: "Only admin accounts can be managed here." }, 403);
      }

      const { data, error } = await adminClient.auth.admin.updateUserById(userId, {
        ban_duration: disabled ? "876000h" : "none"
      });

      if (error || !data?.user) {
        console.error("Failed to update admin status:", error?.message);
        return jsonResponse({ error: "Unable to update this administrator account right now." }, 500);
      }

      return jsonResponse({ admin: normalizeUser(data.user) });
    }

    return jsonResponse({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("Unhandled admin management error:", error);
    return jsonResponse({ error: "Unable to process this request. Please try again." }, 500);
  }
});
