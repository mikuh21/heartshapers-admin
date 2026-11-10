# Cloud Functions account verification email setup

For `brewing-connections-ce316`, the required SMTP, continuation URL, and OTP pepper secrets have already been configured and the Functions are deployed. The commands below are for rotating or replacing a secret; do not paste secret values into source control or chat.

The Firebase Auth user-management callables generate Firebase email-verification action links and send them using SMTP through Nodemailer. Configure these secrets in the Firebase project before deploying the functions that create users/admins.

Set the secrets from the repository root after confirming the intended Firebase project and authenticating the Firebase CLI:

```bash
firebase functions:secrets:set SMTP_HOST
firebase functions:secrets:set SMTP_PORT
firebase functions:secrets:set SMTP_USER
firebase functions:secrets:set SMTP_PASSWORD
firebase functions:secrets:set SMTP_FROM
firebase functions:secrets:set VERIFY_CONTINUE_URL
firebase functions:secrets:set OTP_PEPPER
```

Use SMTP credentials issued by the email provider. `SMTP_PORT` is typically 587 (STARTTLS) or 465 (TLS). `SMTP_FROM` should be the verified sender address. `VERIFY_CONTINUE_URL` must be an HTTPS URL on a domain authorized in Firebase Authentication settings; it is the post-verification continuation URL.

Then deploy:

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

The mobile password reset callable uses `OTP_PEPPER` to hash five-digit codes and single-use reset tokens. Use a unique random value and keep it in Secret Manager. The callable returns a generic response when an email is not registered. Codes expire after 10 minutes, are rate-limited to one per minute, and allow up to five verification attempts.

`submitCartPayment` verifies the signed-in UID, active catalog records, VIP status, purchases, access overrides, and the server-side total before writing pending payment rows. Customer proof uploads are limited by Storage Rules to `payment-proofs/{uid}/payments/{paymentId}/{fileName}`; customers cannot read or replace proof files.

The callable responses include `email_sent`. If SMTP delivery fails after the account is created, the account remains created with `emailVerified=false`; the function logs a sanitized failure code and returns `email_sent=false`. Do not treat the account as verified. Configure SMTP secrets before account creation in production and use the Firebase Auth console or a dedicated resend flow to retry verification.

Role checks support Firebase custom claims `role` and `roles` (string or array), and prioritize `super_admin` when both claims are present.
