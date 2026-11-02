#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
# Upstream otherwise overwrites CMAKE_OSX_ARCHITECTURES with x86_64 + arm64,
# including device SDKs where x86_64 is not a supported architecture.
export ARCHFLAGS="-arch arm64"
WORK="$ROOT/build/apple-runtime"
SOURCE="$WORK/unicorn-tci"
REVISION=e3f075a62742913bb734a55a474aec65c9e5745e
mkdir -p "$WORK"
if [ ! -d "$SOURCE/.git" ]; then
  git clone https://github.com/1rhino2/unicorn-tci.git "$SOURCE"
fi
if [ "$(git -C "$SOURCE" rev-parse HEAD)" != "$REVISION" ]; then
  git -C "$SOURCE" fetch origin "$REVISION"
  git -C "$SOURCE" checkout --detach "$REVISION"
fi
PATCH="$ROOT/Runtime/AppleRuntime/patches/unicorn-apple.patch"
if git -C "$SOURCE" apply --check "$PATCH" 2>/dev/null; then
  git -C "$SOURCE" apply "$PATCH"
else
  git -C "$SOURCE" apply --reverse --check "$PATCH"
fi
SOURCE="$SOURCE/unicorn-engine-sys-tci"
source "$ROOT/Scripts/apple-deployment-targets.sh"
TARGET="${1:-macos}"
FLAGS=(-DUNICORN_INTERPRETER=ON -DUNICORN_ARCH=aarch64 -DUNICORN_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release)
DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET"
case "$TARGET" in
  macos) DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" ;;
  ios) FLAGS+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos "-DCMAKE_C_FLAGS=-target arm64-apple-ios$IOS_DEPLOYMENT_TARGET") ;;
  ios-simulator) FLAGS+=(-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator "-DCMAKE_C_FLAGS=-target arm64-apple-ios$IOS_DEPLOYMENT_TARGET-simulator") ;;
  tvos) DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET"; FLAGS+=(-DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT=appletvos "-DCMAKE_C_FLAGS=-target arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET") ;;
  tvos-simulator) DEPLOYMENT_TARGET="$TVOS_DEPLOYMENT_TARGET"; FLAGS+=(-DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_SYSROOT=appletvsimulator "-DCMAKE_C_FLAGS=-target arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET-simulator") ;;
  *) echo "Usage: $0 [macos|ios|ios-simulator|tvos|tvos-simulator]" >&2; exit 2 ;;
esac
if [ "$TARGET" != macos ]; then FLAGS+=(-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"); fi
OUTPUT="$WORK/unicorn-tci-$TARGET"
STAMP="$TARGET:$DEPLOYMENT_TARGET"
if [ "$(cat "$OUTPUT/.deployment-target" 2>/dev/null || true)" != "$STAMP" ]; then
  rm -rf "$OUTPUT"
fi
if [ -f "$OUTPUT/libunicorn.a" ] && grep -q '^UNICORN_INTERPRETER:BOOL=ON$' "$OUTPUT/CMakeCache.txt" 2>/dev/null; then
  echo "Interpreter-only ARM64 archive (cached for $STAMP): $OUTPUT/libunicorn.a"
  exit 0
fi
cmake -S "$SOURCE" -B "$OUTPUT" "${FLAGS[@]}"
cmake --build "$OUTPUT" -j "${JOBS:-4}"
# Fail closed if a cached configuration accidentally chose the JIT backend.
grep -q '^UNICORN_INTERPRETER:BOOL=ON$' "$OUTPUT/CMakeCache.txt"
if [ "$TARGET" = macos ]; then
  clang -I "$SOURCE/include" Tests/Native/Arm64InterpreterProbe.c "$OUTPUT/libunicorn.a" -lpthread -lm -o "$OUTPUT/arm64-probe"
  "$OUTPUT/arm64-probe"
fi
echo "$STAMP" > "$OUTPUT/.deployment-target"
echo "Interpreter-only ARM64 archive: $OUTPUT/libunicorn.a"
