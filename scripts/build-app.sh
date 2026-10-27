#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
configuration="${1:-release}"
if [[ "$#" -gt 1 || ( "$configuration" != release && "$configuration" != debug ) ]]; then
    print -u2 'Usage: ./scripts/build-app.sh [release|debug]'
    exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
    print -u2 'MeetingHelper requires macOS with Swift 6.2+ and a macOS 26+ SDK.'
    exit 1
fi
xcrun --find swift >/dev/null
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
build_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build -c "$configuration" "${build_options[@]}"
binary_dir="$(swift build -c "$configuration" --show-bin-path "${build_options[@]}")"
app_dir="$PWD/dist/MeetingHelper.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MeetingHelper" "$app_dir/Contents/MacOS/MeetingHelper"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MeetingHelper.png LICENSE "$app_dir/Contents/Resources/"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign - --identifier com.meetinghelper.desktop "$app_dir"
codesign --verify --strict "$app_dir"
# Notify Launch Services that an existing local bundle has changed, including its icon.
touch "$app_dir"
print "Built $app_dir"
print 'Launch with: open dist/MeetingHelper.app'
