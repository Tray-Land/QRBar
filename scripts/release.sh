#!/usr/bin/env bash
# Build, sign (Developer ID), notarize, and publish QRBar to GitHub Releases.
#
# Usage: scripts/release.sh [--draft] [--no-publish] [version]
#   version       Defaults to MARKETING_VERSION from the Xcode project (tag: v<version>).
#   --draft       Create the GitHub release as a draft.
#   --no-publish  Build, sign and notarize only; skip the GitHub release.
#
# One-time setup (on a Mac with Xcode 26+ and the `gh` CLI, logged in via `gh auth login`):
#   1. Install a "Developer ID Application" certificate for team $TEAM_ID in your keychain.
#   2. Store notarization credentials:
#        xcrun notarytool store-credentials QRBar-notary \
#          --apple-id <you@example.com> --team-id J79TFP5Q3P --password <app-specific-password>
#
# Overrides (env): TEAM_ID, NOTARY_PROFILE, SCHEME

set -euo pipefail

TEAM_ID="${TEAM_ID:-J79TFP5Q3P}"
NOTARY_PROFILE="${NOTARY_PROFILE:-QRBar-notary}"
SCHEME="${SCHEME:-QRBar}"
APP_NAME="QRBar"

DRAFT=()
PUBLISH=1
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --draft) DRAFT=(--draft) ;;
    --no-publish) PUBLISH=0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) VERSION="$arg" ;;
  esac
done

cd "$(dirname "$0")/.."
ROOT="$PWD"
PROJECT="$ROOT/$APP_NAME.xcodeproj"

[[ "$(uname)" == "Darwin" ]] || { echo "Must run on macOS." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild not found." >&2; exit 1; }
if (( PUBLISH )); then
  command -v gh >/dev/null || { echo "gh CLI not found (or use --no-publish)." >&2; exit 1; }
  [[ -z "$(git status --porcelain)" ]] || { echo "Working tree is dirty; commit or stash first." >&2; exit 1; }
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ *MARKETING_VERSION/ {print $2; exit}')"
fi
[[ -n "$VERSION" ]] || { echo "Could not determine version." >&2; exit 1; }
TAG="v$VERSION"

if (( PUBLISH )) && gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG already exists." >&2; exit 1
fi

BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT="$BUILD/export"
ZIP="$BUILD/$APP_NAME-$VERSION.zip"
rm -rf "$BUILD"; mkdir -p "$BUILD"

echo "==> Testing QRBarKit"
(cd QRBarKit && swift test)

echo "==> Archiving $APP_NAME $VERSION"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  MARKETING_VERSION="$VERSION" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ENABLE_HARDENED_RUNTIME=YES

echo "==> Exporting (Developer ID)"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD/ExportOptions.plist" -exportPath "$EXPORT"
APP="$EXPORT/$APP_NAME.app"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing"
SUBMIT_ZIP="$BUILD/notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$BUILD" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

if (( PUBLISH )); then
  echo "==> Publishing $TAG to GitHub"
  gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
    --title "$APP_NAME $VERSION" --generate-notes ${DRAFT[@]+"${DRAFT[@]}"}
fi

echo "Done: $ZIP"
