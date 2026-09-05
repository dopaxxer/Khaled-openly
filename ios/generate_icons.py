#!/usr/bin/env python3
"""Compile all app-icon sizes from the supplied, unchanged logo."""
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'Openly/Assets.xcassets/BrandLogo.imageset/openly-logo.jpg'
OUT = ROOT / 'Openly/Assets.xcassets/AppIcon.appiconset'
SIZES = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
if not SOURCE.is_file():
    sys.exit('Original Openly logo missing; refusing to use a placeholder.')
OUT.mkdir(parents=True, exist_ok=True)
for size in SIZES:
    subprocess.run(['/usr/bin/sips', '-s', 'format', 'png', '-z', str(size), str(size),
                    str(SOURCE), '--out', str(OUT / f'icon-{size}.png')],
                   check=True, stdout=subprocess.DEVNULL)
print(f'Compiled {len(SIZES)} app icons from the supplied Openly logo')
