#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="config/base.xcconfig"
APP_NAME="${APP_NAME:-$(awk -F= '/^PRODUCT_NAME/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG")}"
BUNDLE_ID="${BUNDLE_ID:-$(awk -F= '/^PRODUCT_BUNDLE_IDENTIFIER/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG")}"
CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-Release}"
DERIVED_DATA_ROOT="${DERIVED_DATA_ROOT:-$HOME/Library/Developer/Xcode/DerivedData}"
INSTALL_PATH="/Applications/${APP_NAME}.app"

find_newest_product() {
    local suffix="$1"
    find "$DERIVED_DATA_ROOT" -path "*/Build/Products/${CONFIGURATION}/${suffix}" -prune -print0 2>/dev/null \
        | xargs -0 stat -f "%m %N" 2>/dev/null \
        | sort -nr \
        | sed -n '1s/^[0-9]* //p' \
        || true
}

archive_dsym() {
    local dsym uuid archive_dir
    dsym="$(find_newest_product "${APP_NAME}.app.dSYM")"
    [[ -n "$dsym" ]] || return 0
    uuid="$(dwarfdump --uuid "$dsym" 2>/dev/null | awk '/arm64/ { print $2; exit }')"
    [[ -n "$uuid" ]] || return 0
    archive_dir="$HOME/Library/Logs/${APP_NAME}/dsyms/${uuid}"
    mkdir -p "$archive_dir"
    rm -rf "${archive_dir}/${APP_NAME}.app.dSYM"
    cp -R "$dsym" "$archive_dir/"
}

echo "Building ${APP_NAME} (${CONFIGURATION})"
xcodebuild \
    -workspace alt-tab-macos.xcworkspace \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    build \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM=""

APP_PATH="$(find_newest_product "${APP_NAME}.app")"
[[ -n "$APP_PATH" ]] || { echo "Built app not found under ${DERIVED_DATA_ROOT}" >&2; exit 1; }

echo "Archiving dSYM"
archive_dsym

echo "Stopping ${APP_NAME}"
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -f "$INSTALL_PATH" 2>/dev/null || true
sleep 1

echo "Resetting TCC and reinstalling ${INSTALL_PATH}"
tccutil reset All "$BUNDLE_ID" || true
defaults delete "$BUNDLE_ID" NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints 2>/dev/null || true
rm -rf "$INSTALL_PATH"
ditto "$APP_PATH" "$INSTALL_PATH"

echo "Launching ${APP_NAME}"
open "$INSTALL_PATH"
echo "macOS should prompt again for Accessibility and Screen Recording. If Screen Recording does not prompt, add ${APP_NAME} manually in System Settings."
