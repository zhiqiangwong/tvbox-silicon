#!/bin/bash
# Prepare signed-in app resources; never bundle Mac executables or native dylibs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"; TARGET="${1:-ios-simulator}"
source "$ROOT/Scripts/apple-deployment-targets.sh"
case "$TARGET" in
 ios) PLATFORM=iphoneos; CONF=ios-aarch64-zero-release; MINIMUM="-miphoneos-version-min=$IOS_DEPLOYMENT_TARGET" ;;
 ios-simulator) PLATFORM=iphonesimulator; CONF=ios-aarch64-zero-simulator; MINIMUM="-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET" ;;
 tvos) PLATFORM=appletvos; CONF=tvos-aarch64-zero-release; MINIMUM="-mtvos-version-min=$TVOS_DEPLOYMENT_TARGET" ;;
 tvos-simulator) PLATFORM=appletvsimulator; CONF=tvos-aarch64-zero-simulator; MINIMUM="-mtvos-simulator-version-min=$TVOS_DEPLOYMENT_TARGET" ;;
 *) exit 2 ;;
esac
WORK="$ROOT/build/apple-runtime"; OUT="$ROOT/build/AppleRuntime/$PLATFORM"
BOOT="$WORK/boot-jdk/jdk-26.0.2.1+1/Contents/Home"
JDK="$WORK/openjdk-mobile/build/$CONF"
if [ "$(cat "$OUT/.deployment-target" 2>/dev/null || true)" != "$MINIMUM" ]; then
  rm -rf "$OUT/lib"
fi
if [ ! -f "$JDK/images/static-libs/lib/zero/libjvm.a" ] || [ ! -f "$JDK/images/static-libs/lib/libmanagement.a" ] || [ "$(cat "$JDK/.deployment-target" 2>/dev/null || true)" != "$MINIMUM" ]; then
  Scripts/build-apple-jvm.sh "$TARGET"
fi
Scripts/build-apple-native-bindings.sh "$TARGET"
mkdir -p "$OUT/lib" "$OUT/include" "$OUT/Resources/lib/lib/security" "$OUT/Resources/lib/conf/security" "$OUT/Resources/JavaHost/lib"
cp "$BOOT/include/jni.h" "$BOOT/include/darwin/jni_md.h" "$OUT/include/"
LIB="$JDK/images/static-libs/lib"
ARCHIVES=("$LIB/zero/libjvm.a")
for name in java net nio zip jimage verify management; do ARCHIVES+=("$LIB/lib$name.a"); done
ARCHIVES+=("$WORK/libffi-$TARGET-3.4.8/install/lib/libffi.a" "$WORK/unicorn-tci-$TARGET/libunicorn.a" "$WORK/capstone-$TARGET/libcapstone.a" "$WORK/keystone-$TARGET/llvm/lib/libkeystone.a" "$WORK/native-$TARGET/libapplebindings.a")
xcrun libtool -static -o "$OUT/lib/libTVAppleRuntime.a" "${ARCHIVES[@]}"
# Link the classes into one jimage (lib/lib/modules, as java.home is lib) instead of shipping the
# exploded module folders: sideload signers (SideStore, Xcode's export) read every file starting with
# CAFEBABE, which every .class file does, as a fat Mach-O and fail. jlink must match the target's
# JDK version, so it comes from a host build of the same source tree.
HOST="$WORK/openjdk-mobile/build/macosx-host/images/jdk"
if [ ! -x "$HOST/bin/jlink" ]; then
 DUMMY_METAL="$WORK/dummy-metal.sh"
 cat > "$DUMMY_METAL" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  if [ "$1" = "-o" ] && [ $# -gt 1 ]; then
    mkdir -p "$(dirname "$2")"
    : > "$2"
    exit 0
  fi
  shift
done
echo "Apple LLVM version 17.0.0 (metal)"
EOF
 chmod +x "$DUMMY_METAL"
 (cd "$WORK/openjdk-mobile" && sh configure --with-conf-name=macosx-host --disable-warnings-as-errors --with-boot-jdk="$BOOT" METAL="$DUMMY_METAL" METALLIB="$DUMMY_METAL" && make CONF=macosx-host JOBS="${JOBS:-4}" jdk-image)
fi
# jdk.charsets carries GBK/GB2312/GB18030/Big5, which many Chinese source sites still serve.
MODULES=java.base,java.management,java.logging,java.naming,java.security.sasl,java.xml,jdk.zipfs,jdk.httpserver,jdk.unsupported,jdk.charsets
# Exploded java.base has no target platform, which jlink needs; a jmod records it.
LINK="$WORK/jlink-$TARGET"; rm -rf "$LINK"; mkdir -p "$LINK/jmods"
"$HOST/bin/jmod" create --class-path "$JDK/jdk/modules/java.base" --target-platform "$(sed -n 's/^OPENJDK_MODULE_TARGET_PLATFORM := //p' "$JDK/spec.gmk")" "$LINK/jmods/java.base.jmod"
MODULE_PATH="$LINK/jmods"
for module in ${MODULES//,/ }; do [ "$module" = java.base ] || MODULE_PATH+=":$JDK/jdk/modules/$module"; done
"$HOST/bin/jlink" --module-path "$MODULE_PATH" --add-modules "$MODULES" --output "$LINK/image"
rm -rf "$OUT/Resources/lib/modules"
cp "$LINK/image/lib/modules" "$OUT/Resources/lib/lib/modules"
cp "$BOOT/conf/security/java.security" "$OUT/Resources/lib/conf/security/"
rsync -a --delete "$BOOT/conf/security/policy/" "$OUT/Resources/lib/conf/security/policy/"
cp "$BOOT/lib/security/cacerts" "$OUT/Resources/lib/lib/security/"
cp "$BOOT/lib/tzdb.dat" "$OUT/Resources/lib/lib/"
cp "$WORK/native-$TARGET/apple-bindings.jar" "$OUT/Resources/JavaHost/"
Scripts/sync-apple-javahost.sh "$PLATFORM"
echo "$MINIMUM" > "$OUT/.deployment-target"
echo "Packaged runtime: $OUT"
