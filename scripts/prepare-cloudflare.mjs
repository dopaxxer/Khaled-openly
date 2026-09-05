import { readFileSync, writeFileSync } from "node:fs";
const {
  CLOUDFLARE_WORKER_NAME,
  CLOUDFLARE_D1_ID,
  CLOUDFLARE_R2_BUCKET,
  PUBLIC_ORIGIN,
  IOS_BUNDLE_ID,
  APPLE_TEAM_ID,
} = process.env;
if (!/^[a-z0-9][a-z0-9-]{1,60}$/.test(CLOUDFLARE_WORKER_NAME || ""))
  throw Error("Set CLOUDFLARE_WORKER_NAME to the new deployment name");
if (!/^[a-f0-9-]{36}$/.test(CLOUDFLARE_D1_ID || ""))
  throw Error("Set the actual CLOUDFLARE_D1_ID");
if (!/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/.test(CLOUDFLARE_R2_BUCKET || ""))
  throw Error("Set CLOUDFLARE_R2_BUCKET");
const origin = new URL(PUBLIC_ORIGIN || "");
if (origin.protocol !== "https:" || origin.origin !== PUBLIC_ORIGIN)
  throw Error("PUBLIC_ORIGIN must be an HTTPS origin");
const path = "dist/server/wrangler.json";
const config = JSON.parse(readFileSync(path, "utf8"));
config.name = CLOUDFLARE_WORKER_NAME;
config.d1_databases = [
  {
    binding: "DB",
    database_name: CLOUDFLARE_WORKER_NAME,
    database_id: CLOUDFLARE_D1_ID,
    migrations_dir: "../../drizzle",
  },
];
config.r2_buckets = [{ binding: "BUCKET", bucket_name: CLOUDFLARE_R2_BUCKET }];
config.vars = {
  PUBLIC_ORIGIN,
  IOS_BUNDLE_ID: IOS_BUNDLE_ID || "com.openly.social",
  APPLE_TEAM_ID: APPLE_TEAM_ID || "",
};
writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
console.log(
  "Prepared deployment configuration with explicit database and private bucket bindings.",
);
