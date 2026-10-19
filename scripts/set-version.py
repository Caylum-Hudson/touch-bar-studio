#!/usr/bin/env python3
"""Update release metadata without creating commits, tags or releases."""
import json
import plistlib
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
if len(sys.argv) != 2 or not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', sys.argv[1]):
    raise SystemExit('Usage: python3 scripts/set-version.py MAJOR.MINOR.PATCH')
version = sys.argv[1]
package_path = root / 'package.json'
lock_path = root / 'package-lock.json'
plist_path = root / 'mtmr-src/MTMR/Info.plist'
package = json.loads(package_path.read_text())
lock = json.loads(lock_path.read_text())
info = plistlib.loads(plist_path.read_bytes())
previous_version = package['version']
previous_build = int(info.get('CFBundleVersion', '0'))
package['version'] = version
lock['version'] = version
lock['packages']['']['version'] = version
info['CFBundleShortVersionString'] = version
# The shipped native build and source plist use the same build number.
info['CFBundleVersion'] = str(previous_build + (version != previous_version))
package_path.write_text(json.dumps(package, indent=2) + '\n')
lock_path.write_text(json.dumps(lock, indent=2) + '\n')
plist_path.write_bytes(plistlib.dumps(info, sort_keys=False))
print(f'Version set to {version}. Build and verify before tagging v{version}.')
