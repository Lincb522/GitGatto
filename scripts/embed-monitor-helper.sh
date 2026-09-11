#!/bin/zsh
set -euo pipefail

APP="${1:?Expected the built GitGatto.app path}"
IDENTITY="${GITGATTO_CODESIGN_IDENTITY:--}"
HELPER="$APP/Contents/Library/LoginItems/GitGattoMonitor.app"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/GitGattoMonitor.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/GitGattoMonitor.app"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == dev.gitgatto.client ]]
mkdir -p "$BUNDLE/Contents"
ditto "$APP/Contents/MacOS" "$BUNDLE/Contents/MacOS"
mv "$BUNDLE/Contents/MacOS/GitGatto" "$BUNDLE/Contents/MacOS/GitGattoMonitor"
ditto "$APP/Contents/Resources" "$BUNDLE/Contents/Resources"
ditto "$APP/Contents/Frameworks" "$BUNDLE/Contents/Frameworks"
python3 - "$APP/Contents/Info.plist" "$BUNDLE/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as handle:
    parent = plistlib.load(handle)
info = {key: parent[key] for key in [
    'CFBundleShortVersionString', 'CFBundleVersion', 'LSMinimumSystemVersion',
    'CFBundleDevelopmentRegion', 'CFBundleLocalizations'
] if key in parent}
info.update(CFBundleIdentifier='dev.gitgatto.monitor', CFBundleName='GitGatto Monitor',
            CFBundleDisplayName='GitGatto Monitor', CFBundleExecutable='GitGattoMonitor',
            CFBundlePackageType='APPL', LSUIElement=True, NSHighResolutionCapable=True,
            CFBundleIconFile='AppIcon')
with open(sys.argv[2], 'wb') as handle:
    plistlib.dump(info, handle)
PY

SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--timestamp --options runtime)
    [[ -z "${GITGATTO_SIGNING_KEYCHAIN:-}" ]] || SIGN_ARGS+=(--keychain "$GITGATTO_SIGNING_KEYCHAIN")
fi
# Xcode Debug uses an executable stub with sibling runtime dylibs, signed after this build phase.
for library in "$BUNDLE/Contents/MacOS/"*.dylib(N); do
    codesign "${SIGN_ARGS[@]}" "$library"
done
# Nested frameworks keep the signing and entitlements already applied by the parent build.
codesign "${SIGN_ARGS[@]}" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
mkdir -p "${HELPER:h}"
rm -rf "$HELPER"
ditto "$BUNDLE" "$HELPER"
codesign --verify --deep --strict "$HELPER"
