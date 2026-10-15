#!/bin/zsh
# Rebuilds Vendor/MediaRemoteAdapter from source. Tether reads what's playing
# on the Mac through it: since macOS 15.4 only Apple-signed programs may read
# Now Playing, so the adapter is loaded by /usr/bin/perl.
#
#   scripts/build-mediaremote-adapter.sh [commit]
#
# Needs cmake. Default commit: the one the checked-in framework was built from.
set -euo pipefail
ROOT=${0:A:h:h}
COMMIT=${1:-797729d9b16316dc313844476c153d7a107ca0df}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone -q https://github.com/ungive/mediaremote-adapter.git "$WORK/src"
git -C "$WORK/src" checkout -q "$COMMIT"
cmake -S "$WORK/src" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 >/dev/null
cmake --build "$WORK/build" --config Release -j 8 >/dev/null

rm -rf "$ROOT/Vendor/MediaRemoteAdapter/MediaRemoteAdapter.framework"
ditto "$WORK/build/MediaRemoteAdapter.framework" "$ROOT/Vendor/MediaRemoteAdapter/MediaRemoteAdapter.framework"
cp "$WORK/src/LICENSE" "$ROOT/Vendor/MediaRemoteAdapter/LICENSE"
cp "$WORK/src/bin/mediaremote-adapter.pl" "$ROOT/Tether/Resources/mediaremote-adapter.pl"
echo "$COMMIT" > "$ROOT/Vendor/MediaRemoteAdapter/COMMIT"
echo "Built MediaRemoteAdapter at $COMMIT"
