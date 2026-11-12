const express = require("express");
const os = require("node:os");
const path = require("node:path");
const fs = require("node:fs/promises");
const { spawn } = require("node:child_process");
const crypto = require("node:crypto");
const { Storage } = require("@google-cloud/storage");

const app = express();
app.use(express.json({ limit: "1mb" }));
const storage = new Storage();
const bucketName = process.env.STORAGE_BUCKET;
const MAX_PDF_BYTES = 100 * 1024 * 1024;

function runGhostscript(input, output) {
  return new Promise((resolve, reject) => {
    const args = [
      "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-dPDFSETTINGS=/ebook",
      "-dNOPAUSE", "-dBATCH", "-dSAFER", "-dQUIET",
      "-dDetectDuplicateImages=true", "-dCompressFonts=true",
      "-dSubsetFonts=true", "-dAutoRotatePages=/PageByPage",
      "-sOutputFile=" + output, input
    ];
    const child = spawn("gs", args, { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    child.stderr.on("data", chunk => { stderr += chunk.toString().slice(-4000); });
    child.on("error", reject);
    child.on("close", code => code === 0 ? resolve() : reject(new Error("Ghostscript failed: " + stderr.slice(-1500))));
  });
}

function validatePath(assetType, assetId, sourcePath) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(assetId) || sourcePath.includes("..") || sourcePath.includes("\\\\")) return false;
  if (assetType === "book") return /^pdfs\/[A-Za-z0-9._/-]+\.pdf$/i.test(sourcePath) && sourcePath.startsWith("pdfs/");
  if (assetType === "game") return sourcePath.startsWith("games/" + assetId + "/source/") && /^games\/[A-Za-z0-9_-]+\/source\/[A-Za-z0-9._-]+\.pdf$/i.test(sourcePath);
  return false;
}

app.get("/health", (_req, res) => res.status(200).send("ok"));
app.post("/optimize", async (req, res) => {
  if (!bucketName) return res.status(500).json({ error: "STORAGE_BUCKET is not configured." });
  const { assetType, assetId, sourcePath } = req.body || {};
  if (!validatePath(assetType, String(assetId || ""), String(sourcePath || ""))) {
    return res.status(400).json({ error: "Invalid asset type, ID, or source path." });
  }

  const bucket = storage.bucket(bucketName);
  const source = bucket.file(sourcePath);
  const [metadata] = await source.getMetadata().catch(() => [null]);
  const sourceBytes = Number(metadata?.size || 0);
  if (!sourceBytes || sourceBytes > MAX_PDF_BYTES) return res.status(400).json({ error: "PDF is missing, empty, or exceeds 100 MB." });
  if (metadata.contentType && metadata.contentType !== "application/pdf" && !sourcePath.toLowerCase().endsWith(".pdf")) {
    return res.status(400).json({ error: "Source object is not a PDF." });
  }

  const workDir = await fs.mkdtemp(path.join(os.tmpdir(), "hs-pdf-"));
  const input = path.join(workDir, "source.pdf");
  const output = path.join(workDir, "optimized.pdf");
  try {
    await source.download({ destination: input });
    const header = await fs.open(input, "r");
    const magic = Buffer.alloc(5);
    await header.read(magic, 0, 5, 0);
    await header.close();
    if (magic.toString("ascii") !== "%PDF-") throw new Error("Source file does not contain a valid PDF header.");

    await runGhostscript(input, output);
    const stat = await fs.stat(output);
    if (!stat.size || stat.size > MAX_PDF_BYTES) throw new Error("Optimized PDF is empty or exceeds the supported size.");
    const handle = await fs.open(output, "r");
    const optimizedMagic = Buffer.alloc(5);
    await handle.read(optimizedMagic, 0, 5, 0);
    await handle.close();
    if (optimizedMagic.toString("ascii") !== "%PDF-") throw new Error("Optimized output failed PDF validation.");

    const suffix = crypto.randomUUID();
    const outputPath = assetType === "book"
      ? "pdfs/optimized/" + assetId + "/" + suffix + ".pdf"
      : "games/" + assetId + "/source/optimized-" + suffix + ".pdf";
    await bucket.upload(output, { destination: outputPath, resumable: false, metadata: {
      contentType: "application/pdf",
      cacheControl: "private,max-age=31536000,immutable",
      metadata: { optimizedBy: "ghostscript", sourcePath, sourceBytes: String(sourceBytes) }
    }});
    return res.status(200).json({
      optimizedPath: outputPath,
      originalBytes: sourceBytes,
      optimizedBytes: stat.size,
      savedBytes: Math.max(0, sourceBytes - stat.size),
      reduced: stat.size < sourceBytes
    });
  } catch (error) {
    console.error("PDF optimization failed", { assetType, assetId, message: error.message });
    return res.status(422).json({ error: error.message || "PDF optimization failed." });
  } finally {
    await fs.rm(workDir, { recursive: true, force: true }).catch(() => {});
  }
});

const port = Number(process.env.PORT || 8080);
app.listen(port, "0.0.0.0", () => console.log("PDF worker listening on", port));
