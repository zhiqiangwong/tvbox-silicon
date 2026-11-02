#!/bin/bash
# Builds and packages the independent iOS 16 test entry app into a TrollStore-ready IPA.
# Supports --empty (minimal entry with QuickJS + FFmpeg static probe) or full mode (embeds
# available NodeMobile, ApplePython, and AppleRuntime/Zero JVM artifacts).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
source "$ROOT/Scripts/apple-deployment-targets.sh"

MODE="${1:-auto}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
TRIPLE="arm64-apple-ios$IOS_DEPLOYMENT_TARGET"
OUT="$ROOT/build/sideload/TestEntry"
APP="$OUT/Payload/YingxiaTest.app"
IPA_DIR="$ROOT/build/sideload"
IPA="$IPA_DIR/YingxiaTest-iOS16.ipa"

rm -rf "$OUT" "$IPA"
mkdir -p "$APP/Frameworks" "$IPA_DIR" "$OUT/obj"

CFLAGS=(-target "$TRIPLE" -isysroot "$SDK" -O2)
QJS_OBJS=()
echo "== [1/5] Compiling QuickJS C sources for $TRIPLE"
for src in quickjs libregexp libunicode dtoa TVScript; do
  xcrun --sdk iphoneos clang "${CFLAGS[@]}" -D_GNU_SOURCE -DQUICKJS_NG_BUILD -DNDEBUG \
    -I "$ROOT/Vendor/QuickJS/include" -I "$ROOT/Vendor/QuickJS" \
    -c "$ROOT/Vendor/QuickJS/$src.c" -o "$OUT/obj/qjs-$src.o"
  QJS_OBJS+=("$OUT/obj/qjs-$src.o")
done

DEFS=(-DHAS_QUICKJS=1)
INCLUDES=(-I "$ROOT/Vendor/QuickJS/include" -I "$ROOT/Vendor/QuickJS")
LINK_ARGS=(
  "${QJS_OBJS[@]}"
  -framework UIKit -framework Foundation -framework Security -framework CoreGraphics
  -framework VideoToolbox -framework AudioToolbox -framework CoreMedia -framework CoreVideo
  -lz -liconv -lc++ -Wl,-export_dynamic
)

if [ -f "$ROOT/build/FFmpeg/FFmpeg.xcframework/ios-arm64/libFFmpeg.a" ]; then
  DEFS+=(-DHAS_FFMPEG=1)
  INCLUDES+=(-I "$ROOT/build/FFmpeg/FFmpeg.xcframework/ios-arm64/Headers")
  LINK_ARGS+=("$ROOT/build/FFmpeg/FFmpeg.xcframework/ios-arm64/libFFmpeg.a")
fi

if [ "$MODE" != "--empty" ]; then
  if [ -d "$ROOT/build/NodeMobile/NodeMobile.xcframework/ios-arm64/NodeMobile.framework" ]; then
    echo "   + Embedding NodeMobile.framework"
    rsync -a "$ROOT/build/NodeMobile/NodeMobile.xcframework/ios-arm64/NodeMobile.framework" "$APP/Frameworks/"
  fi
  if [ -d "$ROOT/build/ApplePython/iphoneos/Frameworks/Python.framework" ]; then
    echo "   + Embedding ApplePython (Python 3.14 + extensions)"
    rsync -a "$ROOT/build/ApplePython/iphoneos/Frameworks/" "$APP/Frameworks/"
    rsync -a "$ROOT/build/ApplePython/iphoneos/python" "$ROOT/build/ApplePython/iphoneos/PythonHost" "$APP/"
    xcrun --sdk iphoneos clang "${CFLAGS[@]}" -c "$ROOT/Runtime/AppleRuntime/Native/ApplePython.c" -o "$OUT/obj/ApplePython.o"
    DEFS+=(-DHAS_APPLE_PYTHON=1)
    LINK_ARGS+=("$OUT/obj/ApplePython.o")
  fi
  if [ -f "$ROOT/build/AppleRuntime/iphoneos/lib/libTVAppleRuntime.a" ]; then
    echo "   + Embedding AppleRuntime (OpenJDK Zero JVM + Unicorn TCI + bindings)"
    rsync -a "$ROOT/build/AppleRuntime/iphoneos/Resources/lib" "$APP/"
    rsync -a "$ROOT/build/AppleRuntime/iphoneos/Resources/JavaHost" "$APP/"
    if [ -f "$ROOT/build/JavaHost/host.jar" ]; then
      cp "$ROOT/build/JavaHost/host.jar" "$APP/JavaHost/host.jar"
    fi
    xcrun --sdk iphoneos clang "${CFLAGS[@]}" -fobjc-arc -I "$ROOT/build/AppleRuntime/iphoneos/include" \
      -c "$ROOT/Runtime/AppleRuntime/Native/AppleRuntime.m" -o "$OUT/obj/AppleRuntime.o"
    DEFS+=(-DHAS_APPLE_JVM=1)
    INCLUDES+=(-I "$ROOT/build/AppleRuntime/iphoneos/include")
    LINK_ARGS+=("$OUT/obj/AppleRuntime.o" -Wl,-force_load,"$ROOT/build/AppleRuntime/iphoneos/lib/libTVAppleRuntime.a")
  fi
