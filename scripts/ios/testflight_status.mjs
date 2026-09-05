import { readFileSync, writeFileSync } from "node:fs";
import { sign } from "node:crypto";
const {
  ASC_KEY_ID,
  ASC_ISSUER_ID,
  ASC_KEY_PATH,
  ASC_APP_ID,
  BUILD_NUMBER,
  STATUS_OUTPUT,
} = process.env;
for (const [key, value] of Object.entries({
  ASC_KEY_ID,
  ASC_ISSUER_ID,
  ASC_KEY_PATH,
  ASC_APP_ID,
  BUILD_NUMBER,
  STATUS_OUTPUT,
}))
  if (!value) throw new Error(`Missing ${key}`);
const base = (s) => Buffer.from(JSON.stringify(s)).toString("base64url");
const header = base({ alg: "ES256", kid: ASC_KEY_ID, typ: "JWT" });
const time = Math.floor(Date.now() / 1000);
const payload = base({
  iss: ASC_ISSUER_ID,
  iat: time,
  exp: time + 1200,
  aud: "appstoreconnect-v1",
});
const message = header + "." + payload;
const jwt =
  message +
  "." +
  sign("sha256", Buffer.from(message), {
    key: readFileSync(ASC_KEY_PATH),
    dsaEncoding: "ieee-p1363",
  }).toString("base64url");
let report = {
  upload: "accepted by upload tool",
  apple_processing: "not yet observed",
  available_to_testers: "not verified",
};
for (let attempt = 0; attempt < 20; attempt++) {
  const url = new URL("https://api.appstoreconnect.apple.com/v1/builds");
  url.searchParams.set("filter[app]", ASC_APP_ID);
  url.searchParams.set("filter[version]", BUILD_NUMBER);
  url.searchParams.set("limit", "1");
  const r = await fetch(url, { headers: { authorization: "Bearer " + jwt } });
  if (!r.ok) {
    report.apple_processing = "status query failed: HTTP " + r.status;
    break;
  }
  const data = await r.json();
  const build = data.data?.[0];
  if (build) {
    report.build_id = build.id;
    report.apple_processing = build.attributes.processingState;
    if (
      ["VALID", "FAILED", "INVALID"].includes(build.attributes.processingState)
    )
      break;
  }
  await new Promise((resolve) => setTimeout(resolve, 30000));
}
writeFileSync(STATUS_OUTPUT, JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report, null, 2));
if (["FAILED", "INVALID"].includes(report.apple_processing))
  process.exitCode = 1;
