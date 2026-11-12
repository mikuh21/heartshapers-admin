# Heartshapers PDF optimization worker

This service performs actual PDF rewriting with Ghostscript. It is intentionally deployed separately from Firebase Functions because the Ghostscript binary is required.

## Runtime and security

- Deploy to Cloud Run in `asia-southeast1`.
- Keep unauthenticated access disabled.
- The Firebase callable `processPdfAsset` obtains a Google metadata-server identity token and invokes the Cloud Run URL.
- Grant the Cloud Functions runtime service account `roles/run.invoker` on this Cloud Run service.
- Grant the Cloud Run service account `roles/storage.objectAdmin` on the Firebase Storage bucket.
- Set `PDF_WORKER_URL` in the Firebase Functions environment to the Cloud Run service URL.
- Set `STORAGE_BUCKET` on Cloud Run to the exact Firebase Storage bucket name.

The worker accepts only book paths under `pdfs/` and game source paths under `games/{gameId}/source/`. It creates a new versioned object and never overwrites or deletes the original. The callable returns the optimized path only when the output is smaller; Firestore references are updated by the existing admin publishing flow after processing succeeds.

## Deploy

Run from the repository root in an authenticated Google Cloud CLI environment:

```powershell
gcloud config set project brewing-connections-ce316
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
gcloud storage buckets list --project brewing-connections-ce316
```

Create or choose a dedicated service account for the worker, then grant it access to the Firebase Storage bucket:

```powershell
gcloud iam service-accounts create heartshapers-pdf-worker --project brewing-connections-ce316
gcloud storage buckets add-iam-policy-binding gs://YOUR_FIREBASE_STORAGE_BUCKET --member="serviceAccount:heartshapers-pdf-worker@brewing-connections-ce316.iam.gserviceaccount.com" --role="roles/storage.objectAdmin"
```

Deploy the worker from the repository root:

```powershell
gcloud run deploy heartshapers-pdf-worker --source .\pdf-worker --region asia-southeast1 --project brewing-connections-ce316 --service-account heartshapers-pdf-worker@brewing-connections-ce316.iam.gserviceaccount.com --no-allow-unauthenticated --set-env-vars STORAGE_BUCKET=YOUR_FIREBASE_STORAGE_BUCKET --memory 2Gi --cpu 2 --timeout 600 --concurrency 1
```

Get the Firebase Functions runtime service account (for the default Gen 2 runtime identity, use the project number shown by the command below), then allow it to invoke Cloud Run:

```powershell
gcloud projects describe brewing-connections-ce316 --format="value(projectNumber)"
gcloud run services add-iam-policy-binding heartshapers-pdf-worker --region asia-southeast1 --project brewing-connections-ce316 --member="serviceAccount:PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/run.invoker"
```

Copy the Cloud Run URL from the deploy output. Create `functions/.env.brewing-connections-ce316` (do not commit it) containing:

```dotenv
PDF_WORKER_URL=https://YOUR_CLOUD_RUN_SERVICE_URL
```

Then deploy the callable:

```powershell
cd functions
npm install
cd ..
firebase deploy --only functions:processPdfAsset --project brewing-connections-ce316
```

If the Firebase Functions runtime uses a custom service account, grant `roles/run.invoker` to that account instead of the default compute account.

## Processing behavior

Ghostscript uses the `/ebook` profile as a balance between file size and readable on-screen content. PDFs are validated before and after rewriting. Files over 100 MB are rejected. If the output is not smaller, it is deleted and the original Storage path is returned. Original PDFs are retained for rollback and recovery.

This worker does not process game card-page images; that remains the separate browser image optimization pipeline.