fi

echo "== [2/5] Compiling and linking Release test entry executable ($TRIPLE)"
xcrun --sdk iphoneos clang++ "${CFLAGS[@]}" -fobjc-arc \
  "${DEFS[@]}" "${INCLUDES[@]}" \
  "$ROOT/Runtime/AppleRuntime/TestEntry/main.m" \
  "${LINK_ARGS[@]}" \
  -Wl,-rpath,@executable_path/Frameworks \
  -o "$APP/YingxiaTest"

echo "== [3/5] Writing Info.plist (MinimumOSVersion=$IOS_DEPLOYMENT_TARGET)"
python3 - "$APP" "$IOS_DEPLOYMENT_TARGET" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
minos = sys.argv[2]
info = dict(
    CFBundleIdentifier='com.tvbox.yingxia.ios16test',
    CFBundleExecutable='YingxiaTest',
    CFBundleName='YingxiaTest',
    CFBundleDisplayName='映匣 iOS16 验证',
    CFBundleVersion='1',
    CFBundleShortVersionString='1.8.3',
    CFBundlePackageType='APPL',
    MinimumOSVersion=minos,
    UIDeviceFamily=[1, 2],
    UILaunchScreen={},
    UIFileSharingEnabled=True,
    LSSupportsOpeningDocumentsInPlace=True,
    NSAppTransportSecurity={'NSAllowsArbitraryLoads': True},
    UISupportedInterfaceOrientations=[
        'UIInterfaceOrientationPortrait',
        'UIInterfaceOrientationLandscapeLeft',
        'UIInterfaceOrientationLandscapeRight'
    ],
    UISupportedInterfaceOrientations_ipad=[
        'UIInterfaceOrientationPortrait',
        'UIInterfaceOrientationPortraitUpsideDown',
        'UIInterfaceOrientationLandscapeLeft',
        'UIInterfaceOrientationLandscapeRight'
    ],
    UIApplicationSceneManifest={
        'UIApplicationSupportsMultipleScenes': False,
        'UISceneConfigurations': {
            'UIWindowSceneSessionRoleApplication': [{
                'UISceneConfigurationName': 'Default',
                'UISceneDelegateClassName': 'TestEntrySceneDelegate'
            }]
        }
    }
)
# Fix iPad key name
info['UISupportedInterfaceOrientations~ipad'] = info.pop('UISupportedInterfaceOrientations_ipad')
(app / 'Info.plist').write_bytes(plistlib.dumps(info))
PY

echo "== [4/5] Signing embedded frameworks and application bundle (ad-hoc, no APPSTORE)"
for fw in "$APP/Frameworks/"*.framework; do
  [ -d "$fw" ] && codesign --force --sign - --timestamp=none "$fw"
done
codesign --force --sign - --timestamp=none "$APP"

echo "== [5/5] Packaging Payload into IPA via ditto"
(cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent Payload "$IPA")

echo "== Verification of built executable:"
vtool -show-build "$APP/YingxiaTest" | grep -E "platform|minos|sdk"
SHA="$(shasum -a 256 "$IPA" | cut -d' ' -f1)"
echo "== IPA Ready: $IPA ($(du -sh "$IPA" | cut -f1)) | SHA-256: $SHA"
