#!/usr/bin/env python3
"""Validate the shipped archive itself, not just the build directory."""
import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path, PurePosixPath


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inspect_executable(binary):
    require(len(binary) >= 32, 'Executable is missing or truncated')
    magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', binary)
    require(magic == 0xFEEDFACF, 'Expected a 64-bit Mach-O device executable')
    require(cpu == 0x0100000C, 'Expected an arm64 executable')
    require(filetype == 2, 'Mach-O is not an application executable')
    require(ncmds > 0 and 32 + sizeofcmds <= len(binary), 'Invalid Mach-O load commands')
    offset = 32
    device_platform = False
    for _ in range(ncmds):
        require(offset + 8 <= 32 + sizeofcmds, 'Truncated load command')
        cmd, size = struct.unpack_from('<II', binary, offset)
        require(size >= 8 and offset + size <= 32 + sizeofcmds, 'Invalid load command size')
        if cmd == 0x32:  # LC_BUILD_VERSION: PLATFORM_IOS=2, IOSSIMULATOR=7
            require(size >= 24, 'Truncated platform load command')
            require(struct.unpack_from('<I', binary, offset + 8)[0] == 2,
                    'Executable targets a simulator or a non-iOS platform')
            device_platform = True
        offset += size
    require(device_platform, 'Missing iOS device platform declaration')
    return {'format': 'Mach-O 64-bit', 'architecture': 'arm64', 'platform': 'iOS device'}


def verify(path, expected_build):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, 'Archive integrity check failed')
        names = archive.namelist()
        require(len(names) == len(set(names)), 'Archive contains duplicate paths')
        require(all(not n.startswith('/') and '..' not in PurePosixPath(n).parts for n in names),
                'Archive contains unsafe paths')
        prefix = 'Payload/Openly.app/'
        require(prefix + 'Info.plist' in names, 'Missing Payload/Openly.app/Info.plist')
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        require(info.get('CFBundleIdentifier') == 'ink.openly.app', 'Wrong bundle identifier')
        require(str(info.get('CFBundleVersion')) == str(expected_build), 'Wrong app build number')
        require(info.get('CFBundlePackageType') == 'APPL', 'Bundle is not an application')
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneOS'], 'Bundle is not for iPhoneOS')
        require(info.get('OpenlyAPIBaseURL') == 'https://openly.nootjetzt.workers.dev/api/', 'Wrong API endpoint')
        executable = info.get('CFBundleExecutable', '')
        require(executable and '/' not in executable, 'Invalid CFBundleExecutable')
        item = archive.getinfo(prefix + executable)
        require((item.external_attr >> 16) & 0o111, 'Executable permission was lost during packaging')
        binary = archive.read(item)
        details = inspect_executable(binary)
        require(prefix + 'Assets.car' in names, 'Missing compiled asset catalog')
        require(archive.getinfo(prefix + 'Assets.car').file_size > 0, 'Compiled asset catalog is empty')
        require(any(n.startswith(prefix + 'LaunchScreen.storyboardc/') for n in names), 'Missing launch screen')
        for language in ['ar', 'en']:
            require(prefix + language + '.lproj/Localizable.strings' in names, f'Missing {language} localization')
        require(info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconFiles'), 'Missing app icon declaration')
        require(prefix + 'embedded.mobileprovision' not in names, 'Unsigned build unexpectedly includes a provisioning profile')
        entries = [{'path': i.filename, 'bytes': i.file_size} for i in archive.infolist() if not i.is_dir()]
        return {
            'bundleId': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
            'build': info['CFBundleVersion'], 'minimumIOS': info.get('MinimumOSVersion'),
            'ipaBytes': path.stat().st_size, 'uncompressedBytes': sum(i['bytes'] for i in entries),
            'executableBytes': len(binary), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'signing': 'unsigned — requires signing and provisioning before device installation',
            'checks': ['ZIP integrity', 'arm64 Mach-O', 'iOS device platform', 'bundle metadata',
                       'executable permission', 'compiled assets', 'app icons', 'launch screen', 'Arabic and English resources'],
            **details, 'files': entries,
        }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--build', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.ipa, args.build)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'files'}, indent=2, ensure_ascii=False))
