// Waits for Postgres, then runs Eclaire's own upgrade check/upgrade while holding an
// advisory lock, so overlapping deploys never migrate twice. Exits non-zero on failure.
import { spawnSync } from "node:child_process";
import postgres from "postgres";

const LOCK = 30993099;
const log = (m) => console.log(`[railway] ${m}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function connect() {
  for (let i = 1; i <= 90; i++) {
    const sql = postgres(process.env.DATABASE_URL, { max: 1, connect_timeout: 5, onnotice: () => {} });
    try { await sql`select 1`; return sql; }
    catch (e) { await sql.end({ timeout: 1 }).catch(() => {}); if (i % 10 === 1) log(`waiting for Postgres (${e.code || e.message})`); await sleep(2000); }
  }
  throw new Error("Postgres did not answer within 3 minutes");
}

function run(script, args = []) {
  return spawnSync("node", [`dist/src/scripts/${script}`, ...args], { stdio: "inherit", cwd: "/app" }).status;
}

const sql = await connect();
let locked = false;
for (let i = 0; i < 300 && !locked; i++) {
  [{ locked }] = await sql`select pg_try_advisory_lock(${LOCK}) as locked`;
  if (!locked) { if (i % 15 === 0) log("another deploy is migrating; waiting"); await sleep(2000); }
}
if (!locked) { log("timed out waiting for the migration lock"); process.exit(1); }

let code = 0;
try {
  const state = run("upgrade-check.js", ["--quiet"]);
  // 0 up-to-date, 3 fresh install, 4 safe upgrade, 1 manual upgrade, 2 downgrade, 5 blocked
  if (state === 0) log("database is up to date");
  else if (state === 3 || state === 4) {
    log(state === 3 ? "fresh install: initialising the database" : "applying a safe upgrade");
    const r = run("upgrade.js");
    if (r !== 0) { log(`upgrade failed (exit ${r})`); code = 1; }
  } else if (state === 1) {
    log("this version needs a manual upgrade step; running it (see CHANGELOG.md)");
    const r = run("upgrade.js");
    if (r !== 0) { log(`upgrade failed (exit ${r})`); code = 1; }
  } else if (state === 2) { log("the database is newer than this app version (downgrade); refusing to start"); code = 1; }
  else { log(`upgrade check returned ${state}; refusing to start`); code = 1; }
} finally {
  await sql`select pg_advisory_unlock(${LOCK})`.catch(() => {});
  await sql.end({ timeout: 2 });
}
process.exit(code);
