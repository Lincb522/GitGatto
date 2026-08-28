#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/dist/GitGatto.app}"
OUTPUT="${2:-$ROOT/dist/GitGatto.dmg}"
CODESIGN_IDENTITY="${GITGATTO_CODESIGN_IDENTITY:--}"
SIGNING_KEYCHAIN="${GITGATTO_SIGNING_KEYCHAIN:-}"
VOLUME_NAME="${GITGATTO_DMG_VOLUME_NAME:-GitGatto}"

if [[ ! -d "$APP" || "${APP:e}" != "app" ]]; then
    print -u2 "Expected a macOS app bundle: $APP"
    exit 1
fi

mkdir -p "${OUTPUT:h}"
WORK="$(mktemp -d "${OUTPUT:h}/.GitGatto-dmg.XXXXXX")"
STAGE="$WORK/root"
TEMP_DMG="$WORK/${OUTPUT:t}"

cleanup() {
    [[ -d "$WORK" ]] && rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGE"
ditto "$APP" "$STAGE/${APP:t}"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE" \
    -format UDZO \
    -ov \
    "$TEMP_DMG" >/dev/null

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS=(--force --timestamp --sign "$CODESIGN_IDENTITY")
    if [[ -n "$SIGNING_KEYCHAIN" ]]; then
        SIGN_ARGS+=(--keychain "$SIGNING_KEYCHAIN")
    fi
    codesign $SIGN_ARGS "$TEMP_DMG"
    codesign --verify --strict --verbose=2 "$TEMP_DMG"
fi

hdiutil verify "$TEMP_DMG" >/dev/null
mv -f "$TEMP_DMG" "$OUTPUT"
print "$OUTPUT"
