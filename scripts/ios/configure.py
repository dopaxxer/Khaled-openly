#!/usr/bin/env python3
"""Validate non-secret build settings and optional universal-link entitlement."""
import os,plistlib,re
from pathlib import Path
from urllib.parse import urlparse
origin=os.environ.get('OPENLY_API_ORIGIN','https://openly.invalid')
u=urlparse(origin)
if u.scheme!='https' or not u.hostname or u.username or u.query or u.fragment or u.path not in ('','/'):
 raise SystemExit('OPENLY_API_ORIGIN must be an HTTPS origin without credentials, query, or path.')
bundle=os.environ.get('IOS_BUNDLE_ID','com.openly.social')
if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}',bundle):raise SystemExit('Invalid IOS_BUNDLE_ID')
team=os.environ.get('APPLE_TEAM_ID','')
if team and not re.fullmatch(r'[A-Z0-9]{10}',team):raise SystemExit('APPLE_TEAM_ID must contain 10 uppercase letters or digits')
ent={'aps-environment':'production'}
if os.environ.get('ENABLE_UNIVERSAL_LINKS')=='true':ent['com.apple.developer.associated-domains']=['applinks:'+u.hostname]
Path('ios/Openly/Openly.entitlements').write_bytes(plistlib.dumps(ent))
print('Validated app identity and API origin; configured entitlements.')
