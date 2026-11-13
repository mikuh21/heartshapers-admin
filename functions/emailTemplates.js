const BRAND_RED = "#ff3131";
const INK = "#252525";
const MUTED = "#666666";

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

function shell({ preheader, heading, subtitle, body, footerNote = "" }) {
  const year = new Date().getFullYear();
  return `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${escapeHtml(heading)} | Heartshapers</title></head>
<body style="margin:0;padding:0;background:#f4f5f7;font-family:Arial,Helvetica,sans-serif;color:${INK};">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${escapeHtml(preheader)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#f4f5f7;padding:32px 12px;">
<tr><td align="center">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#ffffff;border:1px solid #e7e7e7;border-radius:14px;overflow:hidden;">
<tr><td style="background:${BRAND_RED};padding:26px 32px;">
<div style="font-size:12px;font-weight:bold;letter-spacing:2px;color:#ffe7e7;text-transform:uppercase;">HEARTSHAPERS</div>
<div style="font-size:26px;line-height:1.25;font-weight:bold;color:#ffffff;margin-top:10px;">${escapeHtml(heading)}</div>
<div style="font-size:14px;line-height:1.6;color:#fff0f0;margin-top:7px;">${escapeHtml(subtitle)}</div>
</td></tr>
<tr><td style="padding:28px 32px 12px;">${body}</td></tr>
<tr><td style="padding:22px 32px 28px;border-top:1px solid #eeeeee;">
<div style="font-size:13px;line-height:1.7;color:#777777;">${footerNote || "Thank you for being part of the Heartshapers community."}</div>
<div style="font-size:12px;line-height:1.7;color:#999999;margin-top:16px;">© ${year} Heartshapers. All rights reserved.</div>
</td></tr>
</table>
</td></tr></table></body></html>`;
}

function actionButton(label, url) {
  return `<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin:24px auto 8px;"><tr><td align="center" bgcolor="${BRAND_RED}" style="border-radius:10px;">
<a href="${escapeHtml(url)}" target="_blank" style="display:inline-block;padding:14px 26px;font-size:15px;line-height:20px;font-weight:bold;color:#ffffff;text-decoration:none;border-radius:10px;">${escapeHtml(label)}</a>
</td></tr></table>`;
}

function detailPanel(label, value) {
  return `<div style="margin-top:18px;padding:16px 18px;border-radius:10px;background:#fff5f4;border:1px solid #ffe0dd;">
<div style="font-size:11px;font-weight:bold;letter-spacing:1px;text-transform:uppercase;color:#888888;">${escapeHtml(label)}</div>
<div style="font-size:16px;line-height:1.5;font-weight:bold;color:#d92d20;margin-top:6px;word-break:break-word;">${escapeHtml(value)}</div>
</div>`;
}

function verificationEmail({ name, email, link }) {
  const safeName = escapeHtml(name || "there");
  const safeEmail = escapeHtml(email);
  const body = `<p style="font-size:15px;line-height:1.7;color:#444444;margin:0 0 12px;">Hello ${safeName},</p>
<p style="font-size:15px;line-height:1.7;color:#555555;margin:0 0 12px;">Welcome to Heartshapers! Confirm your email address to activate your account and get started.</p>
${detailPanel("Account email", safeEmail)}
${actionButton("Verify email address", link)}
<p style="font-size:13px;line-height:1.7;color:#777777;margin:18px 0 0;">If the button does not work, copy and paste this link into your browser:<br><a href="${escapeHtml(link)}" style="color:#d92d20;word-break:break-all;">${escapeHtml(link)}</a></p>
<div style="margin-top:18px;padding:14px 16px;border-radius:9px;background:#f7f7f8;border:1px solid #e9e9e9;color:#666666;font-size:13px;line-height:1.65;"><strong style="color:#333333;">Didn't create this account?</strong><br>You can safely ignore this email.</div>`;
  return {
    subject: "Verify your Heartshapers account",
    html: shell({ preheader: "Confirm your email address to activate your Heartshapers account.", heading: "Welcome to Heartshapers", subtitle: "One quick step to activate your account.", body, footerNote: "For your security, do not forward verification links or share them with anyone." }),
    text: `Hello ${name || "there"},\n\nWelcome to Heartshapers! Verify your email address to activate your account: ${link}\n\nIf you did not create this account, you can ignore this email.`,
  };
}

function passwordResetEmail({ email, code }) {
  const body = `<p style="font-size:15px;line-height:1.7;color:#444444;margin:0 0 12px;">Hello,</p>
<p style="font-size:15px;line-height:1.7;color:#555555;margin:0 0 20px;">We received a request to reset the password for the Heartshapers account associated with <strong>${escapeHtml(email)}</strong>.</p>
<div style="font-size:12px;font-weight:bold;letter-spacing:1px;color:#777777;text-transform:uppercase;text-align:center;margin:0 0 10px;">Your 5-digit verification code</div>
<div style="background:#fff5f4;border:1px solid #ffe0dd;border-radius:12px;padding:22px 12px;text-align:center;"><div style="font-size:36px;line-height:1.2;letter-spacing:10px;font-weight:bold;color:#d92d20;padding-left:10px;">${escapeHtml(code)}</div></div>
<p style="font-size:14px;line-height:1.7;color:#555555;margin:18px 0 0;">This code expires in <strong>10 minutes</strong>. Enter it in the Heartshapers app to continue.</p>
<div style="margin-top:18px;padding:14px 16px;border-radius:9px;background:#f7f7f8;border:1px solid #e9e9e9;color:#666666;font-size:13px;line-height:1.65;"><strong style="color:#333333;">Didn't request this?</strong><br>Ignore this email. Your password will not change unless the code is confirmed and a new password is saved.</div>`;
  return {
    subject: "Your Heartshapers password reset code",
    html: shell({ preheader: "Your Heartshapers password-reset code expires in 10 minutes.", heading: "Reset your password", subtitle: "Use this verification code to securely reset your password.", body, footerNote: "For your security, never share this code with anyone, including someone claiming to represent Heartshapers." }),
    text: `Heartshapers password reset\n\nYour five-digit verification code is: ${code}\nThis code expires in 10 minutes.\n\nIf you did not request a password reset, ignore this email. Do not share this code with anyone.`,
  };
}

