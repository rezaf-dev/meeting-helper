#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "$#" -ne 0 ]]; then
    print -u2 'Usage: ./scripts/package-app.sh'
    exit 2
fi
./scripts/build-app.sh release
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
architecture="$(uname -m)"
archive="MeetingHelper-${version}-macOS-${architecture}.zip"
# ditto preserves the app bundle metadata and ad-hoc signature.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent dist/MeetingHelper.app "dist/$archive"
(cd dist && /usr/bin/shasum -a 256 "$archive" > "$archive.sha256")

# Stage only the app and installation shortcut, excluding other dist artifacts.
staging_dir="$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto dist/MeetingHelper.app "$staging_dir/MeetingHelper.app"
ln -s /Applications "$staging_dir/Applications"
disk_image="MeetingHelper-${version}-macOS-${architecture}.dmg"
/usr/bin/hdiutil create -ov -format UDZO -volname MeetingHelper \
    -srcfolder "$staging_dir" "dist/$disk_image"
/usr/bin/hdiutil verify "dist/$disk_image"
(cd dist && /usr/bin/shasum -a 256 "$disk_image" > "$disk_image.sha256")
print "Packaged dist/$archive"
print "Packaged dist/$disk_image"
