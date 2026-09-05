#!/usr/bin/env python3
import sys,zipfile,plistlib,tempfile,subprocess,json,datetime,hashlib
from pathlib import Path
ipa=Path(sys.argv[1]);method=sys.argv[2]
with tempfile.TemporaryDirectory() as temp:
 with zipfile.ZipFile(ipa) as z:z.extractall(temp)
 app=next((Path(temp)/'Payload').glob('*.app'))
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 info=plistlib.loads((app/'Info.plist').read_bytes())
 p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(app/'embedded.mobileprovision')]))
 assert bool(p.get('ProvisionedDevices'))==(method=='ad-hoc'),'Wrong distribution method'
 report={'file':ipa.name,'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'bundle_id':info['CFBundleIdentifier'],'signature':'codesign verified','distribution':method,'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'profile_expires':p['ExpirationDate'].isoformat(),'registered_device_count':len(p.get('ProvisionedDevices',[])),'testflight_upload':'not evaluated by signature verifier; see testflight-status.json','apple_processing':'see separate TestFlight status report','available_to_testers':'not verified','physical_device_installation':'not verified'}
 ipa.with_suffix('.verification.json').write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({k:v for k,v in report.items() if k not in ('registered_device_count',)},indent=2))
