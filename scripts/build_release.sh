#!/bin/bash
#
# build_release.sh — Build, sign, notarize, and package Logue for distribution.
#
# Usage:
#   ./scripts/build_release.sh [--version X.Y.Z] [--build N] [--team-id XXXXXXXXXX]
#                              [--keychain-profile NAME] [--skip-notarize]
#
# Prerequisites:
#   - Xcode with Metal Toolchain installed
#   - Developer ID Application certificate in Keychain
#   - XcodeGen installed (brew install xcodegen)
#   - create-dmg installed (brew install create-dmg)
#   - Notarization credentials stored (xcrun notarytool store-credentials "Logue-Notarize")
#
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_YML="$PROJECT_ROOT/project.yml"
SCHEME="Logue"

# Build directories
BUILD_DIR="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Logue.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS_TEMPLATE="$SCRIPT_DIR/ExportOptions.plist"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
ENTITLEMENTS="$PROJECT_ROOT/Logue/Resources/Logue.entitlements"

# Notarization keychain profile name
NOTARIZE_PROFILE="Logue-Notarize"

# ── Parse Arguments ───────────────────────────────────────────────────────────
VERSION=""
BUILD_NUMBER=""
TEAM_ID=""
SKIP_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)       VERSION="$2";       shift 2 ;;
        --build)         BUILD_NUMBER="$2";  shift 2 ;;
        --team-id)            TEAM_ID="$2";          shift 2 ;;
        --keychain-profile)  NOTARIZE_PROFILE="$2"; shift 2 ;;
        --skip-notarize)     SKIP_NOTARIZE=true;    shift ;;
        --help|-h)
            echo "Usage: $0 [--version X.Y.Z] [--build N] [--team-id XXXXXXXXXX] [--keychain-profile NAME] [--skip-notarize]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Read defaults from project.yml if not provided ────────────────────────────
if [[ -z "$VERSION" ]]; then
    VERSION=$(grep 'MARKETING_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    echo "Using version from project.yml: $VERSION"
fi

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | sed 's/.*: *"\(.*\)"/\1/')
    echo "Using build number from project.yml: $BUILD_NUMBER"
fi

if [[ -z "$TEAM_ID" ]]; then
    TEAM_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*(\(.*\))/\1/' || true)
    if [[ -z "$TEAM_ID" ]]; then
        echo "ERROR: No --team-id provided and no Developer ID certificate found in Keychain."
        echo "Usage: $0 --team-id YOUR_TEAM_ID"
        exit 1
    fi
    echo "Auto-detected Team ID from Keychain: $TEAM_ID"
fi

DMG_NAME="Logue-${VERSION}.dmg"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Logue Release Build"
echo "  Version: $VERSION ($BUILD_NUMBER)"
echo "  Team ID: $TEAM_ID"
echo "═══════════════════════════════════════════════════════"

# ── Step 0: Prerequisites ─────────────────────────────────────────────────────
echo ""
echo "▸ Checking prerequisites..."

command -v xcodegen >/dev/null 2>&1 || { echo "ERROR: xcodegen not found. Install with: brew install xcodegen"; exit 1; }
command -v create-dmg >/dev/null 2>&1 || { echo "ERROR: create-dmg not found. Install with: brew install create-dmg"; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "ERROR: xcrun not found. Xcode Command Line Tools required."; exit 1; }

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "ERROR: No 'Developer ID Application' certificate found in Keychain."
    exit 1
fi

SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
echo "  Signing identity: $SIGNING_IDENTITY"

# ── Step 1: Clean Build Directory ─────────────────────────────────────────────
echo ""
echo "▸ Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Step 2: Prepare ExportOptions.plist ───────────────────────────────────────
echo ""
echo "▸ Preparing ExportOptions.plist..."
sed "s/__TEAM_ID__/$TEAM_ID/g" "$EXPORT_OPTIONS_TEMPLATE" > "$EXPORT_OPTIONS"

# ── Step 3: Install Metal Toolchain ───────────────────────────────────────────
echo ""
echo "▸ Ensuring Metal Toolchain is available..."
xcodebuild -downloadComponent MetalToolchain 2>/dev/null || true

