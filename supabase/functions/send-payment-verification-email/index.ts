/// <reference lib="deno.ns" />

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
import nodemailer from "npm:nodemailer@6.9.16";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[char] || char));
}

function peso(value: unknown): string {
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP"
  }).format(Number(value || 0));
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const smtpHost = Deno.env.get("SMTP_HOST");
    const smtpPort = Number(Deno.env.get("SMTP_PORT") || "587");
    const smtpUser = Deno.env.get("SMTP_USER");
    const smtpPassword = Deno.env.get("SMTP_PASSWORD");
    const smtpFrom = Deno.env.get("SMTP_FROM") || smtpUser;

    if (!supabaseUrl || !serviceRoleKey || !anonKey) {
      console.error("Payment email function is missing Supabase configuration.");
      return jsonResponse({ error: "Server configuration error" }, 500);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return jsonResponse({ error: "Unauthorized" }, 401);

    const token = authorization.replace(/^Bearer\s+/i, "");
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false }
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    const admin = authData.user;
    if (authError || !admin) return jsonResponse({ error: "Unauthorized" }, 401);

    const role = String(admin.app_metadata?.role || "").trim().toLowerCase();
    if (!["admin", "super_admin"].includes(role)) return jsonResponse({ error: "Forbidden" }, 403);
    if (!admin.email) return jsonResponse({ error: "The signed-in admin has no email address." }, 400);

    if (!smtpHost || !smtpUser || !smtpPassword || !smtpFrom) {
      console.error("Payment email function is missing SMTP configuration.");
      return jsonResponse({ error: "Email service is not configured on the server." }, 503);
    }

    const body = await req.json();
    const userId = String(body?.user_id || "").trim();
    const referenceNumber = String(body?.reference_number || "").trim();
    const proofImageUrl = String(body?.proof_image_url || "").trim();
    if (!userId || !referenceNumber || !proofImageUrl) {
      return jsonResponse({ error: "Missing payment transaction details." }, 400);
    }

    const db = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const [customerResult, booksResult, gamesResult] = await Promise.all([
      db.auth.admin.getUserById(userId),
      db.from("payment_submissions")
        .select("id, amount, reviewed_at, status, reference_number, proof_image_url, books(title, price)")
        .eq("user_id", userId).eq("reference_number", referenceNumber)
        .eq("proof_image_url", proofImageUrl).eq("status", "verified"),
      db.from("game_payment_submissions")
        .select("id, amount, reviewed_at, status, reference_number, proof_image_url, games(title, price)")
        .eq("user_id", userId).eq("reference_number", referenceNumber)
        .eq("proof_image_url", proofImageUrl).eq("status", "verified")
    ]);

    if (customerResult.error || !customerResult.data.user) {
      return jsonResponse({ error: "Unable to load customer details." }, 500);
    }
    if (booksResult.error || gamesResult.error) {
      console.error("Unable to load verified payment items.", {
        booksCode: booksResult.error?.code || null,
        gamesCode: gamesResult.error?.code || null
      });
      return jsonResponse({ error: "Unable to load verified payment items." }, 500);
    }

    const bookRows = booksResult.data || [];
    const gameRows = gamesResult.data || [];
    const allRows = [...bookRows, ...gameRows];
    if (!allRows.length) return jsonResponse({ error: "No verified items were found for this transaction." }, 409);

    const customer = customerResult.data.user;
    const customerName = customer.user_metadata?.full_name || customer.user_metadata?.fullName || customer.email || "Customer";
    const items = [
      ...bookRows.map((row: any) => ({
        type: "Book",
        title: row.books?.title || "Unknown book",
        price: Number(row.amount ?? row.books?.price ?? 0),
        reviewedAt: row.reviewed_at
      })),
      ...gameRows.map((row: any) => ({
        type: "Game",
        title: row.games?.title || "Unknown game",
        price: Number(row.amount ?? row.games?.price ?? 0),
        reviewedAt: row.reviewed_at
      }))
    ];
    const total = items.reduce((sum, item) => sum + item.price, 0);
    const reviewedAt = items.map((item) => item.reviewedAt).filter(Boolean).sort().at(-1) || new Date().toISOString();
    const dateLabel = new Date(reviewedAt).toLocaleString("en-PH", { timeZone: "Asia/Manila", dateStyle: "medium", timeStyle: "short" });
    const itemRows = items.map((item) =>
      `<tr><td style="padding:10px;border-bottom:1px solid #eee">${escapeHtml(item.type)}</td><td style="padding:10px;border-bottom:1px solid #eee">${escapeHtml(item.title)}</td><td style="padding:10px;border-bottom:1px solid #eee;text-align:right">${escapeHtml(peso(item.price))}</td></tr>`
    ).join("");

    const transporter = nodemailer.createTransport({
      host: smtpHost,
      port: smtpPort,
      secure: smtpPort === 465,
      auth: { user: smtpUser, pass: smtpPassword },
      requireTLS: smtpPort === 587
    });

    await transporter.sendMail({
      from: smtpFrom,
      to: admin.email,
      subject: `Heartshapers payment verified — Ref ${referenceNumber}`,
      text: [
        "Heartshapers payment verification notification",
        "",
        `Reviewed by: ${admin.email}`,
        `Customer: ${customerName}`,
        `Customer email: ${customer.email || "Not available"}`,
        `Reference number: ${referenceNumber}`,
        `Verified on: ${dateLabel} (Philippine Time)`,
        "",
        "Approved items:",
        ...items.map((item) => `- ${item.type}: ${item.title} — ${peso(item.price)}`),
        "",
        `Total paid: ${peso(total)}`,
        "",
        "Access has been granted for all verified items in this transaction."
      ].join("\n"),
      html: `<div style="font-family:Arial,sans-serif;color:#222;max-width:680px;margin:auto"><h2 style="color:#ff3131">Heartshapers Payment Verified</h2><p>The transaction has been verified and access has been granted to all listed items.</p><table style="border-collapse:collapse;width:100%;margin:20px 0"><tbody><tr><th style="padding:8px;text-align:left;width:180px">Reviewed by</th><td style="padding:8px">${escapeHtml(admin.email)}</td></tr><tr><th style="padding:8px;text-align:left">Customer</th><td style="padding:8px">${escapeHtml(customerName)}</td></tr><tr><th style="padding:8px;text-align:left">Customer email</th><td style="padding:8px">${escapeHtml(customer.email || "Not available")}</td></tr><tr><th style="padding:8px;text-align:left">Reference number</th><td style="padding:8px">${escapeHtml(referenceNumber)}</td></tr><tr><th style="padding:8px;text-align:left">Verified on</th><td style="padding:8px">${escapeHtml(dateLabel)} (Philippine Time)</td></tr></tbody></table><h3>Approved items</h3><table style="border-collapse:collapse;width:100%"><thead><tr><th style="padding:10px;text-align:left;background:#f6f6f6">Type</th><th style="padding:10px;text-align:left;background:#f6f6f6">Item</th><th style="padding:10px;text-align:right;background:#f6f6f6">Price</th></tr></thead><tbody>${itemRows}</tbody><tfoot><tr><th colspan="2" style="padding:12px;text-align:right">Total paid</th><th style="padding:12px;text-align:right">${escapeHtml(peso(total))}</th></tr></tfoot></table><p style="margin-top:24px;color:#555">This notification was sent automatically by Heartshapers Admin.</p></div>`
    });

    return jsonResponse({ success: true, recipient: admin.email, item_count: items.length });
  } catch (error) {
    console.error("Payment verification email failed.", {
      error: error instanceof Error ? error.message : "Unknown error"
    });
    return jsonResponse({ error: "Unable to send the payment verification email." }, 500);
  }
});
