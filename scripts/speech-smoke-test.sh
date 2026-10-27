#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
if [[ "$#" -ne 1 ]]; then
    print 'Usage: ./scripts/speech-smoke-test.sh /path/to/synthetic-fixture.aiff'
    exit 2
fi
# Build the actual production speech pipeline into a small file-only diagnostic.
swift build --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
binary_dir="$(swift build --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")"
if [[ -f "$binary_dir/MeetingCore.o" ]]; then
    core_objects=("$binary_dir/MeetingCore.o")
    module_dir="$binary_dir"
else
    core_objects=("$binary_dir"/MeetingCore.build/*.o)
    module_dir="$binary_dir/Modules"
fi
swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos26.0" \
    -module-cache-path "$PWD/.build/module-cache" -I "$module_dir" \
    Sources/MeetingHelper/LocalSpeech.swift scripts/SpeechProbe.swift "${core_objects[@]}" \
    -o .build/speech-probe
.build/speech-probe "$1"