# ── Step 4: Generate Xcode Project ────────────────────────────────────────────
echo ""
echo "▸ Generating Xcode project from project.yml..."
cd "$PROJECT_ROOT"
xcodegen generate --spec "$PROJECT_YML"

# ── Step 5: Resolve SPM Dependencies ─────────────────────────────────────────
echo ""
echo "▸ Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies \
    -project Logue.xcodeproj \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages"

# ── Step 6: Archive ──────────────────────────────────────────────────────────
echo ""
echo "▸ Archiving Logue (Release)..."
xcodebuild archive \
    -project Logue.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -archivePath "$ARCHIVE_PATH" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    ARCHS=arm64 \
    OTHER_CODE_SIGN_FLAGS="--options=runtime"

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Archive failed. Check build output above."
    exit 1
fi
echo "  Archive created at: $ARCHIVE_PATH"

# ── Step 7: Export Archive ────────────────────────────────────────────────────
echo ""
echo "▸ Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/Logue.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: Export failed. No .app found in $EXPORT_DIR"
    exit 1
fi
echo "  Exported app: $APP_PATH"

# ── Step 8: Deep Codesign with Hardened Runtime ───────────────────────────────
echo ""
echo "▸ Deep-signing app bundle with hardened runtime..."

# Sign all frameworks and dylibs first
find "$APP_PATH/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null | while read -r framework; do
    echo "  Signing: $(basename "$framework")"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
        --timestamp "$framework"
done

# Sign all helper executables (excluding main binary)
find "$APP_PATH/Contents/MacOS" -type f -perm +111 ! -name "Logue" 2>/dev/null | while read -r helper; do
    echo "  Signing helper: $(basename "$helper")"
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
        --timestamp "$helper"
done

# Sign the main app bundle
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$APP_PATH"

echo ""
echo "  Verifying codesign..."
codesign --verify --verbose=2 "$APP_PATH"

echo ""
echo "  Checking Gatekeeper acceptance..."
spctl --assess --type exec --verbose "$APP_PATH" 2>&1 || echo "  (spctl may fail until notarization is complete — this is expected)"

# ── Step 9: Create Styled DMG ────────────────────────────────────────────────
echo ""
echo "▸ Creating styled DMG..."
DMG_PATH="$BUILD_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

CREATE_DMG_ARGS=(
    --volname "Logue $VERSION"
    --window-pos 200 120
    --window-size 660 400
    --icon-size 80
    --icon "Logue.app" 180 190
    --app-drop-link 480 190
    --hide-extension "Logue.app"
    --no-internet-enable
)

# Add volume icon if app icon exists
if [[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]]; then
    CREATE_DMG_ARGS+=(--volicon "$APP_PATH/Contents/Resources/AppIcon.icns")
fi

# Add background image if it exists
if [[ -f "$SCRIPT_DIR/dmg_background.png" ]]; then
    CREATE_DMG_ARGS+=(--background "$SCRIPT_DIR/dmg_background.png")
fi

# create-dmg returns exit code 2 for cosmetic icon issues — treat as warning
create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_PATH" "$APP_PATH" || {
    exit_code=$?
    if [[ $exit_code -eq 2 ]]; then
        echo "  Warning: DMG created but icon positioning may not be perfect."
    else
        echo "ERROR: Failed to create DMG (exit code $exit_code)"
        exit 1
    fi
}

# Sign the DMG
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
echo "  DMG created: $DMG_PATH"

# ── Step 10: Notarize ────────────────────────────────────────────────────────
if [[ "$SKIP_NOTARIZE" == "true" ]]; then
    echo ""
    echo "▸ Skipping notarization (--skip-notarize flag)"
else
    echo ""
    echo "▸ Submitting DMG for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait \
        --timeout 45m

    echo ""
    echo "▸ Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"

    echo ""
    echo "▸ Verifying notarization..."
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  BUILD COMPLETE"
echo ""
echo "  App:     $APP_PATH"
echo "  DMG:     $DMG_PATH"
echo "  Version: $VERSION ($BUILD_NUMBER)"
echo "═══════════════════════════════════════════════════════"
