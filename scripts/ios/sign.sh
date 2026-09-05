#!/usr/bin/env bash
set -euo pipefail
# Never enable xtrace. All signing material lives in the temporary runner directory.
: "${RUNNER_TEMP:?}" "${CERTIFICATE_P12_BASE64:?}" "${CERTIFICATE_PASSWORD:?}" "${PROFILE_BASE64:?}" "${APPLE_TEAM_ID:?}" "${IOS_BUNDLE_ID:?}" "${DISTRIBUTION_METHOD:?}"
umask 077
SIGN_DIR="$RUNNER_TEMP/openly-signing"
mkdir -p "$SIGN_DIR"
export SIGN_DIR
printf 'SIGN_DIR=%s\n' "$SIGN_DIR" >> "$GITHUB_ENV"
python3 - <<'PY'
import base64,os,pathlib
p=pathlib.Path(os.environ['SIGN_DIR'])
(p/'certificate.p12').write_bytes(base64.b64decode(os.environ['CERTIFICATE_P12_BASE64'],validate=True))
(p/'profile.mobileprovision').write_bytes(base64.b64decode(os.environ['PROFILE_BASE64'],validate=True))
PY
SIGN_PASSWORD="$(openssl rand -hex 24)"
security create-keychain -p "$SIGN_PASSWORD" "$SIGN_DIR/build.keychain-db"
security set-keychain-settings -lut 21600 "$SIGN_DIR/build.keychain-db"
security unlock-keychain -p "$SIGN_PASSWORD" "$SIGN_DIR/build.keychain-db"
security import "$SIGN_DIR/certificate.p12" -P "$CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$SIGN_DIR/build.keychain-db" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$SIGN_PASSWORD" "$SIGN_DIR/build.keychain-db" >/dev/null
security list-keychains -d user -s "$SIGN_DIR/build.keychain-db" login.keychain-db
security cms -D -i "$SIGN_DIR/profile.mobileprovision" > "$SIGN_DIR/profile.plist"
python3 scripts/ios/prepare_profile.py
