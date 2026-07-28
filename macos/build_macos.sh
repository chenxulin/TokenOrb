#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
dist_dir="$script_dir/dist"
app_dir="$dist_dir/TokenOrb.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
plist_path="$contents_dir/Info.plist"
login_items_dir="$contents_dir/Library/LoginItems"
watcher_app_dir="$login_items_dir/TokenOrbWatcher.app"
watcher_contents_dir="$watcher_app_dir/Contents"
watcher_macos_dir="$watcher_contents_dir/MacOS"
watcher_plist_path="$watcher_contents_dir/Info.plist"
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
  --arch arm64 \
  --scratch-path "$arm64_scratch" \
  --product TokenOrbWatcher

swift build \
  --package-path "$script_dir" \
  --configuration release \
  --arch x86_64 \
  --scratch-path "$x86_64_scratch" \
  --product TokenOrbWatcher

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
mkdir -p "$macos_dir" "$resources_dir" "$watcher_macos_dir"

lipo -create \
  "$arm64_bin_dir/TokenOrb" \
  "$x86_64_bin_dir/TokenOrb" \
  -output "$macos_dir/TokenOrb"
chmod 755 "$macos_dir/TokenOrb"

lipo -create \
  "$arm64_bin_dir/TokenOrbWatcher" \
  "$x86_64_bin_dir/TokenOrbWatcher" \
  -output "$watcher_macos_dir/TokenOrbWatcher"
chmod 755 "$watcher_macos_dir/TokenOrbWatcher"

plutil -create xml1 "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TokenOrb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string TokenOrb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.chenxulin.TokenOrb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string TokenOrb" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.5.2" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1.5.2" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright © chenxulin" "$plist_path"

plutil -create xml1 "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string zh_CN" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string TokenOrb" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string TokenOrbWatcher" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.chenxulin.TokenOrb.Watcher" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string TokenOrb" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 1.5.2" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string 1.5.2" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 13.0" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$watcher_plist_path"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright © chenxulin" "$watcher_plist_path"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$watcher_app_dir"
  codesign --force --sign - "$app_dir"
fi

disk_image_stage="$dist_dir/disk-image"
mkdir -p "$disk_image_stage"
ditto "$app_dir" "$disk_image_stage/TokenOrb.app"
ln -s /Applications "$disk_image_stage/Applications"
hdiutil create \
  -quiet \
  -volname "TokenOrb" \
  -srcfolder "$disk_image_stage" \
  -ov \
  -format UDZO \
  "$dist_dir/TokenOrb-macOS.dmg"
rm -rf "$disk_image_stage"

source_stage="$dist_dir/TokenOrb-macOS-source"
mkdir -p "$source_stage/macos"
ditto "$script_dir/Sources" "$source_stage/macos/Sources"
cp "$script_dir/Package.swift" "$source_stage/macos/Package.swift"
cp "$script_dir/build_macos.sh" "$source_stage/macos/build_macos.sh"
cp "$script_dir/README.md" "$source_stage/macos/README.md"
cp "$repo_root/README.md" "$source_stage/README.md"
cp "$repo_root/LICENSE" "$source_stage/LICENSE"
ditto -c -k --keepParent "$source_stage" "$dist_dir/TokenOrb-macOS-source.zip"
rm -rf "$source_stage"

(
  cd "$dist_dir"
  shasum -a 256 \
    "TokenOrb-macOS.dmg" \
    "TokenOrb-macOS-source.zip" \
    > "TokenOrb-macOS.sha256"
)

printf 'Built %s\n' "$app_dir"
printf 'Disk image %s\n' "$dist_dir/TokenOrb-macOS.dmg"
printf 'Source %s\n' "$dist_dir/TokenOrb-macOS-source.zip"
printf 'Checksum %s\n' "$dist_dir/TokenOrb-macOS.sha256"
