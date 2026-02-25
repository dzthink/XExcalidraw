#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# DEVICE BUILD CONFIGURATION
# Edit these values for your development environment
# Or keep them empty and use environment variables to override
# =============================================================================

# Your Apple Development signing identity
# Find it with: security find-identity -v -p codesigning
# Example: "Apple Development: Your Name (XXXXXXXXXX)"
DEFAULT_IOS_SIGN_IDENTITY="Apple Development: dzthink@qq.com (65Y79GZJKH)"

# Path to your provisioning profile (.mobileprovision file)
# Download from: https://developer.apple.com/account/resources/profiles/list
# For free provisioning with Xcode, leave this empty (Xcode manages it)
DEFAULT_IOS_PROVISIONING_PROFILE=""

# For free developer account builds, use Xcode directly:
#   open apps/_legacy_xcode/ExcalidrawIOS.xcodeproj
# Then select your iPhone and click Run (Cmd+R)

# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_PACKAGE="$ROOT_DIR/apps/ios"
MAC_PACKAGE="$ROOT_DIR/apps/macos"
WEB_DIR="$ROOT_DIR/web/canvas-host"
WEB_DIST_DIR="$WEB_DIR/dist"
SWIFTPM_ROOT="${SWIFTPM_ROOT:-$ROOT_DIR/.swiftpm}"
SWIFTPM_CACHE="$SWIFTPM_ROOT/cache"
SWIFTPM_CONFIG="$SWIFTPM_ROOT/config"
SWIFTPM_SECURITY="$SWIFTPM_ROOT/security"
SWIFTPM_SCRATCH="$SWIFTPM_ROOT/scratch"
SWIFTPM_HOME="$SWIFTPM_ROOT/home"
CLANG_MODULE_CACHE="$SWIFTPM_ROOT/clang-module-cache"

CONFIGURATION_RAW="${CONFIGURATION:-Debug}"
CONFIGURATION="$(echo "$CONFIGURATION_RAW" | tr '[:upper:]' '[:lower:]')"

IOS_DEVICE_BUILD="${IOS_DEVICE_BUILD:-0}"
IOS_SDK="${IOS_SDK:-}"  # Auto-detect if empty
IOS_VERSION="${IOS_VERSION:-16.0}"
IOS_ARCH="${IOS_ARCH:-arm64}"
# Use default values from configuration section if env var not set
IOS_SIGN_IDENTITY="${IOS_SIGN_IDENTITY:-$DEFAULT_IOS_SIGN_IDENTITY}"
IOS_PROVISIONING_PROFILE="${IOS_PROVISIONING_PROFILE:-$DEFAULT_IOS_PROVISIONING_PROFILE}"
IOS_TRIPLE="${IOS_TRIPLE:-}"  # Auto-detect if empty

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/native}"
IOS_TARGET="XExcalidraw"
MAC_TARGET="XExcalidraw"
IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.xexcalidraw.ios}"
MAC_BUNDLE_ID="${MAC_BUNDLE_ID:-com.xexcalidraw.macos}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

