#!/usr/bin/env python3
import os
import plistlib
import shutil
from pathlib import Path
from urllib.parse import urlparse
from profile_rules import validate_profile

root = Path(os.environ["SIGN_DIR"])
profile = plistlib.loads((root / "profile.plist").read_bytes())
team, bundle = os.environ["APPLE_TEAM_ID"], os.environ["IOS_BUNDLE_ID"]
domain = urlparse(os.environ["OPENLY_API_ORIGIN"]).hostname if os.environ.get("ENABLE_UNIVERSAL_LINKS") == "true" else None
checked = validate_profile(profile, team, bundle, os.environ["DISTRIBUTION_METHOD"], domain=domain)
folder = Path.home() / "Library/MobileDevice/Provisioning Profiles"
folder.mkdir(parents=True, exist_ok=True)
# Record cleanup ownership before creating the installed copy.
with open(os.environ["GITHUB_ENV"], "a") as f:
    f.write("PROFILE_UUID=" + profile["UUID"] + "\n")
shutil.copyfile(root / "profile.mobileprovision", folder / (profile["UUID"] + ".mobileprovision"))
options = {
    "method": "release-testing" if checked["method"] == "ad-hoc" else "app-store-connect",
    "signingStyle": "manual", "teamID": team, "signingCertificate": "Apple Distribution",
    "provisioningProfiles": {bundle: profile["UUID"]}, "manageAppVersionAndBuildNumber": False,
    "stripSwiftSymbols": True, "uploadSymbols": True, "destination": "export",
}
(root / "ExportOptions.plist").write_bytes(plistlib.dumps(options))
print("Distribution profile validated; signing configuration prepared.")
