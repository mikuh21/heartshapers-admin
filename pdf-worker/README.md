# Heartshapers PDF optimization worker

This service performs PDF rewriting with Ghostscript. It runs separately from Firebase Functions because the Ghostscript binary is required.

## Storage layout

Book source PDFs are stored dynamically by their Firestore taxonomy:

- `pdfs/{pillar-slug}/{filename}.pdf`
- `pdfs/{pillar-slug}/{subcategory-slug}/{filename}.pdf`

Optimized book PDFs are written beside the source in a nested `optimized/{bookId}/` directory. For example:

- Source: `pdfs/work/discipleship/source-book.pdf`
- Optimized: `pdfs/work/discipleship/optimized/{bookId}/{uuid}.pdf`

The worker supports any pillar and subcategory slug; no taxonomy names are hardcoded. It accepts one or two category segments and rejects paths that attempt traversal or point into an existing optimized directory.

Game PDF processing remains unchanged and writes to `games/{gameId}/source/optimized-{uuid}.pdf`.

## Runtime and security

- Deploy to Cloud Run in `asia-southeast1`.
- Keep unauthenticated access disabled.
- The Firebase callable `processPdfAsset` obtains a Google metadata-server identity token and invokes the Cloud Run URL.
- Grant the Cloud Functions runtime service account `roles/run.invoker` on this Cloud Run service.
- Grant the Cloud Run service account `roles/storage.objectAdmin` on the Firebase Storage bucket.
- Set `PDF_WORKER_URL` in Firebase Functions environment to the Cloud Run service URL.
- Set `STORAGE_BUCKET` on Cloud Run to the exact Firebase Storage bucket name.

The worker creates a new object and never overwrites or deletes the original. The existing publishing flow should select the optimized path only when it is smaller; otherwise it retains the original source path.

## Deploy

Run from the repository root in an authenticated Google Cloud CLI environment:

```powershell
gcloud config set project brewing-connections-ce316
gcloud run deploy heartshapers-pdf-worker --source .\pdf-worker --region asia-southeast1 --project brewing-connections-ce316 --service-account heartshapers-pdf-worker@brewing-connections-ce316.iam.gserviceaccount.com --no-allow-unauthenticated --set-env-vars STORAGE_BUCKET=brewing-connections-ce316.firebasestorage.app --memory 2Gi --cpu 2 --timeout 600 --concurrency 1
```

After deploying, confirm the existing Cloud Run invoker binding still grants the Firebase Functions runtime identity access. Do not make the service public.

Deploy the Firebase callable only after confirming `PDF_WORKER_URL` is configured for the Cloud Functions runtime:

```powershell
firebase deploy --only functions:processPdfAsset --project brewing-connections-ce316
```

## Processing behavior

Ghostscript uses the `/ebook` profile as a balance between file size and readable on-screen content. PDFs are validated before and after rewriting. Files over 100 MB are rejected. The worker reports whether the result is smaller; the caller should delete an unhelpful optimized derivative and keep the original reference. Original PDFs are retained for rollback and recovery.

This worker does not process game card-page images; that remains the separate browser image optimization pipeline.
