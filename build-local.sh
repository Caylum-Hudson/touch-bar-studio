#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if pgrep -x TouchBarStudio >/dev/null 2>&1; then
 echo 'Close Touch Bar Studio before rebuilding.' >&2
 exit 1
fi
NODE_EXECUTABLE=$(command -v node || true)
if [ -z "$NODE_EXECUTABLE" ]; then
 NODE_EXECUTABLE="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
fi
if [ ! -x "$NODE_EXECUTABLE" ] || [ ! -d node_modules ]; then
 echo 'Install Node.js and run npm ci --ignore-scripts first.' >&2
 exit 1
fi
"$NODE_EXECUTABLE" local-build/check-state.mjs
"$NODE_EXECUTABLE" local-build/check-controls.mjs
"$NODE_EXECUTABLE" node_modules/vite/bin/vite.js build
./local-build/build-native.sh
"../Touch Bar Studio.app/Contents/MacOS/TouchBarStudio" --self-test

"../Touch Bar Studio.app/Contents/MacOS/TouchBarStudio" --control-self-test local-build/control-fixtures.generated.json
