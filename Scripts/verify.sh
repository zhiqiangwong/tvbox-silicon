#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/apple-deployment-targets.sh
mkdir -p build

verify_ios_min_target() {
  local ios_sdk
  ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  echo "Checking TVCore for arm64-apple-ios${IOS_DEPLOYMENT_TARGET}..."
  swift build --target TVCore \
    --triple "arm64-apple-ios${IOS_DEPLOYMENT_TARGET}" \
    --sdk "$ios_sdk" > build/verify-tvcore-ios16.log 2>&1
  echo "TVCore iOS ${IOS_DEPLOYMENT_TARGET} build passed (build/verify-tvcore-ios16.log)"

  echo "Checking TVBox-iOS target for arm64-apple-ios${IOS_DEPLOYMENT_TARGET}..."
  xcodebuild -project TVBox.xcodeproj -scheme TVBox-iOS -destination 'generic/platform=iOS' \
    -configuration Release -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$PWD/build/Verify-ios-min-target" \
    clean build > build/verify-ios-min-target.log 2>&1
  local app_dir="$PWD/build/Verify-ios-min-target/Build/Products/Release-iphoneos/TVBox-iOS.app"
  local app_bin="$app_dir/TVBox-iOS"
  if ! otool -l "$app_bin" | grep -A 4 "cmd LC_BUILD_VERSION" | grep -q "minos ${IOS_DEPLOYMENT_TARGET}"; then
    echo "error: $app_bin does not have minos ${IOS_DEPLOYMENT_TARGET}" >&2
    exit 1
  fi
  echo "TVBox-iOS minos ${IOS_DEPLOYMENT_TARGET} build & Mach-O check passed (build/verify-ios-min-target.log)"
}

if [[ "${1:-}" == "--ios-min-target" ]]; then
  verify_ios_min_target
  exit 0
fi

Scripts/build-apple-ffmpeg.sh
swift test
Scripts/test-apple-runtime-bridge.sh
# The apps embed build/JavaHost: it must be the sources' version, and its own tests must pass.
Scripts/check-java-host.sh build/JavaHost/host.jar
Scripts/test-java-host.sh > build/verify-java.log 2>&1 || { tail -40 build/verify-java.log; exit 1; }
echo "Java host tests passed (build/verify-java.log)"
verify_ios_min_target
for entry in 'macOS|platform=macOS|mac' 'iOS|generic/platform=iOS|ios' 'tvOS|generic/platform=tvOS|tv'; do
  IFS='|' read -r platform destination folder <<< "$entry"
  xcodebuild -project TVBox.xcodeproj -scheme "TVBox-$platform" \
    -destination "$destination" -derivedDataPath "build/Verify-$folder" \
    -skipMacroValidation CODE_SIGNING_ALLOWED=NO build > "build/verify-$folder.log" 2>&1
  echo "$platform build passed (build/verify-$folder.log)"
done
