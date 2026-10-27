#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
build_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build "${build_options[@]}"
binary_dir="$(swift build --show-bin-path "${build_options[@]}")"
model_sources=(Sources/MeetingHelper/*.swift)
model_sources=("${(@)model_sources:#*MeetingHelperApp.swift}")
if [[ -f "$binary_dir/MeetingCore.o" ]]; then
    core_objects=("$binary_dir/MeetingCore.o")
    module_dir="$binary_dir"
else
    core_objects=("$binary_dir"/MeetingCore.build/*.o)
    module_dir="$binary_dir/Modules"
fi
swiftc -parse-as-library -I "$module_dir" -module-cache-path .build/module-cache \
    "${model_sources[@]}" scripts/ChatHistoryProbe.swift "${core_objects[@]}" -o .build/chat-history-probe
.build/chat-history-probe
