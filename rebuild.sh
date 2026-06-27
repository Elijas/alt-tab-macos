#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="config/base.xcconfig"
APP_NAME="${APP_NAME:-$(awk -F= '/^PRODUCT_NAME/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG")}"
BUNDLE_ID="${BUNDLE_ID:-$(awk -F= '/^PRODUCT_BUNDLE_IDENTIFIER/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG")}"
CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-Release}"
# Project-local DerivedData: eliminates the multi-hash-dir ambiguity in Xcode's
# default ~/Library/.../DerivedData layout. With a fixed -derivedDataPath, the
# script always knows exactly where the build output lives — no need to "pick
# newest" across hash directories that accumulate after Xcode upgrades.
# Already covered by .gitignore (/DerivedData/).
DERIVED_DATA_PATH="$(pwd)/DerivedData"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
DSYM_PATH="${APP_PATH}.dSYM"
INSTALL_PATH="/Applications/${APP_NAME}.app"

archive_dsym() {
    local uuid archive_dir
    [[ -d "$DSYM_PATH" ]] || return 0
    uuid="$(dwarfdump --uuid "$DSYM_PATH" 2>/dev/null | awk '/arm64/ { print $2; exit }')"
    [[ -n "$uuid" ]] || return 0
    archive_dir="$HOME/Library/Logs/${APP_NAME}/dsyms/${uuid}"
    mkdir -p "$archive_dir"
    rm -rf "${archive_dir}/${APP_NAME}.app.dSYM"
    cp -R "$DSYM_PATH" "$archive_dir/"
}

echo "Building ${APP_NAME} (${CONFIGURATION}) -> ${DERIVED_DATA_PATH}"
xcodebuild \
    -project alt-tab-macos.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM=""

[[ -d "$APP_PATH" ]] || { echo "Built app not found at ${APP_PATH}" >&2; exit 1; }

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
