#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PACKAGE_NAME="nzapret-desktop"
APP_BINARY_NAME="nzapret_desktop"
APP_INSTALL_DIR="/opt/$APP_PACKAGE_NAME"
DIST_DIR="$ROOT_DIR/dist"
BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
SKIP_BUILD="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build)
      SKIP_BUILD="1"
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

pubspec_value() {
  local key="$1"
  awk -F': ' -v key="$key" '$1 == key { print $2; exit }' "$ROOT_DIR/pubspec.yaml"
}

deb_architecture() {
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --print-architecture
    return 0
  fi

  case "$(uname -m)" in
    x86_64)
      echo "amd64"
      ;;
    aarch64)
      echo "arm64"
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

compute_dependencies() {
  local package_root="$1"
  local bundle_root="$package_root$APP_INSTALL_DIR"

  if command -v dpkg-shlibdeps >/dev/null 2>&1; then
    local output=""
    output="$(
      dpkg-shlibdeps -O \
        -l"$bundle_root/lib" \
        "$bundle_root/$APP_BINARY_NAME" \
        "$bundle_root/lib/libapp.so" \
        "$bundle_root/lib/libflutter_linux_gtk.so" 2>/dev/null || true
    )"

    if [[ "$output" == shlibs:Depends=* ]]; then
      local deps="${output#shlibs:Depends=}"
      if [[ -n "$deps" ]]; then
        echo "$deps, nftables"
        return 0
      fi
    fi
  fi

  echo "libc6, libgcc-s1, libgtk-3-0, libstdc++6, libblkid1, zlib1g, nftables"
}

require_cmd cp
require_cmd dpkg-deb
require_cmd install
require_cmd ln
require_cmd tar

if [[ "$SKIP_BUILD" != "1" ]]; then
  "$ROOT_DIR/build-linux.sh"
fi

if [[ ! -x "$BUNDLE_DIR/$APP_BINARY_NAME" ]]; then
  echo "Release bundle not found. Run ./build-linux.sh first." >&2
  exit 1
fi

VERSION="$(pubspec_value version)"
ARCH="$(deb_architecture)"
MAINTAINER="${DEB_MAINTAINER:-NZapret Desktop Maintainers <noreply@localhost>}"
PACKAGE_ROOT="$ROOT_DIR/build/deb/$APP_PACKAGE_NAME"
OUTPUT_PATH="$DIST_DIR/${APP_PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

rm -rf "$PACKAGE_ROOT"
mkdir -p \
  "$PACKAGE_ROOT/DEBIAN" \
  "$PACKAGE_ROOT$APP_INSTALL_DIR" \
  "$PACKAGE_ROOT/usr/bin" \
  "$PACKAGE_ROOT/usr/share/applications" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/scalable/apps" \
  "$PACKAGE_ROOT/usr/share/doc/$APP_PACKAGE_NAME" \
  "$DIST_DIR"

cp -R "$BUNDLE_DIR"/. "$PACKAGE_ROOT$APP_INSTALL_DIR/"
ln -s "$APP_INSTALL_DIR/$APP_BINARY_NAME" "$PACKAGE_ROOT/usr/bin/$APP_PACKAGE_NAME"
install -m 644 "$ROOT_DIR/packaging/linux/nzapret-desktop.desktop" \
  "$PACKAGE_ROOT/usr/share/applications/$APP_PACKAGE_NAME.desktop"
install -m 644 "$ROOT_DIR/assets/branding/nzapret-desktop.svg" \
  "$PACKAGE_ROOT/usr/share/icons/hicolor/scalable/apps/$APP_PACKAGE_NAME.svg"
install -m 644 "$ROOT_DIR/README.md" \
  "$PACKAGE_ROOT/usr/share/doc/$APP_PACKAGE_NAME/README.md"

INSTALLED_SIZE="$(du -sk "$PACKAGE_ROOT" | awk '{print $1}')"
DEPENDS="$(compute_dependencies "$PACKAGE_ROOT")"

cat > "$PACKAGE_ROOT/DEBIAN/control" <<EOF
Package: $APP_PACKAGE_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Maintainer: $MAINTAINER
Depends: $DEPENDS
Installed-Size: $INSTALLED_SIZE
Description: Linux desktop controller for nfqws and nftables
 Desktop UI for launching the bundled nfqws strategy, managing nftables queue
 rules, reading runtime logs, and operating privileged start/stop flows through
 pkexec when available.
EOF

dpkg-deb --build --root-owner-group "$PACKAGE_ROOT" "$OUTPUT_PATH" >/dev/null
echo "Built $OUTPUT_PATH"
