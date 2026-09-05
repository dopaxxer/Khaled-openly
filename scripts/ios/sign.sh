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
python3 - <<'PY'
import os,plistlib,pathlib,datetime,shutil
p=pathlib.Path(os.environ['SIGN_DIR']);profile=plistlib.loads((p/'profile.plist').read_bytes());ent=profile['Entitlements'];team=os.environ['APPLE_TEAM_ID'];bundle=os.environ['IOS_BUNDLE_ID'];method=os.environ['DISTRIBUTION_METHOD']
assert team in profile['TeamIdentifier'],'Provisioning profile belongs to another team'
assert ent['application-identifier']==team+'.'+bundle,'Profile must exactly match the Bundle ID'
assert not ent.get('get-task-allow',False),'A distribution provisioning profile is required'
assert profile['ExpirationDate']>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),'Provisioning profile has expired'
assert ent.get('aps-environment')=='production','Enable push capability and use a production distribution profile'
if method=='ad-hoc':assert profile.get('ProvisionedDevices'),'Ad Hoc profile must include registered devices'
else:assert not profile.get('ProvisionedDevices') and not profile.get('ProvisionsAllDevices'),'App Store Connect requires an App Store distribution profile'
if os.environ.get('ENABLE_UNIVERSAL_LINKS')=='true':assert 'com.apple.developer.associated-domains' in ent,'Profile lacks Associated Domains capability'
folder=pathlib.Path.home()/'Library/MobileDevice/Provisioning Profiles';folder.mkdir(parents=True,exist_ok=True);shutil.copyfile(p/'profile.mobileprovision',folder/(profile['UUID']+'.mobileprovision'))
options={'method':'release-testing' if method=='ad-hoc' else 'app-store-connect','signingStyle':'manual','teamID':team,'signingCertificate':'Apple Distribution','provisioningProfiles':{bundle:profile['UUID']},'manageAppVersionAndBuildNumber':False,'stripSwiftSymbols':True,'uploadSymbols':True,'destination':'export'}
(p/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
with open(os.environ['GITHUB_ENV'],'a') as f:f.write('PROFILE_UUID='+profile['UUID']+'\nSIGN_DIR='+str(p)+'\n')
print('Distribution profile validated; signing configuration prepared.')
PY
