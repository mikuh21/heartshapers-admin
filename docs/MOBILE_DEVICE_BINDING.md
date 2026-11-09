# One mobile device per customer account

Customer accounts can be linked to one Heartshapers mobile app installation at a time. The mobile app stores an installation ID in AsyncStorage, and the `claimMobileDevice` callable atomically claims it for the signed-in Firebase Auth UID. A second installation is denied and is signed out by the app. Firebase custom claims and the private `device_bindings/{uid}` document gate Firestore, Storage, email verification, payments, and protected book/game access.

Administrators can release a customer account from **Users → Reset device**. That revokes refresh tokens, clears the device claim, and invalidates the stored binding. The next mobile installation to sign in claims the account. App reinstall or clearing app storage creates a new installation ID, so an administrator must reset the binding in that case.

## Deployment order

Do not deploy the stricter Firestore and Storage rules to production until the updated mobile app is available to users. The new app calls `claimMobileDevice` at signup/sign-in and on restored sessions; older app versions do not have the required device claim and will lose customer data access once the rules are active.

1. Deploy the `claimMobileDevice` and `resetManagedUserDevice` callables first.
2. Build and release the updated mobile app and admin site.
3. Deploy `firestore.rules` and `storage.rules` after customers have updated the mobile app.

The binding is an account-slot policy, not hardware attestation: a determined user with control of the app's local storage could copy its installation ID. App Check can help attest genuine app instances, but it does not provide a guaranteed physical-device identity.
