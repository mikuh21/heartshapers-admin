/// <reference lib="deno.ns" />

import { createClient } from "npm:@supabase/supabase-js@2";
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
      html: `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Payment verified | Heartshapers</title></head>
<body style="margin:0;padding:0;background:#f4f5f7;font-family:Arial,Helvetica,sans-serif;color:#252525">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0">Payment verified successfully. ${items.length} item(s) approved for reference ${escapeHtml(referenceNumber)}.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f4f5f7;padding:32px 12px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:680px;background:#ffffff;border:1px solid #e7e7e7;border-radius:14px;overflow:hidden">
        <tr><td style="background:#ff3131;padding:26px 32px">
          <div style="font-size:12px;font-weight:bold;letter-spacing:2px;color:#ffe7e7;text-transform:uppercase">HEARTSHAPERS ADMIN</div>
          <div style="font-size:26px;line-height:1.25;font-weight:bold;color:#ffffff;margin-top:10px">Payment verified</div>
          <div style="font-size:14px;line-height:1.6;color:#fff0f0;margin-top:7px">The transaction has been approved and access has been granted.</div>
        </td></tr>
        <tr><td style="padding:28px 32px 12px">
          <div style="display:inline-block;background:#e9f8ef;color:#187344;border:1px solid #c7ecd5;border-radius:20px;padding:7px 12px;font-size:12px;font-weight:bold">✓ VERIFIED SUCCESSFULLY</div>
          <p style="font-size:15px;line-height:1.7;color:#555;margin:18px 0 22px">This is a confirmation that the payment review is complete. Keep this email for your transaction records.</p>
          <div style="font-size:17px;font-weight:bold;margin:0 0 12px;color:#222">Transaction details</div>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border:1px solid #e9e9e9;border-radius:9px;border-collapse:separate">
            <tr><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;color:#777;font-size:13px;width:36%">Reference number</td><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;font-size:14px;font-weight:bold;color:#222;word-break:break-word">${escapeHtml(referenceNumber)}</td></tr>
            <tr><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;color:#777;font-size:13px">Customer</td><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;font-size:14px;color:#222">${escapeHtml(customerName)}</td></tr>
            <tr><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;color:#777;font-size:13px">Customer email</td><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;font-size:14px;color:#222;word-break:break-word">${escapeHtml(customer.email || "Not available")}</td></tr>
            <tr><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;color:#777;font-size:13px">Reviewed by</td><td style="padding:13px 15px;border-bottom:1px solid #eeeeee;font-size:14px;color:#222;word-break:break-word">${escapeHtml(admin.email)}</td></tr>
            <tr><td style="padding:13px 15px;color:#777;font-size:13px">Verified on</td><td style="padding:13px 15px;font-size:14px;color:#222">${escapeHtml(dateLabel)} <span style="color:#777;font-size:12px">(Philippine Time)</span></td></tr>
          </table>
        </td></tr>
        <tr><td style="padding:18px 32px 8px">
          <div style="font-size:17px;font-weight:bold;color:#222;margin-bottom:12px">Approved items <span style="font-size:12px;font-weight:normal;color:#777">(${items.length})</span></div>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;width:100%">
            <thead><tr style="background:#f7f7f8"><th align="left" style="padding:12px 10px;font-size:11px;letter-spacing:.5px;text-transform:uppercase;color:#666;border-bottom:1px solid #e8e8e8">Type</th><th align="left" style="padding:12px 10px;font-size:11px;letter-spacing:.5px;text-transform:uppercase;color:#666;border-bottom:1px solid #e8e8e8">Item</th><th align="right" style="padding:12px 10px;font-size:11px;letter-spacing:.5px;text-transform:uppercase;color:#666;border-bottom:1px solid #e8e8e8;white-space:nowrap">Price</th></tr></thead>
            <tbody>${itemRows}</tbody>
          </table>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin-top:14px;background:#fff5f4;border:1px solid #ffe0dd;border-radius:9px">
            <tr><td style="padding:16px;color:#73312c;font-size:14px;font-weight:bold">TOTAL PAID</td><td align="right" style="padding:16px;color:#d92d20;font-size:22px;font-weight:bold;white-space:nowrap">${escapeHtml(peso(total))}</td></tr>
          </table>
        </td></tr>
        <tr><td style="padding:28px 32px 30px">
          <div style="border-top:1px solid #eeeeee;padding-top:18px;font-size:12px;line-height:1.7;color:#888">This is an automated notification from Heartshapers Admin.<br>Please do not reply directly to this email.</div>
        </td></tr>
      </table>
      <div style="max-width:680px;padding:16px 8px 0;font-size:11px;line-height:1.6;text-align:center;color:#999">© Heartshapers · Payment verification record</div>
    </td></tr>
  </table>
</body>
</html>`
    });

    return jsonResponse({ success: true, recipient: admin.email, item_count: items.length });
  } catch (error) {
    console.error("Payment verification email failed.", {
      error: error instanceof Error ? error.message : "Unknown error"
    });
    return jsonResponse({ error: "Unable to send the payment verification email." }, 500);
  }
});
