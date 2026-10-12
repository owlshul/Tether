#!/bin/zsh
#
# Builds the release disk images: one for Apple Silicon, one for Intel.
#
#   scripts/release.sh            build both DMGs into dist/
#   scripts/release.sh --publish  also create the GitHub release for this version
#
# The version comes from the Xcode project (MARKETING_VERSION). Release notes
# for --publish are read from dist/notes-<version>.md.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

VERSION=$(xcodebuild -project Tether.xcodeproj -target Tether -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2; exit }')
MIN_MACOS=$(xcodebuild -project Tether.xcodeproj -target Tether -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = / { print $2; exit }')
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION" >&2; exit 1; }

mkdir -p "$DIST"
echo "Tether $VERSION (macOS $MIN_MACOS+)"

# arch   label (used in the file name)
for pair in "arm64 AppleSilicon" "x86_64 Intel"; do
  arch=${pair%% *}
  label=${pair##* }
  derived="$BUILD/$arch"
  echo "\n==> Building $label ($arch)"

  xcodebuild -project Tether.xcodeproj -scheme Tether -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    ARCHS="$arch" ONLY_ACTIVE_ARCH=NO build -quiet

  app="$derived/Build/Products/Release/Tether.app"
  binary="$app/Contents/MacOS/Tether"

  # Each image must contain exactly the architecture its name promises.
  built_archs=$(lipo -archs "$binary")
  [[ "$built_archs" == "$arch" ]] || { echo "Expected $arch, built: $built_archs" >&2; exit 1; }
  minos=$(vtool -show-build "$binary" | awk '/minos/ { print $2; exit }')
  [[ "$minos" == "$MIN_MACOS" ]] || { echo "Expected minimum macOS $MIN_MACOS, got $minos" >&2; exit 1; }
  codesign --verify --deep --strict "$app"

  staging="$BUILD/dmg-$arch"
  mkdir -p "$staging"
  ditto "$app" "$staging/Tether.app"
  ln -s /Applications "$staging/Applications"

  dmg="$DIST/Tether-$VERSION-$label.dmg"
  rm -f "$dmg"
  hdiutil create -quiet -volname "Tether $VERSION" -srcfolder "$staging" \
    -format UDZO -imagekey zlib-level=9 "$dmg"
  hdiutil verify -quiet "$dmg"
  echo "    $(basename "$dmg")  $(du -h "$dmg" | cut -f1 | xargs)"
done

echo "\n==> SHA-256"
(cd "$DIST" && shasum -a 256 "Tether-$VERSION-AppleSilicon.dmg" "Tether-$VERSION-Intel.dmg" | tee "SHA256SUMS-$VERSION.txt")

if [[ "${1:-}" == "--publish" ]]; then
  notes="$DIST/notes-$VERSION.md"
  [[ -f "$notes" ]] || { echo "Missing $notes" >&2; exit 1; }
  echo "\n==> Publishing v$VERSION"
  gh release create "v$VERSION" \
    "$DIST/Tether-$VERSION-AppleSilicon.dmg" \
    "$DIST/Tether-$VERSION-Intel.dmg" \
    "$DIST/SHA256SUMS-$VERSION.txt" \
    --target main --title "Tether $VERSION" --notes-file "$notes"
fi
