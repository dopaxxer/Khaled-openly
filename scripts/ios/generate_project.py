#!/usr/bin/env python3
"""Generate a deterministic Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[2]/'ios'; objects={}
def uid(value):return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def add(label,isa,**values):
 key=uid(label);objects[key]={'isa':isa,**values};return key
def ref(path,filetype):return add('file:'+path,'PBXFileReference',lastKnownFileType=filetype,path=path,sourceTree='<group>')
def build(file):return add('build:'+file,'PBXBuildFile',fileRef=file)
source=[ref('Openly/'+p.name,'sourcecode.swift') for p in sorted((root/'Openly').glob('*.swift'))]
assets=ref('Openly/Assets.xcassets','folder.assetcatalog');privacy=ref('Openly/PrivacyInfo.xcprivacy','text.xml');info=ref('Openly/Info.plist','text.plist.xml');entitlements=ref('Openly/Openly.entitlements','text.plist.entitlements')
localized=[add('locale:'+lang,'PBXFileReference',lastKnownFileType='text.plist.strings',name=lang,path=f'Openly/{lang}.lproj/InfoPlist.strings',sourceTree='<group>') for lang in ['en','ar']]
variant=add('localized-info','PBXVariantGroup',children=localized,name='InfoPlist.strings',sourceTree='<group>')
project=uid('project');app=uid('target:Openly');test=uid('target:OpenlyTests');uitest=uid('target:OpenlyUITests')
products=[];targets=[]
base={'SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_STRICT_OBJC_MSGSEND':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','GCC_WARN_UNUSED_FUNCTION':'YES','GCC_WARN_UNUSED_VARIABLE':'YES','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','SWIFT_EMIT_LOC_STRINGS':'YES','OPENLY_API_ORIGIN':'https://openly.invalid','OPENLY_BUNDLE_ID':'com.openly.social','DEVELOPMENT_TEAM':'','MARKETING_VERSION':'1.0.0','CURRENT_PROJECT_VERSION':'1','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator'}
def configs(name,settings):
 result=[]
 for mode in ['Debug','Release']:
  values={**settings,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym','ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else ''}
  result.append(add('config:'+name+mode,'XCBuildConfiguration',buildSettings=values,name=mode))
 return add('configs:'+name,'XCConfigurationList',buildConfigurations=result,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
for name,sources,target,kind in [('Openly',source,app,'application'),('OpenlyTests',[ref('OpenlyTests/OpenlyTests.swift','sourcecode.swift')],test,'bundle.unit-test'),('OpenlyUITests',[ref('OpenlyUITests/OpenlyUITests.swift','sourcecode.swift')],uitest,'bundle.ui-testing')]:
 extension='app' if kind=='application' else 'xctest'
 product=add('product:'+name,'PBXFileReference',explicitFileType='wrapper.application' if kind=='application' else 'wrapper.cfbundle',includeInIndex=0,path=name+'.'+extension,sourceTree='BUILT_PRODUCTS_DIR');products.append(product)
 phases=[add('sources:'+name,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=[build(x) for x in sources],runOnlyForDeploymentPostprocessing=0),add('frameworks:'+name,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),add('resources:'+name,'PBXResourcesBuildPhase',buildActionMask=2147483647,files=[build(x) for x in [assets,privacy,variant]] if name=='Openly' else [],runOnlyForDeploymentPostprocessing=0)]
 settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'$(OPENLY_BUNDLE_ID)'+('' if name=='Openly' else '.'+name),'GENERATE_INFOPLIST_FILE':'NO' if name=='Openly' else 'YES'}
 dependencies=[]
 if name=='Openly':settings.update({'INFOPLIST_FILE':'Openly/Info.plist','CODE_SIGN_ENTITLEMENTS':'Openly/Openly.entitlements','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']})
 else:
  proxy=add('proxy:'+name,'PBXContainerItemProxy',containerPortal=project,proxyType=1,remoteGlobalIDString=app,remoteInfo='Openly');dependencies=[add('dependency:'+name,'PBXTargetDependency',target=app,targetProxy=proxy)]
  if name=='OpenlyTests':settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Openly.app/Openly','BUNDLE_LOADER':'$(TEST_HOST)'})
  else:settings['TEST_TARGET_NAME']='Openly'
 objects[target]={'isa':'PBXNativeTarget','buildConfigurationList':configs(name,settings),'buildPhases':phases,'buildRules':[],'dependencies':dependencies,'name':name,'productName':name,'productReference':product,'productType':'com.apple.product-type.'+kind};targets.append(target)
productGroup=add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
allFiles=[key for key,v in objects.items() if v['isa']=='PBXFileReference' and key not in products and key not in localized]
main=add('main','PBXGroup',children=allFiles+[variant,productGroup],sourceTree='<group>')
objects[project]={'isa':'PBXProject','attributes':{'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1640','TargetAttributes':{app:{'CreatedOnToolsVersion':'16.4'},test:{'CreatedOnToolsVersion':'16.4','TestTargetID':app},uitest:{'CreatedOnToolsVersion':'16.4','TestTargetID':app}}},'buildConfigurationList':configs('project',base),'compatibilityVersion':'Xcode 14.0','developmentRegion':'en','hasScannedForEncodings':0,'knownRegions':['en','ar','Base'],'mainGroup':main,'productRefGroup':productGroup,'projectDirPath':'','projectRoot':'','targets':targets}
def render(value,level=0):
 if isinstance(value,dict):return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+' = '+render(v,level+1)+';\n' for k,v in value.items())+'\t'*level+'}'
 if isinstance(value,list):return '('+', '.join(render(v,level) for v in value)+')'
 if isinstance(value,int):return str(value)
 return json.dumps(value,ensure_ascii=False)
folder=root/'Openly.xcodeproj';folder.mkdir(exist_ok=True);(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+render({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
schemes=folder/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def br(target,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.{"app" if name=="Openly" else "xctest"}" BlueprintName="{name}" ReferencedContainer="container:Openly.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="1640" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{br(app,'Openly')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{br(test,'OpenlyTests')}</TestableReference><TestableReference skipped="NO">{br(uitest,'OpenlyUITests')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{br(app,'Openly')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{br(app,'Openly')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(schemes/'Openly.xcscheme').write_text(scheme+'\n');print('Generated Openly.xcodeproj with app, unit test, and UI test targets.')
