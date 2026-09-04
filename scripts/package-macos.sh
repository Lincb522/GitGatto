#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="${1:-$ROOT/dist}"
FINAL_APP="$OUTPUT_DIR/GitGatto.app"
STAGE_ROOT=""
BACKUP_APP="$OUTPUT_DIR/.GitGatto.previous"
# project.yml is the single source of truth for the default version and build number.
DEFAULT_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9.]+)"?.*/\1/p' "$ROOT/project.yml" | head -n 1)"
DEFAULT_BUILD="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"?([0-9]+)"?.*/\1/p' "$ROOT/project.yml" | head -n 1)"
VERSION="${GITGATTO_VERSION:-$DEFAULT_VERSION}"
BUILD="${GITGATTO_BUILD_NUMBER:-$DEFAULT_BUILD}"
FEED_URL="${GITGATTO_UPDATE_FEED_URL:-https://github.com/Lincb522/GitGatto/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${GITGATTO_SPARKLE_PUBLIC_KEY:-}"
CODESIGN_IDENTITY="${GITGATTO_CODESIGN_IDENTITY:--}"
SIGNING_KEYCHAIN="${GITGATTO_SIGNING_KEYCHAIN:-}"
ENTITLEMENTS="$ROOT/Config/GitGatto.entitlements"
ICON_MASTER="$ROOT/Assets/GitGatto-AppIcon.svg"

if [[ "$FEED_URL" != https://* ]]; then
    print -u2 "GITGATTO_UPDATE_FEED_URL must use HTTPS."
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    print -u2 "Missing entitlements file: $ENTITLEMENTS"
    exit 1
fi

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "GITGATTO_VERSION must use major.minor.patch."
    exit 1
fi

if [[ ! "$BUILD" =~ '^[0-9]+$' ]]; then
    print -u2 "GITGATTO_BUILD_NUMBER must be numeric."
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
STAGE_ROOT="$(mktemp -d "$OUTPUT_DIR/.GitGatto-stage.XXXXXX")"
APP="$STAGE_ROOT/GitGatto.app"
ICON_WORK="$STAGE_ROOT/GitGatto.iconset"

cleanup() {
    [[ -n "$STAGE_ROOT" && -d "$STAGE_ROOT" ]] && rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT INT TERM

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$ICON_WORK"

swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --show-bin-path)"

cp "$BIN_DIR/GitGatto" "$APP/Contents/MacOS/GitGatto"
ditto "$BIN_DIR/GitGatto_GitGatto.bundle" "$APP/Contents/Resources/GitGatto_GitGatto.bundle"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/GitGatto"

render_icon() {
    local size="$1"
    local destination="$2"
    sips -s format png -z "$size" "$size" "$ICON_MASTER" --out "$ICON_WORK/$destination" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICON_WORK" -o "$APP/Contents/Resources/AppIcon.icns"

/usr/bin/python3 - "$APP/Contents/Info.plist" "$VERSION" "$BUILD" "$FEED_URL" "$SPARKLE_PUBLIC_KEY" <<'PY'
import plistlib
import sys

path, version, build, feed_url, sparkle_public_key = sys.argv[1:]
info = {
    "CFBundleExecutable": "GitGatto",
    "CFBundleIdentifier": "dev.gitgatto.client",
    "CFBundleName": "GitGatto",
    "CFBundleDisplayName": "GitGatto",
    "CFBundlePackageType": "APPL",
    "CFBundleDevelopmentRegion": "en",
    "CFBundleLocalizations": [
        "en", "zh-Hans", "zh-Hant", "ja", "ko", "fr",
        "de", "es", "pt-BR", "ru", "ar",
    ],
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "CFBundleIconFile": "AppIcon",
    "LSMinimumSystemVersion": "14.0",
    "NSAppleEventsUsageDescription": (
        "GitGatto opens Terminal to run the GitHub CLI login command "
        "so you can sign in to GitHub."
    ),
    "NSHighResolutionCapable": True,
    "SUFeedURL": feed_url,
    "SUEnableAutomaticChecks": False,
    "SUAutomaticallyUpdate": False,
}
if sparkle_public_key:
    info["SUPublicEDKey"] = sparkle_public_key
with open(path, "wb") as handle:
    plistlib.dump(info, handle, sort_keys=False)
PY

chmod +x "$APP/Contents/MacOS/GitGatto"
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP"
    codesign --force --sign - --entitlements "$ENTITLEMENTS" \
        -r='designated => identifier "dev.gitgatto.client"' "$APP"
else
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
    SPARKLE_VERSION="$SPARKLE/Versions/B"
    SIGN_ARGS=(--force --timestamp --options runtime --sign "$CODESIGN_IDENTITY")
    if [[ -n "$SIGNING_KEYCHAIN" ]]; then
        SIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
    fi

    codesign $SIGN_ARGS "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    codesign $SIGN_ARGS --preserve-metadata=entitlements "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    codesign $SIGN_ARGS "$SPARKLE_VERSION/Autoupdate"
    codesign $SIGN_ARGS "$SPARKLE_VERSION/Updater.app"
    codesign $SIGN_ARGS "$SPARKLE"
    codesign $SIGN_ARGS --entitlements "$ENTITLEMENTS" "$APP"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | grep -q 'com.apple.security.automation.apple-events'
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --verify --deep --strict -R='identifier "dev.gitgatto.client"' "$APP"
else
    CODESIGN_DETAILS="$(codesign -d --verbose=4 "$APP" 2>&1)"
    grep -q '^Authority=Developer ID Application:' <<< "$CODESIGN_DETAILS"
    grep -q '^Runtime Version=' <<< "$CODESIGN_DETAILS"
fi
ARCHS="$(lipo -archs "$APP/Contents/MacOS/GitGatto")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]
otool -L "$APP/Contents/MacOS/GitGatto" | grep -q '@rpath/Sparkle.framework'
otool -l "$APP/Contents/MacOS/GitGatto" | grep -q '@executable_path/../Frameworks'
[[ -x "$APP/Contents/Frameworks/Sparkle.framework/Versions/Current/Sparkle" ]]
[[ -f "$APP/Contents/Resources/GitGatto_GitGatto.bundle/Contents/Resources/en.lproj/UserAgreement.md" ]]
[[ -f "$APP/Contents/Resources/GitGatto_GitGatto.bundle/Contents/Resources/zh-Hans.lproj/UserAgreement.md" ]]

rm -rf "$BACKUP_APP"
if [[ -e "$FINAL_APP" ]]; then
    mv "$FINAL_APP" "$BACKUP_APP"
fi
if ! mv "$APP" "$FINAL_APP"; then
    [[ -e "$BACKUP_APP" ]] && mv "$BACKUP_APP" "$FINAL_APP"
    exit 1
fi
rm -rf "$BACKUP_APP"

print "$FINAL_APP"
