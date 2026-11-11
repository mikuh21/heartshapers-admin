import React, { useEffect, useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";
import { isFirebaseConfigured, missingFirebaseSettings } from "../lib/firebase";
import {
  connectFirebaseStorage,
  subscribeToStorageAuth
} from "../lib/firebaseStorage";

export default function StorageConnectionBanner() {
  const [user, setUser] = useState(undefined);
  const [formOpen, setFormOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => subscribeToStorageAuth((nextUser) => {
    setUser(nextUser);
    if (nextUser) {
      setPassword("");
      setError("");
      setFormOpen(false);
    }
  }), []);

  if (user === undefined || user) return null;

  if (!isFirebaseConfigured) {
    return (
      <div className="storage-banner" role="alert">
        <AlertTriangle size={18} />
        <div className="storage-banner-copy">
          <strong>Firebase Storage is not configured.</strong>
          <span>Add {missingFirebaseSettings.join(", ")} to the admin environment, then rebuild.</span>
        </div>
      </div>
    );
  }

  async function handleConnect(event) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await connectFirebaseStorage(email, password);
    } catch (connectError) {
      const code = String(connectError?.code || "");
      if (code === "auth/invalid-credential" || code === "auth/wrong-password" || code === "auth/user-not-found") {
        setError("Firebase rejected those credentials. Use the Firebase admin account, not the Supabase one.");
      } else if (code === "auth/unauthorized-domain") {
        setError("This site is not an authorized domain in Firebase Authentication.");
      } else {
        setError(connectError?.message || "Unable to connect Firebase Storage.");
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="storage-banner" role="status">
      <AlertTriangle size={18} />
      <div className="storage-banner-copy">
        <strong>Firebase Storage is not connected.</strong>
        <span>Uploads stay disabled until an administrator signs in to Firebase.</span>
      </div>
      {formOpen ? (
        <form className="storage-banner-form" onSubmit={handleConnect}>
          <input
            type="email"
            autoComplete="username"
            placeholder="Firebase admin email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
            disabled={busy}
          />
          <input
            type="password"
            autoComplete="current-password"
            placeholder="Password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
            disabled={busy}
          />
          <button className="primary-btn" type="submit" disabled={busy}>
            {busy ? <Loader2 className="spin" size={16} /> : null}
            {busy ? "Connecting..." : "Connect"}
          </button>
          <button className="secondary-btn" type="button" onClick={() => setFormOpen(false)} disabled={busy}>
            Cancel
          </button>
        </form>
      ) : (
        <button className="primary-btn" type="button" onClick={() => setFormOpen(true)}>
          Connect
        </button>
      )}
      {error ? <div className="field-error storage-banner-error">{error}</div> : null}
    </div>
  );
}
