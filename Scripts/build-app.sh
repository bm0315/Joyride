#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
configuration="${CONFIGURATION:-debug}"
app_dir="$project_dir/dist/Joyride.app"
contents_dir="$app_dir/Contents"
build_support_dir="$project_dir/.build-support"
module_cache_dir="$build_support_dir/clang-module-cache"
swiftpm_cache_dir="$build_support_dir/swiftpm-cache"
swiftpm_config_dir="$build_support_dir/swiftpm-config"
swiftpm_security_dir="$build_support_dir/swiftpm-security"
probe_file="$build_support_dir/sdk-probe.swift"

mkdir -p \
  "$module_cache_dir" \
  "$swiftpm_cache_dir" \
  "$swiftpm_config_dir" \
  "$swiftpm_security_dir"
printf '%s\n' 'import AppKit' 'import Network' 'import WebKit' > "$probe_file"

select_sdk() {
  local default_sdk candidate architecture
  default_sdk="$(xcrun --sdk macosx --show-sdk-path)"
  architecture="$(uname -m)"
  for candidate in \
    "${AGENT_AVATAR_SDK:-}" \
    "$default_sdk" \
    /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk
  do
    [[ -n "$candidate" && -d "$candidate" ]] || continue
    if CLANG_MODULE_CACHE_PATH="$module_cache_dir" swiftc \
      -sdk "$candidate" \
      -target "$architecture-apple-macos14.0" \
      -typecheck "$probe_file" >/dev/null 2>&1
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '%s\n' "No compatible macOS SDK was found for the installed Swift compiler." >&2
  return 1
}

sdk_path="$(select_sdk)"
swiftpm_options=(
  --package-path "$project_dir"
  --configuration "$configuration"
  --product Joyride
  --disable-sandbox
  --sdk "$sdk_path"
  --cache-path "$swiftpm_cache_dir"
  --config-path "$swiftpm_config_dir"
  --security-path "$swiftpm_security_dir"
)

SDKROOT="$sdk_path" CLANG_MODULE_CACHE_PATH="$module_cache_dir" swift build "${swiftpm_options[@]}"
binary_dir="$(SDKROOT="$sdk_path" CLANG_MODULE_CACHE_PATH="$module_cache_dir" swift build "${swiftpm_options[@]}" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources/packs"
cp "$binary_dir/Joyride" "$contents_dir/MacOS/Joyride"
cp "$project_dir/Packaging/Info.plist" "$contents_dir/Info.plist"
cp -R "$project_dir/Assets/packs/default" "$contents_dir/Resources/packs/default"

codesign --force --deep --sign - "$app_dir"
printf '%s\n' "$app_dir"
