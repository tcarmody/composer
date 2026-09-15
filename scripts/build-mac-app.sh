#!/usr/bin/env bash
#
# Build, bundle, and sign the Composer macOS app without Xcode.
#
#   scripts/build-mac-app.sh                  # release, host arch, ad-hoc signed
#   scripts/build-mac-app.sh --debug --run    # debug build, then launch it
#   scripts/build-mac-app.sh --universal      # arm64 + x86_64
#   scripts/build-mac-app.sh --sign "Apple Development: you@example.com (TEAMID)"
#
# Requires the Xcode command line tools (swift, actool, codesign) — but not the
# Xcode app, and not xcodegen. Bundle metadata is read out of app/Composer/
# project.yml so this path and the Xcode path can't drift.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$REPO_ROOT/app/Composer"
SOURCE_DIR="$APP_DIR/Composer"

CONFIG="release"
OUT_DIR="$APP_DIR/builds"
IDENTITY="${CODESIGN_IDENTITY:--}"
RUN_AFTER=0
ARCH_FLAGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)     CONFIG="debug"; shift ;;
        --release)   CONFIG="release"; shift ;;
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64); shift ;;
        --run)       RUN_AFTER=1; shift ;;
        --sign)      IDENTITY="$2"; shift 2 ;;
        --output)    OUT_DIR="$2"; shift 2 ;;
        -h|--help)   sed -n '2,15p' "${BASH_SOURCE[0]}" | cut -c3-; exit 0 ;;
        *)           echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- bundle metadata, straight out of project.yml -------------------------

yml_value() {
    sed -n "s/^[[:space:]]*$1:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*\$/\1/p" \
        "$APP_DIR/project.yml" | head -1
}

PRODUCT_NAME="$(yml_value PRODUCT_NAME)"
BUNDLE_ID="$(yml_value PRODUCT_BUNDLE_IDENTIFIER)"
MARKETING_VERSION="$(yml_value MARKETING_VERSION)"
BUILD_VERSION="$(yml_value CURRENT_PROJECT_VERSION)"
DEPLOYMENT_TARGET="$(yml_value MACOSX_DEPLOYMENT_TARGET)"

for var in PRODUCT_NAME BUNDLE_ID MARKETING_VERSION BUILD_VERSION DEPLOYMENT_TARGET; do
    [[ -n "${!var}" ]] || { echo "could not read $var from project.yml" >&2; exit 1; }
done

# --- compile --------------------------------------------------------------

# ${ARCH_FLAGS[@]+...} keeps an empty array from tripping `set -u` on bash 3.2.
spm() {
    swift build --package-path "$APP_DIR" -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} "$@"
}

echo "==> Building $PRODUCT_NAME ($CONFIG)"
spm
BIN_DIR="$(spm --show-bin-path)"

# --- assemble the .app ----------------------------------------------------

APP="$OUT_DIR/$PRODUCT_NAME.app"
CONTENTS="$APP/Contents"
echo "==> Bundling $APP"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$PRODUCT_NAME" "$CONTENTS/MacOS/$PRODUCT_NAME"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Expand the Xcode build-setting placeholders the Info.plist template uses.
sed -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
    -e "s/\$(EXECUTABLE_NAME)/$PRODUCT_NAME/g" \
    -e "s/\$(PRODUCT_NAME)/$PRODUCT_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(MARKETING_VERSION)/$MARKETING_VERSION/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$BUILD_VERSION/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$DEPLOYMENT_TARGET/g" \
    "$SOURCE_DIR/Info.plist" > "$CONTENTS/Info.plist"

# Bake in the repo this app was built from, so BackendSupervisor can find
# venv/ and backend/ on any machine that has a clone.
/usr/libexec/PlistBuddy -c "Add :ComposerProjectRoot string $REPO_ROOT" "$CONTENTS/Info.plist" >/dev/null

# --- asset catalog (app icon) --------------------------------------------

PARTIAL_PLIST="$(mktemp -t composer-assetcatalog)"
trap 'rm -f "$PARTIAL_PLIST"' EXIT

actool "$SOURCE_DIR/Assets.xcassets" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target "$DEPLOYMENT_TARGET" \
    --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    --output-format human-readable-text > /dev/null

# actool reports CFBundleIconFile / CFBundleIconName in a partial plist; fold
# whatever it emitted into the real one.
while IFS= read -r key; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PARTIAL_PLIST")"
    plutil -replace "$key" -string "$value" "$CONTENTS/Info.plist"
done < <(plutil -convert xml1 -o - "$PARTIAL_PLIST" | sed -n 's|.*<key>\(.*\)</key>.*|\1|p')

plutil -lint "$CONTENTS/Info.plist" > /dev/null

# --- sign -----------------------------------------------------------------

echo "==> Signing with identity: $IDENTITY"
TIMESTAMP_FLAG="--timestamp"
[[ "$IDENTITY" == "-" ]] && TIMESTAMP_FLAG="--timestamp=none"

codesign --force --sign "$IDENTITY" \
    --options runtime \
    --entitlements "$SOURCE_DIR/Composer.entitlements" \
    --identifier "$BUNDLE_ID" \
    "$TIMESTAMP_FLAG" \
    "$APP"

codesign --verify --strict --verbose=2 "$APP"

echo "==> Built $APP"
echo "    project root: $REPO_ROOT"

if [[ "$RUN_AFTER" == "1" ]]; then
    echo "==> Launching"
    # -n forces this bundle. Without it LaunchServices can hand the launch to
    # another copy with the same bundle id (e.g. an install in /Applications),
    # and you end up staring at a build you didn't just make.
    open -n "$APP"
fi
