#!/usr/bin/env bash
set -euo pipefail

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

IOS_SDK="${IOS_SDK:-iphonesimulator}"
IOS_VERSION="${IOS_VERSION:-16.0}"
IOS_ARCH="${IOS_ARCH:-$(uname -m | sed 's/x86_64/x86_64/;s/arm64/arm64/')}"
IOS_TRIPLE="${IOS_TRIPLE:-$IOS_ARCH-apple-ios${IOS_VERSION}-simulator}"

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/native}"
IOS_TARGET="ExcalidrawIOS"
MAC_TARGET="ExcalidrawMac"
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
Usage: $(basename "$0") [ios|macos|all|ios-app|macos-app|app]

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
  IOS_INSTALL      Install to booted simulator (1/0). Default: 0
  IOS_DEVICE       Simulator UDID or 'booted'. Default: booted

Examples:
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
  xcrun --sdk "$IOS_SDK" --show-sdk-path
}

swiftpm_bin_path_ios() {
  local sdk_path
  sdk_path="$(ios_sdk_path)"
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
  prepare_swiftpm_paths
  local sdk_path
  sdk_path="$(ios_sdk_path)"
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
  <string>Excalidraw</string>
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
  <string>Excalidraw</string>
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

bundle_ios_app() {
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
    compile_assets "$xcassets_path" "$app_dir" "iphonesimulator" "$IOS_VERSION"
  fi
  
  copy_web_dist "$app_dir"
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
  *)
    usage
    exit 2
    ;;
esac
