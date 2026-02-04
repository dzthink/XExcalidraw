#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTPM_ROOT="${SWIFTPM_ROOT:-$ROOT_DIR/.swiftpm}"
SWIFTPM_CACHE="$SWIFTPM_ROOT/cache"
SWIFTPM_CONFIG="$SWIFTPM_ROOT/config"
SWIFTPM_SECURITY="$SWIFTPM_ROOT/security"
SWIFTPM_SCRATCH="$SWIFTPM_ROOT/scratch"
SWIFTPM_HOME="$SWIFTPM_ROOT/home"
CLANG_MODULE_CACHE="$SWIFTPM_ROOT/clang-module-cache"

mkdir -p "$SWIFTPM_CACHE" "$SWIFTPM_CONFIG" "$SWIFTPM_SECURITY" "$SWIFTPM_SCRATCH" "$SWIFTPM_HOME" "$CLANG_MODULE_CACHE"
export HOME="$SWIFTPM_HOME"
export XDG_CACHE_HOME="$SWIFTPM_CACHE"
export XDG_CONFIG_HOME="$SWIFTPM_CONFIG"
export XDG_DATA_HOME="$SWIFTPM_ROOT/data"
export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE"

COMMON=(--cache-path "$SWIFTPM_CACHE" --config-path "$SWIFTPM_CONFIG" --security-path "$SWIFTPM_SECURITY" --scratch-path "$SWIFTPM_SCRATCH" --manifest-cache local --disable-sandbox)

swift test --package-path "$ROOT_DIR/apps/shared" "${COMMON[@]}"
swift test --package-path "$ROOT_DIR/apps/macos" "${COMMON[@]}"
swift test --package-path "$ROOT_DIR/apps/ios" "${COMMON[@]}"

DERIVED_DATA_ROOT="$ROOT_DIR/build/DerivedData"
mkdir -p "$DERIVED_DATA_ROOT"

./scripts/build_web.sh

xcodebuild build-for-testing \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawMac.xcodeproj" \
  -scheme ExcalidrawMacUITests \
  -destination "platform=macOS" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_ROOT/macos"

WEB_COPY_DEST="$DERIVED_DATA_ROOT/macos/Build/Products/Debug/ExcalidrawMac.app/Contents/Resources" \
  WEB_SKIP_BUILD=1 \
  ./scripts/build_web.sh

xcodebuild test-without-building \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawMac.xcodeproj" \
  -scheme ExcalidrawMacUITests \
  -destination "platform=macOS" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_ROOT/macos"

if [[ -z "${IOS_DESTINATION:-}" ]]; then
  if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    IOS_DESTINATION="platform=iOS Simulator,name=$IOS_SIMULATOR_NAME"
  else
    if ! xcrun simctl list runtimes | rg -q "iOS .*\\(available\\)"; then
      echo "No iOS Simulator runtime installed. Install it in Xcode > Settings > Components." >&2
      exit 1
    fi
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

WEB_COPY_DEST="$DERIVED_DATA_ROOT/ios/Build/Products/Debug-iphonesimulator/ExcalidrawIOS.app" \
  WEB_SKIP_BUILD=1 \
  ./scripts/build_web.sh

xcodebuild test-without-building \
  -project "$ROOT_DIR/apps/_legacy_xcode/ExcalidrawIOS.xcodeproj" \
  -scheme ExcalidrawIOSUITests \
  -destination "$IOS_DESTINATION" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_ROOT/ios"
