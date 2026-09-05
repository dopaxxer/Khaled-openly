#!/usr/bin/env python3
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from urllib.parse import urlparse
from profile_rules import validate_signed_app


def main():
    ipa, method = Path(sys.argv[1]), sys.argv[2]
    required = ('APPLE_TEAM_ID', 'IOS_BUNDLE_ID', 'MARKETING_VERSION', 'BUILD_NUMBER')
    missing = [key for key in required if not os.environ.get(key)]
    if missing:
        raise ValueError('Missing expected export configuration: ' + ', '.join(missing))
    domain = urlparse(os.environ['OPENLY_API_ORIGIN']).hostname if os.environ.get('ENABLE_UNIVERSAL_LINKS') == 'true' else None
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(temp)
        apps = list((Path(temp) / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('IPA must contain exactly one application')
        app = apps[0]
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')]))
        entitlements = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.PIPE))
        certificate_prefix = str(Path(temp) / 'signer')
        subprocess.run(['codesign', '-d', '--extract-certificates', certificate_prefix, str(app)], check=True, capture_output=True)
        certificate = Path(certificate_prefix + '0').read_bytes()
        checked = validate_signed_app(profile, entitlements, info, certificate,
            os.environ['APPLE_TEAM_ID'], os.environ['IOS_BUNDLE_ID'], method,
            os.environ['MARKETING_VERSION'], os.environ['BUILD_NUMBER'], domain=domain)
        report = {
            'file': ipa.name, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'bundle_id': info['CFBundleIdentifier'], 'signature': 'codesign verified',
            'provisioning': 'team, app, certificate, entitlements, expiry and requested version/build matched',
            'distribution': checked['method'], 'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
            'profile_expires': checked['expires'].isoformat(), 'registered_device_count': checked['device_count'],
            'testflight_upload': 'not evaluated by signature verifier; see testflight-status.json',
            'apple_processing': 'see separate TestFlight status report', 'available_to_testers': 'not verified',
            'physical_device_installation': 'not verified',
        }
        ipa.with_suffix('.verification.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({k: v for k, v in report.items() if k != 'registered_device_count'}, indent=2))


if __name__ == '__main__':
    main()
