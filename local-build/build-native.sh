#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/local-build"
APP="$ROOT/../Touch Bar Studio.app"
mkdir -p "$OUT/objects" "$OUT/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Resources/WebApp"
SDK=$(xcrun --show-sdk-path)
for SRC in mtmr-src/MTMR/CBridge/*.m mtmr-src/MTMR/CBridge/*.c; do
 clang -w -fmodules -fmodules-cache-path="$OUT/module-cache" -isysroot "$SDK" -fobjc-arc -c "$SRC" -o "$OUT/objects/$(basename "$SRC").o"
done
find mtmr-src/MTMR -name '*.swift' -not -path '*/WebApp/*' -print0 | xargs -0 swiftc -swift-version 5 -module-cache-path "$OUT/module-cache" -import-objc-header mtmr-src/MTMR/CBridge/TouchBarPrivateApi-Bridging.h -F "$SDK/System/Library/PrivateFrameworks" -framework Cocoa -framework WebKit -framework Carbon -framework IOKit -framework DFRFoundation -framework MultitouchSupport -framework CoreDisplay -framework CoreBrightness "$OUT"/objects/*.o -o "$APP/Contents/MacOS/TouchBarStudio" 2> "$OUT/compiler.log"
cp -R dist/. "$APP/Contents/Resources/WebApp/"
cp mtmr-src/MTMR/defaultPreset.json "$APP/Contents/Resources/"
find mtmr-src/MTMR/Assets.xcassets -type f \( -name '*.png' -o -name '*.pdf' \) -exec cp {} "$APP/Contents/Resources/" \;
python3 - "$APP" <<'PY'
import json,plistlib,sys
from pathlib import Path
app=Path(sys.argv[1])
version=json.loads(Path('package.json').read_text())['version']
source_info=plistlib.loads(Path('mtmr-src/MTMR/Info.plist').read_bytes())
if source_info['CFBundleShortVersionString'] != version:
 raise SystemExit('Version mismatch. Run npm run version:set -- ' + version)
info=dict(CFBundleExecutable='TouchBarStudio',CFBundleIdentifier='nz.caylum.touchbarstudio',CFBundleName='Touch Bar Studio',CFBundleVersion=source_info['CFBundleVersion'],CFBundleShortVersionString=version,CFBundlePackageType='APPL',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True,NSAppleEventsUsageDescription='User-configured controls can send commands to other apps.',NSCalendarsUsageDescription='Optional calendar widget.',NSLocationWhenInUseUsageDescription='Optional weather widget.')
info['NSServices']=[{'NSMenuItem':{'default':'Open in Photo Workspace'},'NSMessage':'openPhotoWorkspace','NSPortName':'Touch Bar Studio','NSSendTypes':['NSFilenamesPboardType','public.file-url'],'NSRequiredContext':{'NSServiceCategory':'public.image'}}]
info['CFBundleDocumentTypes']=[{'CFBundleTypeName':'Photo files','CFBundleTypeRole':'Viewer','LSHandlerRank':'Alternate','LSItemContentTypes':['public.image','public.folder']}]
import shutil
for folder in Path('mtmr-src/MTMR/Assets.xcassets').glob('*.imageset'):
 for image in folder.iterdir():
  if image.suffix.lower() in ['.png','.pdf']:
   shutil.copy2(image,app/'Contents/Resources'/(folder.stem+image.suffix))
   break
info['CFBundleIconFile']='AppIcon'
iconset=Path('local-build/AppIcon.iconset'); iconset.mkdir(exist_ok=True)
for size in [16,32,128,256,512]:
 for scale in [1,2]:
  image=Path(f'mtmr-src/MTMR/Assets.xcassets/AppIcon.appiconset/logo-{size*scale}.png')
  if image.exists(): shutil.copy2(image,iconset/f'icon_{size}x{size}{"@2x" if scale==2 else ""}.png')
import struct
chunks=[]
for tag,size in [('icp4',16),('icp5',32),('icp6',64),('ic07',128),('ic08',256),('ic09',512),('ic10',1024)]:
 data=Path(f'mtmr-src/MTMR/Assets.xcassets/AppIcon.appiconset/logo-{size}.png').read_bytes()
 chunks.append(tag.encode()+struct.pack('>I',len(data)+8)+data)
body=b''.join(chunks)
(app/'Contents/Resources/AppIcon.icns').write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
cp mtmr-src/LICENSE "$APP/Contents/Resources/MTMR-LICENSE.txt"
codesign --force --deep --sign - "$APP"
echo "$APP"