function paymentStatusEmail({ name, referenceNumber, status, items = [], total = 0, rejectionReason = "" }) {
  const normalizedStatus = ["pending", "verified", "rejected"].includes(status) ? status : "pending";
  const copy = {
    pending: {
      subject: "Heartshapers payment received",
      heading: "Payment submitted",
      subtitle: "We have received your payment details and will review them shortly.",
      intro: "Your payment transaction has been submitted successfully. Please wait for confirmation.",
      footer: "We will email you again when your payment has been reviewed.",
    },
    verified: {
      subject: "Your Heartshapers payment is confirmed",
      heading: "Payment confirmed",
      subtitle: "Thank you for your purchase and for supporting Heartshapers.",
      intro: "Your payment has been successfully verified. Your purchased content is now available in your account.",
      footer: "You can open the Heartshapers app and access your purchased content anytime.",
    },
    rejected: {
      subject: "Update on your Heartshapers payment",
      heading: "Payment needs attention",
      subtitle: "Your payment submission was not approved.",
      intro: "We were unable to verify this payment. Please review the reason below and contact the Heartshapers team if you need help.",
      footer: "You can review your rejected transaction in the Heartshapers app and submit a corrected payment.",
    },
  }[normalizedStatus];

  const itemRows = items.map((item) => {
    const label = `${item.type === "game" ? "Game" : "Book"} · ${item.name || "Content"}`;
    const amount = Number(item.amount || 0);
    return `<tr>
<td style="padding:12px 10px;border-bottom:1px solid #eeeeee;font-size:14px;line-height:1.5;color:#444444;">${escapeHtml(label)}</td>
<td align="right" style="padding:12px 10px;border-bottom:1px solid #eeeeee;font-size:14px;line-height:1.5;color:#252525;font-weight:bold;white-space:nowrap;">₱${amount.toLocaleString("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
</tr>`;
  }).join("");
  const itemTable = `<div style="margin-top:20px;border:1px solid #eeeeee;border-radius:10px;overflow:hidden;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
<tr><td colspan="2" style="padding:13px 10px;background:#fafafa;font-size:12px;font-weight:bold;letter-spacing:1px;text-transform:uppercase;color:#777777;">Transaction items</td></tr>
${itemRows || '<tr><td colspan="2" style="padding:12px 10px;color:#777777;">Item details unavailable</td></tr>'}
<tr><td style="padding:14px 10px;font-size:14px;font-weight:bold;color:#252525;">Total</td>
<td align="right" style="padding:14px 10px;font-size:17px;font-weight:bold;color:#d92d20;white-space:nowrap;">₱${Number(total || 0).toLocaleString("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td></tr>
</table></div>`;
  const rejectionPanel = normalizedStatus === "rejected" && rejectionReason
    ? `<div style="margin-top:18px;padding:14px 16px;border-radius:9px;background:#fff5f4;border:1px solid #ffe0dd;color:#8f241d;font-size:13px;line-height:1.65;"><strong>Reason:</strong><br>${escapeHtml(rejectionReason)}</div>`
    : "";
  const body = `<p style="font-size:15px;line-height:1.7;color:#444444;margin:0 0 12px;">Hello ${escapeHtml(name || "there")},</p>
<p style="font-size:15px;line-height:1.7;color:#555555;margin:0 0 12px;">${copy.intro}</p>
${detailPanel("Payment reference", referenceNumber)}
${itemTable}
${rejectionPanel}
<div style="margin-top:18px;padding:14px 16px;border-radius:9px;background:#f7f7f8;border:1px solid #e9e9e9;color:#666666;font-size:13px;line-height:1.65;">${copy.footer}</div>`;
  const textItems = items.map((item) => `- ${item.type === "game" ? "Game" : "Book"}: ${item.name || "Content"} — PHP ${Number(item.amount || 0).toFixed(2)}`).join("\n");
  return {
    subject: copy.subject,
    html: shell({ preheader: copy.intro, heading: copy.heading, subtitle: copy.subtitle, body, footerNote: "Keep this email for your records. If you contact the Heartshapers team, include your payment reference." }),
    text: `Hello ${name || "there"},\n\n${copy.intro}\n\nPayment reference: ${referenceNumber}\n\nItems:\n${textItems}\n\nTotal: PHP ${Number(total || 0).toFixed(2)}${normalizedStatus === "rejected" && rejectionReason ? `\n\nReason: ${rejectionReason}` : ""}\n\n${copy.footer}`,
  };
}

function paymentReceiptEmail({ name, referenceNumber }) {
  return paymentStatusEmail({
    name,
    referenceNumber,
    status: "verified",
    items: [],
    total: 0,
  });
}

module.exports = { verificationEmail, passwordResetEmail, paymentReceiptEmail, paymentStatusEmail };
