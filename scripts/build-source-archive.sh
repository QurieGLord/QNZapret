#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PACKAGE_NAME="nzapret-desktop"
VERSION="$(awk -F': ' '$1 == "version" { print $2; exit }' "$ROOT_DIR/pubspec.yaml")"
STAGING_ROOT="$ROOT_DIR/build/source"
STAGING_DIR="$STAGING_ROOT/${APP_PACKAGE_NAME}-${VERSION}"
OUTPUT_PATH="$DIST_DIR/${APP_PACKAGE_NAME}-${VERSION}-source.tar.gz"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

tar \
  --exclude='./.dart_tool' \
  --exclude='./.idea' \
  --exclude='./.pub' \
  --exclude='./.pub-cache' \
  --exclude='./.toolchain' \
  --exclude='./build' \
  --exclude='./coverage' \
  --exclude='./dist' \
  --exclude='./linux/flutter/ephemeral' \
  --exclude='./*.iml' \
  -cf - \
  -C "$ROOT_DIR" . | tar -xf - -C "$STAGING_DIR"

tar -C "$STAGING_ROOT" -czf "$OUTPUT_PATH" "$(basename "$STAGING_DIR")"
echo "Built $OUTPUT_PATH"
