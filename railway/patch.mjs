// Build-time patches to Eclaire's compiled JS. Each replacement must match exactly once,
// so a version bump that changes the code fails the build instead of shipping silently.
import fs from "node:fs";

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
