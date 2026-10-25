/// <reference lib="deno.ns" />
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const CODE_TTL_MINUTES = 10;
const COOLDOWN_SECONDS = 60;
const MAX_ATTEMPTS = 5;

function respond(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] || c)
  );
}
function hex(bytes: Uint8Array): string {
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}
async function digest(value: string, pepper: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
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
    const n = new Uint32Array(1);
    crypto.getRandomValues(n);
    if (n[0] < limit) return String(n[0] % 100000).padStart(5, "0");
  }
}
function validEmail(v: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
}

function emailHtml(code: string, email: string, fullName: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Verify your account | Heartshapers</title></head>
<body style="margin:0;padding:0;background:#f4f5f7;font-family:Arial,Helvetica,sans-serif;color:#252525">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">Your Heartshapers account-verification code is ${code}. It expires in 10 minutes.</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f4f5f7;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#fff;border:1px solid #e7e7e7;border-radius:14px;overflow:hidden">
<tr><td style="background:#ff3131;padding:26px 32px"><div style="font-size:12px;font-weight:bold;letter-spacing:2px;color:#ffe7e7;text-transform:uppercase">HEARTSHAPERS</div><div style="font-size:26px;line-height:1.25;font-weight:bold;color:#fff;margin-top:10px">Verify your account</div><div style="font-size:14px;line-height:1.6;color:#fff0f0;margin-top:7px">Use this verification code to confirm your email address and activate your account.</div></td></tr>
<tr><td style="padding:28px 32px 12px"><p style="font-size:15px;line-height:1.7;color:#444;margin:0 0 12px">Hello ${escapeHtml(fullName || "there")},</p>
<p style="font-size:15px;line-height:1.7;color:#555;margin:0 0 20px">Thanks for creating a Heartshapers account with <strong>${escapeHtml(email)}</strong>. Enter this code in the Heartshapers app to verify that this email address belongs to you.</p>
<div style="font-size:12px;font-weight:bold;letter-spacing:1px;color:#777;text-transform:uppercase;text-align:center;margin:0 0 10px">Your 5-digit verification code</div>
<div style="background:#fff5f4;border:1px solid #ffe0dd;border-radius:12px;padding:22px 12px;text-align:center"><div style="font-size:36px;line-height:1.2;letter-spacing:10px;font-weight:bold;color:#d92d20;padding-left:10px">${code}</div></div>
<p style="font-size:14px;line-height:1.7;color:#555;margin:18px 0 0">This code expires in <strong>10 minutes</strong>. Enter it in the Heartshapers app to finish verifying your account.</p>
<div style="margin-top:18px;padding:14px 16px;border-radius:9px;background:#f7f7f8;border:1px solid #e9e9e9;color:#666;font-size:13px;line-height:1.65"><strong style="color:#333">Didn't create this account?</strong><br>You can safely ignore this email. Do not share this code with anyone.</div></td></tr>
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
    const host = Deno.env.get("SMTP_HOST");
    const port = Number(Deno.env.get("SMTP_PORT") || "587");
    const smtpUser = Deno.env.get("SMTP_USER");
    const smtpPassword = Deno.env.get("SMTP_PASSWORD");
    const from = Deno.env.get("SMTP_FROM") || smtpUser;

    if (!url || !serviceKey || !pepper) {
      console.error("Account verification function is missing required server configuration.");
      return respond({ error: "Account verification service is not configured." }, 503);
    }
    const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json();
    const action = String(body?.action || "");
    const email = String(body?.email || "").trim().toLowerCase();

    if (!validEmail(email)) return respond({ error: "Enter a valid email address." }, 400);
    if (!host || !smtpUser || !smtpPassword || !from) {
      console.error("Account verification email is missing SMTP configuration.");
      return respond({ error: "Email service is temporarily unavailable." }, 503);
    }

    const sendCode = async (userId: string, fullName: string): Promise<Response> => {
      const { data: previous, error: previousError } = await db
        .from("account_verification_codes")
        .select("last_sent_at,verified_at")
        .eq("email", email)
        .maybeSingle();
      if (previousError) {
        console.error("Account verification rate-limit lookup failed:", previousError.message);
        return respond({ error: "Unable to process this request right now." }, 503);
      }
      if (previous?.verified_at) return respond({ error: "This account has already been verified. Please log in." }, 400);
      if (previous?.last_sent_at) {
        const elapsed = (Date.now() - new Date(previous.last_sent_at).getTime()) / 1000;
        if (elapsed >= 0 && elapsed < COOLDOWN_SECONDS) {
          return respond({ error: "Please wait a minute before requesting another code." }, 429);
        }
      }

      const code = makeCode();
      const now = new Date();
      const { error: saveError } = await db.from("account_verification_codes").upsert({
        email,
        user_id: userId,
        code_hash: await digest(`${email}:${code}`, pepper),
        expires_at: new Date(now.getTime() + CODE_TTL_MINUTES * 60000).toISOString(),
        attempts: 0,
        verified_at: null,
        last_sent_at: now.toISOString(),
        updated_at: now.toISOString(),
      }, { onConflict: "email" });
      if (saveError) {
        console.error("Could not store account verification code:", saveError.message);
        return respond({ error: "Unable to process this request right now." }, 503);
      }

      try {
        const transporter = nodemailer.createTransport({
          host, port, secure: port === 465, auth: { user: smtpUser, pass: smtpPassword },
          ...(port === 587 ? { requireTLS: true } : {}),
        });
        await transporter.sendMail({
          from,
          to: email,
          subject: "Your Heartshapers account verification code",
          text: [
            "Heartshapers account verification",
            "",
            `Hello ${fullName || "there"},`,
            `Your five-digit verification code is: ${code}`,
            "This code expires in 10 minutes.",
            "",
            "If you did not create a Heartshapers account, ignore this email.",
            "Do not share this code with anyone.",
          ].join("\n"),
          html: emailHtml(code, email, fullName),
        });
      } catch (mailError) {
        console.error("Unable to send account verification email:", mailError);
        return respond({ error: "We could not send the verification email. Please use Resend Code in a minute." }, 503);
      }
      return respond({ ok: true });
    };

    if (action === "register") {
      const password = String(body?.password || "");
      const fullName = String(body?.fullName || "").trim();
      if (!fullName || password.length < 8 || password.length > 16 || !/[^A-Za-z0-9]/.test(password)) {
        return respond({ error: "Enter your name and a password of 8–16 characters with at least one special character." }, 400);
      }

      const { data: created, error: createError } = await db.auth.admin.createUser({
        email,
        password,
        email_confirm: false,
        user_metadata: { full_name: fullName },
      });
      if (createError || !created?.user) {
        const msg = String(createError?.message || "").toLowerCase();
        if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
          return respond({ error: "This email is already registered." }, 409);
        }
        console.error("Account creation failed:", createError?.message || "No user returned");
        return respond({ error: "We could not create your account. Please try again." }, 400);
      }
      const sendResponse = await sendCode(created.user.id, fullName);
      if (!sendResponse.ok) {
        // Avoid leaving a stranded unverified account if the first email cannot be sent.
        await db.from("account_verification_codes").delete().eq("email", email);
        await db.auth.admin.deleteUser(created.user.id);
      }
      return sendResponse;
    }

    if (action === "resend-code") {
      let user: any = null;
      for (let page = 1; page <= 50; page++) {
        const { data, error: usersError } = await db.auth.admin.listUsers({ page, perPage: 1000 });
        if (usersError) {
          console.error("Account lookup failed:", usersError.message);
          return respond({ error: "Unable to process this request right now." }, 503);
        }
        const users = data?.users || [];
        user = users.find((u: any) => String(u.email || "").toLowerCase() === email) || null;
        if (user || users.length < 1000) break;
      }
      if (!user || user.email_confirmed_at) {
        return respond({ error: "This account cannot be verified with a new code. Please try logging in or sign up again." }, 400);
      }
      const fullName = String(user.user_metadata?.full_name || "");
      return await sendCode(user.id, fullName);
    }

    if (action === "verify-code") {
      const code = String(body?.code || "").trim();
      if (!/^\d{5}$/.test(code)) return respond({ error: "That code is invalid or has expired." }, 400);

      const { data: record, error: readError } = await db.from("account_verification_codes")
        .select("email,user_id,code_hash,expires_at,attempts,verified_at")
        .eq("email", email).maybeSingle();
      if (readError) {
        console.error("Could not read account verification record:", readError.message);
        return respond({ error: "Unable to verify the code right now." }, 503);
      }
      if (!record?.code_hash || record.verified_at || !record.expires_at ||
          new Date(record.expires_at).getTime() <= Date.now() || Number(record.attempts) >= MAX_ATTEMPTS) {
        return respond({ error: "That code is invalid or has expired." }, 400);
      }
      const suppliedHash = await digest(`${email}:${code}`, pepper);
      if (!equalConstantTime(suppliedHash, record.code_hash)) {
        await db.from("account_verification_codes")
          .update({ attempts: Math.min(MAX_ATTEMPTS, Number(record.attempts) + 1), updated_at: new Date().toISOString() })
          .eq("email", email).eq("code_hash", record.code_hash).is("verified_at", null);
        return respond({ error: "That code is invalid or has expired." }, 400);
      }

      const now = new Date().toISOString();
      const { data: claimed, error: claimError } = await db.from("account_verification_codes")
        .update({ code_hash: null, expires_at: null, updated_at: now })
        .eq("email", email).eq("code_hash", record.code_hash).is("verified_at", null)
        .select("user_id").maybeSingle();
      if (claimError || !claimed) return respond({ error: "That code is invalid or has already been used." }, 400);

      const { error: confirmError } = await db.auth.admin.updateUserById(claimed.user_id, { email_confirm: true });
      if (confirmError) {
        console.error("Could not confirm account email:", confirmError.message);
        return respond({ error: "The code could not activate your account. Please request a new code in a minute and try again." }, 503);
      }
      const { error: markVerifiedError } = await db.from("account_verification_codes")
        .update({ verified_at: now, updated_at: now })
        .eq("email", email).eq("user_id", claimed.user_id).is("verified_at", null);
      if (markVerifiedError) {
        console.error("Could not mark account verification record as complete:", markVerifiedError.message);
      }
      return respond({ ok: true });
    }

    return respond({ error: "Unsupported action." }, 400);
  } catch (error) {
    console.error("Unhandled account verification request:", error);
    return respond({ error: "Unable to process this request right now." }, 500);
  }
});