SWIFTPM_COMMON=(
  --cache-path "$SWIFTPM_CACHE"
  --config-path "$SWIFTPM_CONFIG"
  --security-path "$SWIFTPM_SECURITY"
  --scratch-path "$SWIFTPM_SCRATCH"
  --manifest-cache local
  --disable-sandbox
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") [ios|macos|all|ios-app|macos-app|app|ios-device|ios-deploy]

Commands:
  ios              Build iOS library (simulator)
  macos            Build macOS library
  all              Build both iOS and macOS libraries
  ios-app          Build iOS app bundle (simulator)
  macos-app        Build macOS app bundle
  app              Build both iOS and macOS app bundles
  ios-device       Build iOS app for physical device (requires signing config)
  ios-deploy       Build and deploy iOS app to connected device via ios-deploy

Device Build Setup:
  1. Edit DEFAULT_IOS_SIGN_IDENTITY in this script
  2. Edit DEFAULT_IOS_PROVISIONING_PROFILE in this script
  3. Or use environment variables: IOS_SIGN_IDENTITY, IOS_PROVISIONING_PROFILE

Env vars:
  CONFIGURATION   Build config (Debug/Release). Default: Debug
  IOS_SDK          iOS SDK name for xcrun. Default: iphonesimulator
  IOS_VERSION      iOS deployment version for triple. Default: 16.0
  IOS_ARCH         iOS simulator arch (arm64 or x86_64). Default: host arch
  IOS_TRIPLE       Override target triple (e.g. arm64-apple-ios16.0-simulator)
  SWIFTPM_ROOT     Override SwiftPM cache root. Default: .swiftpm (repo root)
  OUTPUT_DIR       App bundle output directory. Default: build/native
  IOS_BUNDLE_ID    iOS bundle identifier. Default: com.xexcalidraw.ios
  MAC_BUNDLE_ID    macOS bundle identifier. Default: com.xexcalidraw.macos
  MARKETING_VERSION  CFBundleShortVersionString. Default: 1.0
  BUILD_NUMBER       CFBundleVersion. Default: 1
  IOS_DEVICE_BUILD Build for physical device (1/0). Default: 0
  IOS_INSTALL      Install to booted simulator (1/0). Default: 0
  IOS_DEVICE       Simulator UDID or 'booted'. Default: booted
  IOS_SIGN_IDENTITY  Code signing identity for device builds (required for device)
  IOS_PROVISIONING_PROFILE  Path to provisioning profile (required for device)
  IOS_DEPLOY       Install to physical device via ios-deploy (1/0). Default: 0
  IOS_DEPLOY_ARGS  Additional arguments for ios-deploy

Examples:
  # Build for device and install via ios-deploy
  IOS_DEVICE_BUILD=1 IOS_SIGN_IDENTITY="Apple Development" IOS_DEPLOY=1 ./scripts/build_native.sh ios-app
  $0 all
  CONFIGURATION=Release $0 macos
  IOS_VERSION=17.0 $0 ios
  $0 app
  IOS_INSTALL=1 $0 ios-app
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Invalid CONFIGURATION: $CONFIGURATION_RAW (use Debug or Release)" >&2
  exit 1
fi

prepare_swiftpm_paths() {
  mkdir -p \
    "$SWIFTPM_CACHE" \
    "$SWIFTPM_CONFIG" \
    "$SWIFTPM_SECURITY" \
    "$SWIFTPM_SCRATCH" \
    "$SWIFTPM_HOME" \
    "$CLANG_MODULE_CACHE"

  export HOME="$SWIFTPM_HOME"
  export XDG_CACHE_HOME="$SWIFTPM_CACHE"
  export XDG_CONFIG_HOME="$SWIFTPM_CONFIG"
  export XDG_DATA_HOME="$SWIFTPM_ROOT/data"
  export CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE"
}

ensure_packages() {
  if [[ ! -f "$IOS_PACKAGE/Package.swift" ]]; then
    echo "iOS Package.swift not found: $IOS_PACKAGE/Package.swift" >&2
    exit 1
  fi

  if [[ ! -f "$MAC_PACKAGE/Package.swift" ]]; then
    echo "macOS Package.swift not found: $MAC_PACKAGE/Package.swift" >&2
    exit 1
  fi
}

ios_sdk_path() {
  local sdk="$1"
  xcrun --sdk "$sdk" --show-sdk-path
}

resolve_ios_settings() {
  # Auto-detect SDK and triple based on device build setting
  if [[ -z "$IOS_SDK" ]]; then
    if [[ "$IOS_DEVICE_BUILD" == "1" ]]; then
      IOS_SDK="iphoneos"
    else
      IOS_SDK="iphonesimulator"
    fi
  fi
  
  if [[ -z "$IOS_TRIPLE" ]]; then
    if [[ "$IOS_DEVICE_BUILD" == "1" ]]; then
      IOS_TRIPLE="$IOS_ARCH-apple-ios$IOS_VERSION"
    else
      IOS_TRIPLE="$IOS_ARCH-apple-ios$IOS_VERSION-simulator"
    fi
  fi
}

swiftpm_bin_path_ios() {
  resolve_ios_settings
  local sdk_path
  sdk_path="$(ios_sdk_path "$IOS_SDK")"
  swift build \
    --package-path "$IOS_PACKAGE" \
    --configuration "$CONFIGURATION" \
    "${SWIFTPM_COMMON[@]}" \
    -Xcc -isysroot -Xcc "$sdk_path" \
    -Xlinker -syslibroot -Xlinker "$sdk_path" \
    --sdk "$sdk_path" \
    --triple "$IOS_TRIPLE" \
    --show-bin-path
}

swiftpm_bin_path_macos() {
  swift build \
    --package-path "$MAC_PACKAGE" \
    --configuration "$CONFIGURATION" \
    "${SWIFTPM_COMMON[@]}" \
    --show-bin-path
}

build_ios() {
  echo "==> Building iOS ($CONFIGURATION)"
  resolve_ios_settings
  prepare_swiftpm_paths
  
  echo "    SDK: $IOS_SDK, Triple: $IOS_TRIPLE"
  
  local sdk_path
  sdk_path="$(ios_sdk_path "$IOS_SDK")"
  if [[ -z "$sdk_path" ]]; then
    echo "Failed to resolve SDK path for $IOS_SDK" >&2
    exit 1
  fi
  swift build \
    --package-path "$IOS_PACKAGE" \
    --configuration "$CONFIGURATION" \
    "${SWIFTPM_COMMON[@]}" \
    -Xcc -isysroot -Xcc "$sdk_path" \
    -Xlinker -syslibroot -Xlinker "$sdk_path" \
    --sdk "$sdk_path" \
    --triple "$IOS_TRIPLE"
}

build_macos() {
  echo "==> Building macOS ($CONFIGURATION)"
  prepare_swiftpm_paths
  swift build \
    --package-path "$MAC_PACKAGE" \
    --configuration "$CONFIGURATION" \
    "${SWIFTPM_COMMON[@]}"
}

write_ios_info_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>XExcalidraw</string>
  <key>CFBundleExecutable</key>
  <string>$IOS_TARGET</string>
  <key>CFBundleIdentifier</key>
  <string>$IOS_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$IOS_TARGET</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconName</key>
      <string>AppIcon</string>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon60x60</string>
      </array>
      <key>UILaunchImages</key>
      <array/>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconName</key>
      <string>AppIcon</string>
      <key>CFBundleIconFiles</key>
      <array>
        <string>AppIcon60x60</string>
        <string>AppIcon76x76</string>
      </array>
      <key>UILaunchImages</key>
      <array/>
    </dict>
  </dict>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>MinimumOSVersion</key>
  <string>$IOS_VERSION</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>iPhoneSimulator</string>
  </array>
  <key>UIDeviceFamily</key>
  <array>
    <integer>1</integer>
    <integer>2</integer>
  </array>
  <key>UILaunchScreen</key>
  <dict/>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
  </dict>
</dict>
</plist>
PLIST
}

