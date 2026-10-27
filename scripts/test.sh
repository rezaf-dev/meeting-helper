#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swiftc_path="$(xcrun --find swiftc)"
plugin_path="${swiftc_path:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
plugin_flags=()
if [[ -f "$plugin_path" ]]; then
    plugin_flags=(-Xswiftc -load-plugin-library -Xswiftc "$plugin_path")
fi
swift test --disable-sandbox --disable-xctest --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" "${plugin_flags[@]}"
