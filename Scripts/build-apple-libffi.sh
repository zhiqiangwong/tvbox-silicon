#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$PWD/build/apple-runtime"
source "$PWD/Scripts/apple-deployment-targets.sh"
TARGET="${1:-ios}"
case "$TARGET" in
  ios) SDK=iphoneos; TRIPLE=arm64-apple-ios$IOS_DEPLOYMENT_TARGET ;;
  ios-simulator) SDK=iphonesimulator; TRIPLE=arm64-apple-ios$IOS_DEPLOYMENT_TARGET-simulator ;;
  tvos) SDK=appletvos; TRIPLE=arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET ;;
  tvos-simulator) SDK=appletvsimulator; TRIPLE=arm64-apple-tvos$TVOS_DEPLOYMENT_TARGET-simulator ;;
  *) echo "Usage: $0 [ios|ios-simulator|tvos|tvos-simulator]" >&2; exit 2 ;;
esac
mkdir -p "$WORK"
ARCHIVE="$WORK/libffi-3.4.8.tar.gz"
if [ ! -f "$ARCHIVE" ]; then
  curl -fL --retry 2 https://github.com/libffi/libffi/releases/download/v3.4.8/libffi-3.4.8.tar.gz -o "$ARCHIVE.download"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
echo "bc9842a18898bfacb0ed1252c4febcc7e78fa139fd27fdc7a3e30d9d9356119b  $ARCHIVE" | shasum -a 256 -c -
if [ ! -d "$WORK/libffi-3.4.8" ]; then tar -xzf "$ARCHIVE" -C "$WORK"; fi
BUILD="$WORK/libffi-$TARGET-3.4.8"
if [ "$(cat "$BUILD/.deployment-target" 2>/dev/null || true)" != "$TRIPLE" ]; then
  rm -rf "$BUILD"
fi
if [ -f "$BUILD/install/lib/libffi.a" ]; then
  echo "Static libffi (cached for $TRIPLE): $BUILD/install/lib/libffi.a"
  exit 0
fi
mkdir -p "$BUILD"
cd "$BUILD"
SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK" --find clang) -target $TRIPLE" \
  CFLAGS="-O2 -isysroot $SYSROOT" LDFLAGS="-isysroot $SYSROOT" \
  "$WORK/libffi-3.4.8/configure" --host=aarch64-apple-darwin \
  --disable-shared --enable-static --disable-docs --prefix="$BUILD/install"
make -j "${JOBS:-4}"
make install
test -f "$BUILD/install/lib/libffi.a"
echo "$TRIPLE" > "$BUILD/.deployment-target"
echo "Static libffi: $BUILD/install/lib/libffi.a"
