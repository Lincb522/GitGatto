#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/dist/GitGatto.app}"
OUTPUT_DMG="${2:-$ROOT/dist/GitGatto.dmg}"
CODESIGN_IDENTITY="${GITGATTO_CODESIGN_IDENTITY:-}"
NOTARIZATION_DIR="${GITGATTO_NOTARIZATION_DIR:-${OUTPUT_DMG:h}/notarization}"

for variable in \
    CODESIGN_IDENTITY \
    APP_STORE_CONNECT_KEY_PATH \
    APP_STORE_CONNECT_KEY_ID \
    APP_STORE_CONNECT_ISSUER_ID
do
    if [[ -z "${(P)variable:-}" ]]; then
        print -u2 "$variable is required."
        exit 1
    fi
done

if [[ ! -f "$APP_STORE_CONNECT_KEY_PATH" ]]; then
    print -u2 "App Store Connect private key not found: $APP_STORE_CONNECT_KEY_PATH"
    exit 1
fi

NOTARYTOOL_CREDENTIALS=(
    --key "$APP_STORE_CONNECT_KEY_PATH"
    --key-id "$APP_STORE_CONNECT_KEY_ID"
    --issuer "$APP_STORE_CONNECT_ISSUER_ID"
)

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    print -u2 "A Developer ID Application identity is required."
    exit 1
fi

if [[ ! -d "$APP" ]]; then
    print -u2 "App bundle not found: $APP"
    exit 1
fi

mkdir -p "$NOTARIZATION_DIR" "${OUTPUT_DMG:h}"
WORK="$(mktemp -d "${OUTPUT_DMG:h}/.GitGatto-notary.XXXXXX")"
APP_ZIP="$WORK/GitGatto.app.zip"

cleanup() {
    [[ -d "$WORK" ]] && rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

submit_and_wait() {
    local artifact="$1"
    local name="$2"
    local result="$NOTARIZATION_DIR/$name.json"
    local log="$NOTARIZATION_DIR/$name-log.json"

    if ! xcrun notarytool submit "$artifact" \
        "${NOTARYTOOL_CREDENTIALS[@]}" \
        --wait \
        --timeout 45m \
        --output-format json >"$result"; then
        print -u2 "Apple notarization submission failed for ${artifact:t}."
        return 1
    fi

    local notary_status
    local submission_id
    notary_status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", ""))' "$result")"
    submission_id="$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$result")"

    if [[ "$notary_status" != "Accepted" ]]; then
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" \
                "${NOTARYTOOL_CREDENTIALS[@]}" \
                "$log" || true
        fi
        print -u2 "Apple notarization status for ${artifact:t}: ${notary_status:-unknown}"
        return 1
    fi
}

codesign --verify --deep --strict "$APP"
CODESIGN_DETAILS="$(codesign -d --verbose=4 "$APP" 2>&1)"
grep -q '^Authority=Developer ID Application:' <<< "$CODESIGN_DETAILS"
grep -q '^Runtime Version=' <<< "$CODESIGN_DETAILS"

ditto -c -k --keepParent --rsrc "$APP" "$APP_ZIP"
submit_and_wait "$APP_ZIP" app
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

GITGATTO_CODESIGN_IDENTITY="$CODESIGN_IDENTITY" \
    "$ROOT/scripts/create-dmg.sh" "$APP" "$OUTPUT_DMG" >/dev/null

submit_and_wait "$OUTPUT_DMG" dmg
xcrun stapler staple "$OUTPUT_DMG"
xcrun stapler validate "$OUTPUT_DMG"
codesign --verify --strict --verbose=2 "$OUTPUT_DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$OUTPUT_DMG"
hdiutil verify "$OUTPUT_DMG" >/dev/null

print "$OUTPUT_DMG"
