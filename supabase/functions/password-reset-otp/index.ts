/// <reference lib="deno.ns" />
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const CODE_TTL_MINUTES = 10;
const TOKEN_TTL_MINUTES = 10;
const COOLDOWN_SECONDS = 60;
const MAX_ATTEMPTS = 5;

function respond(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c] || c));
}
function hex(bytes: Uint8Array): string { return Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join(""); }
async function digest(value: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value))));
}
function equalConstantTime(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}
function makeCode(): string {
  const limit = Math.floor(0x100000000 / 100000) * 100000;
  while (true) {
    const n = new Uint32Array(1); crypto.getRandomValues(n);
    if (n[0] < limit) return String(n[0] % 100000).padStart(5, "0");
  }
}
function makeToken(): string { const b = new Uint8Array(32); crypto.getRandomValues(b); return hex(b); }
function validEmail(v: string): boolean { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v); }
function validPassword(v: string): boolean { return v.length >= 8 && v.length <= 16 && /[^A-Za-z0-9]/.test(v); }

function emailHtml(code: string, email: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Password reset | Heartshapers</title></head>
<body style="margin:0;padding:0;background:#f4f5f7;font-family:Arial,Helvetica,sans-serif;color:#252525">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">Your Heartshapers password-reset code is ${code}. It expires in 10 minutes.</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f4f5f7;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#fff;border:1px solid #e7e7e7;border-radius:14px;overflow:hidden">
<tr><td style="background:#ff3131;padding:26px 32px"><div style="font-size:12px;font-weight:bold;letter-spacing:2px;color:#ffe7e7;text-transform:uppercase">HEARTSHAPERS</div><div style="font-size:26px;line-height:1.25;font-weight:bold;color:#fff;margin-top:10px">Reset your password</div><div style="font-size:14px;line-height:1.6;color:#fff0f0;margin-top:7px">Use this verification code to securely reset your password.</div></td></tr>
<tr><td style="padding:28px 32px 12px"><p style="font-size:15px;line-height:1.7;color:#444;margin:0 0 12px">Hello,</p>
<p style="font-size:15px;line-height:1.7;color:#555;margin:0 0 20px">We received a request to reset the password for the Heartshapers account associated with <strong>${escapeHtml(email)}</strong>.</p>
<div style="font-size:12px;font-weight:bold;letter-spacing:1px;color:#777;text-transform:uppercase;text-align:center;margin:0 0 10px">Your 5-digit verification code</div>
<div style="background:#fff5f4;border:1px solid #ffe0dd;border-radius:12px;padding:22px 12px;text-align:center"><div style="font-size:36px;line-height:1.2;letter-spacing:10px;font-weight:bold;color:#d92d20;padding-left:10px">${code}</div></div>
<p style="font-size:14px;line-height:1.7;color:#555;margin:18px 0 0">This code expires in <strong>10 minutes</strong>. Enter it in the Heartshapers app to continue.</p>
<div style="margin-top:18px;padding:14px 16px;border-radius:9px;background:#f7f7f8;border:1px solid #e9e9e9;color:#666;font-size:13px;line-height:1.65"><strong style="color:#333">Didn't request this?</strong><br>Ignore this email. Your password will not change unless the code is confirmed and a new password is saved.</div></td></tr>
<tr><td style="padding:22px 32px 28px;border-top:1px solid #eee"><div style="font-size:13px;line-height:1.7;color:#777">For your security, never share this code with anyone, including someone claiming to represent Heartshapers.</div><div style="font-size:12px;line-height:1.7;color:#999;margin-top:16px">© ${new Date().getFullYear()} Heartshapers. All rights reserved.</div></td></tr>
</table></td></tr></table></body></html>`;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return respond({ error: "Method not allowed." }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const pepper = Deno.env.get("OTP_PEPPER");
    if (!url || !serviceKey || !pepper) {
      console.error("Password reset function is missing required server configuration.");
      return respond({ error: "Password reset service is not configured." }, 503);
    }
    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json();
    const action = String(body?.action || "");

    if (action === "request-code") {
      const email = String(body?.email || "").trim().toLowerCase();
      if (!validEmail(email)) return respond({ error: "Enter a valid email address." }, 400);
      const host = Deno.env.get("SMTP_HOST");
      const port = Number(Deno.env.get("SMTP_PORT") || "587");
      const user = Deno.env.get("SMTP_USER");
      const password = Deno.env.get("SMTP_PASSWORD");
      const from = Deno.env.get("SMTP_FROM") || user;
      if (!host || !user || !password || !from) {
        console.error("Password reset email is missing SMTP configuration.");
        return respond({ error: "Email service is temporarily unavailable." }, 503);
      }
      const { data: previous, error: previousError } = await db.from("password_reset_codes").select("last_sent_at").eq("email", email).maybeSingle();
      if (previousError) {
        console.error("Rate-limit lookup failed:", previousError.message);
        return respond({ error: "Unable to process this request right now." }, 503);
      }
      if (previous?.last_sent_at) {
        const elapsed = (Date.now() - new Date(previous.last_sent_at).getTime()) / 1000;
        if (elapsed >= 0 && elapsed < COOLDOWN_SECONDS) return respond({ ok: true });
      }

      let matchedUser: any = null;
      for (let page = 1; page <= 50; page++) {
        const { data, error } = await db.auth.admin.listUsers({ page, perPage: 1000 });
        if (error) {
          console.error("Account lookup failed:", error.message);
          return respond({ error: "Unable to process this request right now." }, 503);
        }
        const users = data?.users || [];
        matchedUser = users.find((u: any) => String(u.email || "").toLowerCase() === email) || null;
        if (matchedUser || users.length < 1000) break;
      }
      // Return the same response for registered and unregistered addresses.
      if (!matchedUser) return respond({ ok: true });

      const code = makeCode();
      const now = new Date();
      const { error: saveError } = await db.from("password_reset_codes").upsert({
        email, user_id: matchedUser.id, code_hash: await digest(`${email}:${code}`, pepper),
        expires_at: new Date(now.getTime() + CODE_TTL_MINUTES * 60000).toISOString(),
        attempts: 0, verified_at: null, reset_token_hash: null, reset_token_expires_at: null,
        last_sent_at: now.toISOString(), updated_at: now.toISOString()
      }, { onConflict: "email" });
      if (saveError) {
        console.error("Could not store password reset code:", saveError.message);
        return respond({ error: "Unable to process this request right now." }, 503);
      }
      try {
        const transporter = nodemailer.createTransport({ host, port, secure: port === 465, auth: { user, pass: password }, requireTLS: port === 587 });
        await transporter.sendMail({
          from, to: email, subject: "Your Heartshapers password reset code",
          text: ["Heartshapers password reset", "", `Your five-digit verification code is: ${code}`, "This code expires in 10 minutes.", "", "If you did not request a password reset, ignore this email.", "Do not share this code with anyone."].join("\n"),
          html: emailHtml(code, email)
        });
      } catch (mailError) {
        console.error("Unable to send password reset email:", mailError);
      }
      return respond({ ok: true });
    }

    if (action === "verify-code") {
      const email = String(body?.email || "").trim().toLowerCase();
      const code = String(body?.code || "").trim();
      if (!validEmail(email) || !/^\\d{5}$/.test(code)) return respond({ error: "That code is invalid or has expired." }, 400);
      const { data: record, error } = await db.from("password_reset_codes")
        .select("email,user_id,code_hash,expires_at,attempts,verified_at").eq("email", email).maybeSingle();
      if (error) {
        console.error("Could not read password reset record:", error.message);
        return respond({ error: "Unable to verify the code right now." }, 503);
      }
      if (!record?.code_hash || record.verified_at || new Date(record.expires_at).getTime() <= Date.now() || Number(record.attempts) >= MAX_ATTEMPTS) {
        return respond({ error: "That code is invalid or has expired." }, 400);
      }
      const suppliedHash = await digest(`${email}:${code}`, pepper);
      if (!equalConstantTime(suppliedHash, record.code_hash)) {
        await db.from("password_reset_codes").update({ attempts: Math.min(MAX_ATTEMPTS, Number(record.attempts) + 1), updated_at: new Date().toISOString() }).eq("email", email).eq("code_hash", record.code_hash).is("verified_at", null);
        return respond({ error: "That code is invalid or has expired." }, 400);
      }
      const resetToken = makeToken();
      const tokenHash = await digest(`${email}:${resetToken}`, pepper);
      const now = new Date();
      const { data: claimed, error: claimError } = await db.from("password_reset_codes").update({
        code_hash: null, verified_at: now.toISOString(), reset_token_hash: tokenHash,
        reset_token_expires_at: new Date(now.getTime() + TOKEN_TTL_MINUTES * 60000).toISOString(), updated_at: now.toISOString()
      }).eq("email", email).eq("code_hash", record.code_hash).is("verified_at", null).select("email").maybeSingle();
      if (claimError || !claimed) return respond({ error: "That code is invalid or has expired." }, 400);
      return respond({ ok: true, resetToken });
    }

    if (action === "reset-password") {
      const email = String(body?.email || "").trim().toLowerCase();
      const token = String(body?.resetToken || "");
      const newPassword = String(body?.newPassword || "");
      if (!validEmail(email) || !token || !validPassword(newPassword)) {
        return respond({ error: "Use a valid reset session and a password of 8–16 characters with at least one special character." }, 400);
      }
      const { data: record, error } = await db.from("password_reset_codes").select("email,user_id,verified_at,reset_token_hash,reset_token_expires_at").eq("email", email).maybeSingle();
      if (error) {
        console.error("Could not read password reset token:", error.message);
        return respond({ error: "Unable to reset the password right now." }, 503);
      }
      if (!record?.verified_at || !record.reset_token_hash || !record.reset_token_expires_at || new Date(record.reset_token_expires_at).getTime() <= Date.now()) {
        return respond({ error: "This reset session is invalid or has expired. Please request a new code." }, 400);
      }
      const suppliedHash = await digest(`${email}:${token}`, pepper);
      if (!equalConstantTime(suppliedHash, record.reset_token_hash)) return respond({ error: "This reset session is invalid or has expired. Please request a new code." }, 400);

      // Atomically claim the single-use token before updating the account.
      const { data: claimed, error: claimError } = await db.from("password_reset_codes").update({
        reset_token_hash: null, reset_token_expires_at: null, updated_at: new Date().toISOString()
      }).eq("email", email).eq("reset_token_hash", record.reset_token_hash).not("verified_at", "is", null).select("user_id").maybeSingle();
      if (claimError || !claimed) return respond({ error: "This reset session is invalid or has already been used." }, 400);

      const { error: updateError } = await db.auth.admin.updateUserById(claimed.user_id, { password: newPassword });
      if (updateError) {
        console.error("Password update failed:", updateError.message);
        await db.from("password_reset_codes").delete().eq("email", email);
        return respond({ error: "We could not update your password. Please request a new code." }, 500);
      }
      await db.from("password_reset_codes").delete().eq("email", email);
      return respond({ ok: true });
    }

    return respond({ error: "Unsupported action." }, 400);
  } catch (error) {
    console.error("Unhandled password reset request:", error);
    return respond({ error: "Unable to process this request right now." }, 500);
  }
});
