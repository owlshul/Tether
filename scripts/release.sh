#!/bin/zsh
#
# Builds the release disk images: one for Apple Silicon, one for Intel.
#
#   scripts/release.sh            build both DMGs into dist/
#   scripts/release.sh --publish  also create the GitHub release for this version
#
# The version comes from the Xcode project (MARKETING_VERSION). Release notes
# for --publish are read from dist/notes-<version>.md: the changelog only; the
# download and install instructions are appended here.
#
# Every build is signed with the "Tether Self-Signed" certificate in the login
# keychain (docs/signing.md). The in-app updater only installs a download signed
# with the same certificate as the running app, so it must never change.

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

IDENTITY="Tether Self-Signed"
TAP_REPO="subhashhhhhh/homebrew-tether"
security find-identity -p codesigning | grep -q "\"$IDENTITY\"" \
  || { echo "The \"$IDENTITY\" signing identity isn't in the keychain (see docs/signing.md)" >&2; exit 1; }

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
    ARCHS="$arch" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none" build -quiet

  app="$derived/Build/Products/Release/Tether.app"
  binary="$app/Contents/MacOS/Tether"

  # Each image must contain exactly the architecture its name promises.
  built_archs=$(lipo -archs "$binary")
  [[ "$built_archs" == "$arch" ]] || { echo "Expected $arch, built: $built_archs" >&2; exit 1; }
  minos=$(vtool -show-build "$binary" | awk '/minos/ { print $2; exit }')
  [[ "$minos" == "$MIN_MACOS" ]] || { echo "Expected minimum macOS $MIN_MACOS, got $minos" >&2; exit 1; }
  codesign --verify --deep --strict "$app"
  for code in "$app" "$app/Contents/PlugIns/TetherShare.appex"; do
    [[ "$(codesign -dvv "$code" 2>&1)" == *"Authority=$IDENTITY"* ]] \
      || { echo "$code isn't signed with $IDENTITY" >&2; exit 1; }
  done

  # The updater downloads the zip; people download the disk image.
  zip="$DIST/Tether-$VERSION-$label.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"

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
  echo "    $(basename "$zip")  $(du -h "$zip" | cut -f1 | xargs)"
done

echo "\n==> SHA-256"
assets=(Tether-$VERSION-AppleSilicon.dmg Tether-$VERSION-Intel.dmg Tether-$VERSION-AppleSilicon.zip Tether-$VERSION-Intel.zip)
(cd "$DIST" && shasum -a 256 $assets | tee "SHA256SUMS-$VERSION.txt")

if [[ "${1:-}" == "--publish" ]]; then
  notes="$DIST/notes-$VERSION.md"
  [[ -f "$notes" ]] || { echo "Missing $notes" >&2; exit 1; }
  body="$BUILD/body.md"
  {
    cat "$notes"
    # The app shows the notes above this marker and drops the rest.
    print -- "\n<!-- tether:install -->\n\n---\n"
    print -- "### ⬇️ Install\n"
    print -- "**Homebrew** (recommended; no Gatekeeper prompt):"
    print -- '```bash\nbrew install --cask subhashhhhhh/tether/tether\n```\n'
    print -- "**Or download the disk image for your Mac:**"
    print -- "- Apple Silicon (M1 and later): \`Tether-$VERSION-AppleSilicon.dmg\`"
    print -- "- Intel: \`Tether-$VERSION-Intel.dmg\`\n"
    print -- "Not sure which you have? Apple menu → **About This Mac** → **Chip** (Apple Silicon) or **Processor** (Intel). Tether needs macOS 15 Sequoia or later.\n"
    print -- "Tether is open source and isn't notarized by Apple, so the first time you open a downloaded copy macOS blocks it. Open **System Settings → Privacy & Security**, scroll to **Security** and click **Open Anyway**, or run:"
    print -- '```bash\nxattr -cr /Applications/Tether.app\n```\n'
    print -- "Already on Tether 1.5.1 or later? It updates itself from **Tether › Check for Updates…**\n"
    print -- "Checksums are in \`SHA256SUMS-$VERSION.txt\`."
  } > "$body"

  echo "\n==> Publishing v$VERSION"
  gh release create "v$VERSION" \
    "${assets[@]/#/$DIST/}" \
    "$DIST/SHA256SUMS-$VERSION.txt" \
    --target main --title "Tether $VERSION" --notes-file "$body"

  echo "\n==> Updating updates/latest.json"
  # The in-app updater reads this through raw.githubusercontent.com, which,
  # unlike GitHub's API, isn't limited to 60 requests an hour per network.
  mkdir -p "$ROOT/updates"
  /usr/bin/python3 -I - "$VERSION" "$notes" "$DIST" "$ROOT/updates/latest.json" <<'PY'
import hashlib, json, os, sys
version, notes, dist, out = sys.argv[1:]
archives = {}
for label in ("AppleSilicon", "Intel"):
    name = f"Tether-{version}-{label}.zip"
    path = os.path.join(dist, name)
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    archives[label] = {"name": name, "size": os.path.getsize(path), "sha256": digest}
manifest = {"version": version, "tag": f"v{version}", "notes": open(notes).read().strip(), "archives": archives}
with open(out, "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  git -C "$ROOT" add updates/latest.json
  git -C "$ROOT" commit -qm "Update manifest for $VERSION"
  git -C "$ROOT" push -q
  echo "    updates/latest.json → $VERSION"

  echo "\n==> Updating the Homebrew cask"
  sha_arm=$(shasum -a 256 "$DIST/Tether-$VERSION-AppleSilicon.dmg" | cut -d' ' -f1)
  sha_intel=$(shasum -a 256 "$DIST/Tether-$VERSION-Intel.dmg" | cut -d' ' -f1)
  tap="$BUILD/tap"
  gh repo clone "$TAP_REPO" "$tap" -- --quiet --depth 1
  sed -E -i '' \
    -e "s/^  version \".*\"/  version \"$VERSION\"/" \
    -e "s/^  sha256 arm: +\"[0-9a-f]*\",/  sha256 arm:   \"$sha_arm\",/" \
    -e "s/^         intel: \"[0-9a-f]*\"/         intel: \"$sha_intel\"/" \
    "$tap/Casks/tether.rb"
  grep -q "$sha_arm" "$tap/Casks/tether.rb" && grep -q "$sha_intel" "$tap/Casks/tether.rb" \
    || { echo "Couldn't update $tap/Casks/tether.rb" >&2; exit 1; }
  git -C "$tap" commit -qam "Tether $VERSION"
  git -C "$tap" push -q
  echo "    $TAP_REPO → $VERSION"
fi
