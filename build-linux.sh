#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$ROOT_DIR/.toolchain/bin"

mkdir -p "$TOOLCHAIN_DIR"

resolve_tool() {
  local fallback="$1"
  shift

  local candidate=""
  for candidate in "$@"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  candidate="$(command -v "$fallback" 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  echo "Unable to locate required tool: $fallback" >&2
  exit 1
}

write_wrapper() {
  local name="$1"
  local target="$2"
  cat > "$TOOLCHAIN_DIR/$name" <<EOF
#!/usr/bin/env bash
exec $target "\$@"
EOF
  chmod 755 "$TOOLCHAIN_DIR/$name"
}

CLANGXX_PATH="$(resolve_tool clang++ /usr/bin/clang++ /usr/lib/llvm-18/bin/clang++)"
CLANG_PATH="$(resolve_tool clang /usr/bin/clang /usr/lib/llvm-18/bin/clang)"
LLVM_AR_PATH="$(
  command -v llvm-ar 2>/dev/null || true
)"
if [[ -z "$LLVM_AR_PATH" ]]; then
  LLVM_AR_PATH="$(
    command -v ar 2>/dev/null || true
  )"
fi
if [[ -z "$LLVM_AR_PATH" ]]; then
  LLVM_AR_PATH="$(resolve_tool llvm-ar \
    /usr/lib/llvm-18/bin/llvm-ar \
    /usr/lib/llvm-17/bin/llvm-ar \
    /usr/lib/llvm-16/bin/llvm-ar)"
fi
LD_PATH="$(resolve_tool ld /usr/bin/ld /usr/lib/llvm-18/bin/ld.lld /usr/bin/ld.lld)"

write_wrapper "clang++" "$CLANGXX_PATH"
write_wrapper "clang" "$CLANG_PATH"
write_wrapper "llvm-ar" "$LLVM_AR_PATH"
write_wrapper "ld" "$LD_PATH"

PATH="$TOOLCHAIN_DIR:$PATH" flutter build linux "$@"
