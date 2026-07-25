#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dist_dir="$script_dir/dist"
app_dir="$dist_dir/Token Orb.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
plist_path="$contents_dir/Info.plist"
arm64_scratch="$script_dir/.build/arm64"
x86_64_scratch="$script_dir/.build/x86_64"

swift build \
  --package-path "$script_dir" \
  --configuration release \
  --arch arm64 \
  --scratch-path "$arm64_scratch" \
  --product TokenOrb

swift build \
  --package-path "$script_dir" \
  --configuration release \
  --arch x86_64 \
  --scratch-path "$x86_64_scratch" \
  --product TokenOrb

arm64_bin_dir="$(swift build \
  --package-path "$script_dir" \
  --configuration release \
  --arch arm64 \
  --scratch-path "$arm64_scratch" \
  --show-bin-path)"

x86_64_bin_dir="$(swift build \
  --package-path "$script_dir" \
  --configuration release \
  --arch x86_64 \
  --scratch-path "$x86_64_scratch" \
  --show-bin-path)"

if [[ -e "$dist_dir" ]]; then
  find "$dist_dir" -depth -delete
fi
mkdir -p "$macos_dir" "$resources_dir"

lipo -create \
  "$arm64_bin_dir/TokenOrb" \
  "$x86_64_bin_dir/TokenOrb" \
  -output "$macos_dir/TokenOrb"
chmod 755 "$macos_dir/TokenOrb"

plutil -create xml1 "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Token Orb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string TokenOrb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.chenxulin.TokenOrb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string Token Orb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.4.0" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1.4.0" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright © chenxulin" "$plist_path"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$app_dir"
fi

ditto -c -k --keepParent "$app_dir" "$dist_dir/TokenOrb-macOS.zip"
(
  cd "$dist_dir"
  shasum -a 256 "TokenOrb-macOS.zip" > "TokenOrb-macOS.sha256"
)

printf 'Built %s\n' "$app_dir"
printf 'Archive %s\n' "$dist_dir/TokenOrb-macOS.zip"
printf 'Checksum %s\n' "$dist_dir/TokenOrb-macOS.sha256"
