#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTPM_ROOT="${SWIFTPM_ROOT:-$ROOT_DIR/.swiftpm}"
SWIFTPM_CACHE="$SWIFTPM_ROOT/cache"
SWIFTPM_CONFIG="$SWIFTPM_ROOT/config"
SWIFTPM_SECURITY="$SWIFTPM_ROOT/security"
SWIFTPM_SCRATCH="$SWIFTPM_ROOT/scratch"
CLANG_MODULE_CACHE="$SWIFTPM_ROOT/clang-module-cache"

mkdir -p "$SWIFTPM_CACHE" "$SWIFTPM_CONFIG" "$SWIFTPM_SECURITY" "$SWIFTPM_SCRATCH" "$CLANG_MODULE_CACHE"
# Keep HOME unchanged so Xcode uses the signed-in user's automation session.
export XDG_CACHE_HOME="$SWIFTPM_CACHE"
export XDG_CONFIG_HOME="$SWIFTPM_CONFIG"
export XDG_DATA_HOME="$SWIFTPM_ROOT/data"
export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE"

COMMON=(--cache-path "$SWIFTPM_CACHE" --config-path "$SWIFTPM_CONFIG" --security-path "$SWIFTPM_SECURITY" --scratch-path "$SWIFTPM_SCRATCH" --manifest-cache local --disable-sandbox)

swift test --package-path "$ROOT_DIR/apps/shared" "${COMMON[@]}"
swift test --package-path "$ROOT_DIR/apps/macos" "${COMMON[@]}"
# The iOS executable cannot link on the macOS host. Exercise it through
# the simulator app and XCTest runner below instead of a host-only placeholder.

DERIVED_DATA_ROOT="$ROOT_DIR/build/DerivedData"
mkdir -p "$DERIVED_DATA_ROOT"

./scripts/build_web.sh

xcodebuild build-for-testing \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawMac.xcodeproj" \
  -scheme ExcalidrawMacUITests \
  -destination "platform=macOS" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_ROOT/macos"

WEB_COPY_DEST="$DERIVED_DATA_ROOT/macos/Build/Products/Debug/Siye.app/Contents/Resources" \
  WEB_SKIP_BUILD=1 \
  ./scripts/build_web.sh

xcodebuild test-without-building \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawMac.xcodeproj" \
  -scheme ExcalidrawMacUITests \
  -destination "platform=macOS" \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -derivedDataPath "$DERIVED_DATA_ROOT/macos"

if [[ -z "${IOS_DESTINATION:-}" ]]; then
  if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    IOS_DESTINATION="platform=iOS Simulator,name=$IOS_SIMULATOR_NAME"
  else
    IOS_SIMULATOR_NAME="$(xcrun simctl list devices available | rg -m1 -o 'iPhone[^()]+' | sed 's/[[:space:]]*$//' || true)"
    if [[ -z "$IOS_SIMULATOR_NAME" ]]; then
      echo "No available iPhone simulator found. Set IOS_DESTINATION or IOS_SIMULATOR_NAME." >&2
      exit 1
    fi
    IOS_DESTINATION="platform=iOS Simulator,name=$IOS_SIMULATOR_NAME"
  fi
fi

xcodebuild build-for-testing \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawIOS.xcodeproj" \
  -scheme ExcalidrawIOSUITests \
  -destination "$IOS_DESTINATION" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_ROOT/ios"

WEB_COPY_DEST="$DERIVED_DATA_ROOT/ios/Build/Products/Debug-iphonesimulator/Siye.app" \
  WEB_SKIP_BUILD=1 \
  ./scripts/build_web.sh

xcodebuild test-without-building \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawIOS.xcodeproj" \
  -scheme ExcalidrawIOSUITests \
  -destination "$IOS_DESTINATION" \
  -configuration Debug \
  -parallel-testing-enabled NO \
  -derivedDataPath "$DERIVED_DATA_ROOT/ios"
