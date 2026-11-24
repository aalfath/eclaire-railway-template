// Build-time patches to Eclaire's compiled JS. Each replacement must match exactly once,
// so a version bump that changes the code fails the build instead of shipping silently.
import fs from "node:fs";
import path from "node:path";

function patch(file, from, to) {
  const src = fs.readFileSync(file, "utf8");
  const count = src.split(from).length - 1;
  if (count !== 1) {
    console.error(`patch: expected 1 match in ${file}, found ${count}:\n${from}`);
    process.exit(1);
  }
  fs.writeFileSync(file, src.replace(from, to));
  console.log(`patched ${file}`);
}

// 1. Close open email sign-up (upstream always allows it).
patch(
  "/app/dist/src/lib/auth.js",
  "requireEmailVerification: false,",
  'requireEmailVerification: false,\n        disableSignUp: process.env.ECLAIRE_ALLOW_SIGNUP !== "true",',
);

// 2. Docling is optional: skip it unless DOCLING_SERVER_URL is set.
const dp = "/app/dist/src/workers/jobs/documentProcessor.js";
patch(
  dp,
  "function shouldProcessWithDocling(mimeType) {",
  'function shouldProcessWithDocling(mimeType) {\n    if (!process.env.DOCLING_SERVER_URL || process.env.DOCLING_SERVER_URL === "disabled")\n        return false;',
);
// ...and let LibreOffice extract text from the OOXML types Docling would have handled.
patch(
  dp,
  '        "application/vnd.apple.keynote",\n    ];',
  '        "application/vnd.apple.keynote",\n' +
    '        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",\n' +
    '        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",\n' +
    '        "application/vnd.openxmlformats-officedocument.presentationml.presentation",\n    ];',
);

// 3. Postgres pool size (upstream: 10), so Railway Postgres fits a small plan.
patch(
  "/app/node_modules/@eclaire/db/dist/clients.js",
  "max: 10, // Maximum number of connections",
  "max: Number(process.env.DATABASE_POOL_MAX || 10), // Maximum number of connections",
);

// 4. Full-page screenshots of long pages need more RAM than a 0.5 GB service has.
//    ECLAIRE_FULLPAGE_SCREENSHOTS=false (set by start.sh below 2 GB) captures the viewport instead.
for (const f of [
  "/app/dist/src/workers/lib/bookmarks/browser-pipeline.js",
  "/app/dist/src/workers/lib/bookmarks/reddit-api.js",
]) {
  const src = fs.readFileSync(f, "utf8");
  const n = src.split("fullPage: true").length - 1;
  if (n !== 1) { console.error(`patch: expected 1 fullPage in ${f}, found ${n}`); process.exit(1); }
  fs.writeFileSync(f, src.replace("fullPage: true", 'fullPage: process.env.ECLAIRE_FULLPAGE_SCREENSHOTS !== "false"'));
  console.log(`patched ${f}`);
}

// 5. Chromium and LibreOffice go through oom-first.sh (OOM victim before Node, small /dev/shm safe).
const pw = "/home/nodeapp/.cache/ms-playwright";
const targets = [];
for (const d of fs.readdirSync(pw)) {
  for (const [sub, bin] of [["chrome-headless-shell-linux64", "chrome-headless-shell"], ["chrome-linux64", "chrome"]]) {
    const f = path.join(pw, d, sub, bin);
    if (fs.existsSync(f)) targets.push(f);
  }
}
if (targets.length < 2) { console.error(`patch: Chromium binaries not found (${targets})`); process.exit(1); }
for (const f of targets) {
  fs.renameSync(f, f + ".real");
  fs.copyFileSync("/app/railway/oom-first.sh", f);
  fs.chmodSync(f, 0o755);
  console.log(`wrapped ${f}`);
}
// LibreOffice: Eclaire calls /usr/bin/libreoffice first.
const lo = "/usr/bin/libreoffice";
if (!fs.existsSync("/usr/lib/libreoffice/program/soffice")) { console.error("patch: soffice not found"); process.exit(1); }
fs.unlinkSync(lo);
fs.symlinkSync("/usr/lib/libreoffice/program/soffice", lo + ".real");
fs.copyFileSync("/app/railway/oom-first.sh", lo);
fs.chmodSync(lo, 0o755);
console.log(`wrapped ${lo}`);
