#!/bin/bash
# Makes a release the app can update itself to.
#
#     Tools/release.sh 1.4.0
#
# Sets the version in Info.plist (and bumps the build number), builds the app, and zips it as
# release/qPCR-Planner-<version>.zip. Publish it as a GitHub Release tagged qpcr-v<version> with that
# .zip attached; every copy of the app with automatic checks on then offers the update.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "usage: Tools/release.sh <version>   e.g. Tools/release.sh 1.4.0" >&2
  exit 1
fi

REPO=$(/usr/libexec/PlistBuddy -c "Print :UpdateRepository" Info.plist 2>/dev/null || true)
if [[ "$REPO" != */* ]]; then
  echo "Set UpdateRepository in Info.plist to owner/repo first, or the released app can't find later updates." >&2
  exit 1
fi

BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" Info.plist

./build.sh

mkdir -p release
ZIP="release/qPCR-Planner-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "qPCR Planner.app" "$ZIP"

echo
echo "Made $ZIP ($(du -h "$ZIP" | cut -f1)), SHA-256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
if command -v gh >/dev/null; then
  echo "Publish it with:"
  echo "  gh release create qpcr-v$VERSION \"$ZIP\" --repo $REPO --title \"qPCR Planner $VERSION\" --notes \"What changed…\""
else
  echo "Publish it: https://github.com/$REPO/releases/new"
  echo "  tag qpcr-v$VERSION, title \"qPCR Planner $VERSION\", write what changed, attach $ZIP, Publish release."
fi
