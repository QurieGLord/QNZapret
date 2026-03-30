#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PACKAGE_NAME="nzapret-desktop"
BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
VERSION="$(awk -F': ' '$1 == "version" { print $2; exit }' "$ROOT_DIR/pubspec.yaml")"
PORTABLE_DIR="$DIST_DIR/${APP_PACKAGE_NAME}-${VERSION}-linux-x64"
PORTABLE_ARCHIVE="$DIST_DIR/${APP_PACKAGE_NAME}-${VERSION}-linux-x64.tar.gz"

mkdir -p "$DIST_DIR"

"$ROOT_DIR/scripts/build-source-archive.sh"
"$ROOT_DIR/build-linux.sh"
"$ROOT_DIR/scripts/package-deb.sh" --skip-build

rm -rf "$PORTABLE_DIR"
mkdir -p "$PORTABLE_DIR"
cp -R "$BUNDLE_DIR"/. "$PORTABLE_DIR/"
tar -C "$DIST_DIR" -czf "$PORTABLE_ARCHIVE" "$(basename "$PORTABLE_DIR")"

echo "Built $PORTABLE_ARCHIVE"
