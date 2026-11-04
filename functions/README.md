# Cloud Functions account verification email setup

The Firebase Auth user-management callables generate Firebase email-verification action links and send them using SMTP through Nodemailer. Configure these secrets in the Firebase project before deploying the functions that create users/admins.

Set the secrets from the repository root (Firebase CLI authenticated and project selected as `heartshapers-3978`):

```bash
firebase functions:secrets:set SMTP_HOST
firebase functions:secrets:set SMTP_PORT
firebase functions:secrets:set SMTP_USER
firebase functions:secrets:set SMTP_PASSWORD
firebase functions:secrets:set SMTP_FROM
firebase functions:secrets:set VERIFY_CONTINUE_URL
```

Use SMTP credentials issued by the email provider. `SMTP_PORT` is typically 587 (STARTTLS) or 465 (TLS). `SMTP_FROM` should be the verified sender address. `VERIFY_CONTINUE_URL` must be an HTTPS URL on a domain authorized in Firebase Authentication settings; it is the post-verification continuation URL.

Then deploy:

```bash
cd functions
npm install
cd ..
firebase deploy --only functions
```

The callable responses include `email_sent`. If SMTP delivery fails after the account is created, the account remains created with `emailVerified=false`; the function logs a sanitized failure code and returns `email_sent=false`. Do not treat the account as verified. Configure SMTP secrets before account creation in production and use the Firebase Auth console or a dedicated resend flow to retry verification.

Role checks support Firebase custom claims `role` and `roles` (string or array), and prioritize `super_admin` when both claims are present.
