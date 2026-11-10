# One mobile device per customer account

Customer accounts can be linked to one Android or iOS device at a time. The app hashes the platform device identifier before sending it to Firebase, and the `claimMobileDevice` callable atomically claims it for the signed-in Firebase Auth UID. A second device is denied and signed out by the app. Firebase custom claims and the private `device_bindings/{uid}` document gate Firestore, Storage, email verification, payments, and protected book/game access. Android uses `ANDROID_ID`; iOS uses IDFV. If iOS temporarily returns no vendor ID before first unlock, the app uses a persisted installation fallback.

Administrators can release a customer account from **Users → Reset device**. That revokes refresh tokens, clears the device claim, and invalidates the stored binding. The next mobile device to sign in claims the account. Android factory reset/signing key changes and removal of every app from the iOS vendor may change the platform ID; use the admin reset action if that happens.

## Deployment order

Do not deploy the stricter Firestore and Storage rules to production until the updated mobile app is available to users. The new app calls `claimMobileDevice` at signup/sign-in and on restored sessions; older app versions do not have the required device claim and will lose customer data access once the rules are active.

1. Deploy the `claimMobileDevice` and `resetManagedUserDevice` callables first.
2. Rebuild and release the updated mobile app as a new native binary (the Expo Application and Crypto native modules must be included), and rebuild/upload the admin site.
3. Deploy `firestore.rules` and `storage.rules` after customers have updated the mobile app.

Platform IDs are device-scoped identifiers, not hardware attestation. A determined user with a rooted/jailbroken device can spoof them. App Check can help attest genuine app instances, but it does not provide a guaranteed physical-device identity.