write_macos_info_plist() {
  local plist_path="$1"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>XExcalidraw</string>
  <key>CFBundleExecutable</key>
  <string>$MAC_TARGET</string>
  <key>CFBundleIdentifier</key>
  <string>$MAC_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$MAC_TARGET</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

compile_assets() {
  local xcassets_path="$1"
  local output_dir="$2"
  local platform="$3"
  local min_version="$4"
  
  if [[ ! -d "$xcassets_path" ]]; then
    return 0
  fi
  
  echo "==> Compiling Assets.xcassets ($platform)"
  mkdir -p "$output_dir"
  
  xcrun actool \
    --compile "$output_dir" \
    --platform "$platform" \
    --minimum-deployment-target "$min_version" \
    --app-icon AppIcon \
    --output-partial-info-plist "$output_dir/Assets-partial.plist" \
    "$xcassets_path" 2>&1 | grep -v "^-" || true
  
  # For macOS, also generate a proper .icns file with all sizes using iconutil
  if [[ "$platform" == "macosx" ]]; then
    generate_macos_icns "$xcassets_path" "$output_dir"
  fi
}

generate_macos_icns() {
  local xcassets_path="$1"
  local output_dir="$2"
  local iconset_dir="/tmp/AppIcon.iconset"
  
  rm -rf "$iconset_dir"
  mkdir -p "$iconset_dir"
  
  # Get the appiconset path
  local appiconset_path="$xcassets_path/AppIcon.appiconset"
  
  # Copy and rename icon files to iconset format
  # macOS icon sizes: 16x16, 32x32, 128x128, 256x256, 512x512 (each with 1x and 2x)
  local sizes=("16" "32" "128" "256" "512")
  
  for size in "${sizes[@]}"; do
    local file1x="$appiconset_path/${size}.png"
    local file2x="$appiconset_path/${size}@2x.png"
    
    if [[ -f "$file1x" ]]; then
      cp "$file1x" "$iconset_dir/icon_${size}x${size}.png"
    fi
    if [[ -f "$file2x" ]]; then
      cp "$file2x" "$iconset_dir/icon_${size}x${size}@2x.png"
    fi
  done
  
  # Generate .icns file
  if command -v iconutil &> /dev/null; then
    iconutil -c icns "$iconset_dir" -o "$output_dir/AppIcon.icns"
    echo "Generated AppIcon.icns with all sizes"
  else
    echo "iconutil not available, using actool generated icns"
  fi
  
  rm -rf "$iconset_dir"
}

copy_resource_bundles() {
  local bin_path="$1"
  local dest_dir="$2"
  local bundle
  while IFS= read -r -d '' bundle; do
    cp -R "$bundle" "$dest_dir/"
  done < <(find "$bin_path" -maxdepth 1 -name "*.bundle" -print0)
}

ensure_web_dist() {
  if [[ ! -f "$WEB_DIST_DIR/index.html" ]]; then
    echo "==> Building web bundle"
    "$ROOT_DIR/scripts/build_web.sh"
    return
  fi
  if find "$WEB_DIR/src" "$WEB_DIR/index.html" "$WEB_DIR/package.json" "$WEB_DIR/vite.config.ts" -type f -newer "$WEB_DIST_DIR/index.html" | grep -q .; then
    echo "==> Rebuilding web bundle (sources changed)"
    "$ROOT_DIR/scripts/build_web.sh"
  fi
}

copy_web_dist() {
  local dest_dir="$1"
  if [[ -f "$WEB_DIST_DIR/index.html" ]]; then
    mkdir -p "$dest_dir"
    rsync -a "$WEB_DIST_DIR/" "$dest_dir/"
  else
    echo "Web dist not found at $WEB_DIST_DIR (skipping)"
  fi
}

check_ios_deploy() {
  if ! command -v ios-deploy &> /dev/null; then
    echo "Error: ios-deploy is not installed." >&2
    echo "Install with: npm install -g ios-deploy" >&2
    echo "Or: brew install ios-deploy" >&2
    exit 1
  fi
}

build_ios_xcode() {
  local project_path="$ROOT_DIR/apps/_legacy_xcode/ExcalidrawIOS.xcodeproj"
  local scheme="ExcalidrawIOS"
  local config="$CONFIGURATION_RAW"
  local sdk="$IOS_SDK"
  
  if [[ -z "$sdk" ]]; then
    [[ "$IOS_DEVICE_BUILD" == "1" ]] && sdk="iphoneos" || sdk="iphonesimulator"
  fi
  
  echo "==> Building iOS with xcodebuild ($config, $sdk)"
  echo "    Using Xcode project: $project_path"
  
  # Build for device - Xcode will handle signing with configured team
  xcodebuild \
    -project "$project_path" \
    -scheme "$scheme" \
    -configuration "$config" \
    -sdk "$sdk" \
    -derivedDataPath "$OUTPUT_DIR/ios_derived" \
    build
}

bundle_ios_app() {
  local use_xcodebuild="${USE_XCODEBUILD:-1}"
  
  # For device builds, use xcodebuild by default (required for free developer accounts)
  if [[ "$IOS_DEVICE_BUILD" == "1" && "$use_xcodebuild" == "1" ]]; then
    build_ios_xcode
    
    # Find the built app
    local app_path=$(find "$OUTPUT_DIR/ios_derived" -name "*.app" -type d | head -1)
    if [[ -z "$app_path" ]]; then
      echo "Error: Could not find built .app bundle" >&2
      exit 1
    fi
    
    local app_dir="$OUTPUT_DIR/ios/$IOS_TARGET.app"
    rm -rf "$app_dir"
    mkdir -p "$OUTPUT_DIR/ios"
    cp -R "$app_path" "$app_dir"
    echo "iOS app bundle: $app_dir"
    
    # Deploy to physical device via ios-deploy
    if [[ "${IOS_DEPLOY:-0}" == "1" ]]; then
      check_ios_deploy
      echo "==> Installing to device via ios-deploy"
      ios-deploy --bundle "$app_dir" ${IOS_DEPLOY_ARGS:-} --justlaunch
      return
    fi
    return
  fi
  
  # Simulator build - use SwiftPM (original method)
  build_ios
  ensure_web_dist
  local bin_path
  bin_path="$(swiftpm_bin_path_ios)"
  local app_dir="$OUTPUT_DIR/ios/$IOS_TARGET.app"
  rm -rf "$app_dir"
  mkdir -p "$app_dir"
  cp "$bin_path/$IOS_TARGET" "$app_dir/$IOS_TARGET"
  chmod +x "$app_dir/$IOS_TARGET"
  write_ios_info_plist "$app_dir/Info.plist"
  copy_resource_bundles "$bin_path" "$app_dir"
  
  # Compile Assets.xcassets if exists
  local xcassets_path="$IOS_PACKAGE/Sources/ExcalidrawIOS/Resources/Assets.xcassets"
  if [[ -d "$xcassets_path" ]]; then
    local platform="iphonesimulator"
    [[ "$IOS_DEVICE_BUILD" == "1" ]] && platform="iphoneos"
    compile_assets "$xcassets_path" "$app_dir" "$platform" "$IOS_VERSION"
  fi
  
  copy_web_dist "$app_dir"
  
  # Ad-hoc code sign for simulator
  codesign --force --sign - --timestamp=none "$app_dir/$IOS_TARGET" 2>/dev/null || true
  
  echo "iOS app bundle: $app_dir"

  if [[ "${IOS_INSTALL:-0}" == "1" ]]; then
    local device="${IOS_DEVICE:-booted}"
    xcrun simctl install "$device" "$app_dir"
    xcrun simctl launch "$device" "$IOS_BUNDLE_ID"
  fi
}

bundle_macos_app() {
  build_macos
  ensure_web_dist
  local bin_path
  bin_path="$(swiftpm_bin_path_macos)"
  local app_dir="$OUTPUT_DIR/macos/$MAC_TARGET.app"
  local contents_dir="$app_dir/Contents"
  local macos_dir="$contents_dir/MacOS"
  local resources_dir="$contents_dir/Resources"
  rm -rf "$app_dir"
  mkdir -p "$macos_dir" "$resources_dir"
  cp "$bin_path/$MAC_TARGET" "$macos_dir/$MAC_TARGET"
  chmod +x "$macos_dir/$MAC_TARGET"
  write_macos_info_plist "$contents_dir/Info.plist"
  copy_resource_bundles "$bin_path" "$resources_dir"
  
  # Compile Assets.xcassets if exists
  local xcassets_path="$MAC_PACKAGE/Sources/ExcalidrawMac/Resources/Assets.xcassets"
  if [[ -d "$xcassets_path" ]]; then
    compile_assets "$xcassets_path" "$resources_dir" "macosx" "13.0"
  fi
  
  copy_web_dist "$resources_dir"
  
  # Ad-hoc code sign the executable
  codesign --force --sign - --timestamp=none "$macos_dir/$MAC_TARGET" 2>/dev/null || true
  
  echo "macOS app bundle: $app_dir"
}

ensure_packages

TARGET="${1:-all}"
case "$TARGET" in
  ios)
    build_ios
    ;;
  macos)
    build_macos
    ;;
  all)
    build_ios
    build_macos
    ;;
  ios-app)
    bundle_ios_app
    ;;
  macos-app)
    bundle_macos_app
    ;;
  app)
    bundle_ios_app
    bundle_macos_app
    ;;
  ios-device)
    IOS_DEVICE_BUILD=1
    bundle_ios_app
    ;;
  ios-deploy)
    IOS_DEVICE_BUILD=1
    IOS_DEPLOY=1
    bundle_ios_app
    ;;
  *)
    usage
    exit 2
    ;;
esac
