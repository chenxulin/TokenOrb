#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if (( $# == 0 )); then
  printf 'Usage: %s <swift-package-command> [arguments...]\n' "$0" >&2
  exit 64
fi

swift_subcommand="$1"
shift

swift_exec="${TOKENORB_SWIFT_EXEC:-}"
if [[ -z "$swift_exec" ]] && command -v xcrun >/dev/null 2>&1; then
  swift_exec="$(xcrun --find swift 2>/dev/null || true)"
fi
if [[ -z "$swift_exec" ]]; then
  swift_exec="$(command -v swift || true)"
fi
if [[ -z "$swift_exec" || ! -x "$swift_exec" ]]; then
  printf 'Swift executable not found. Install Apple Command Line Tools or set TOKENORB_SWIFT_EXEC.\n' >&2
  exit 1
fi

state_dir="${TOKENORB_SWIFTPM_STATE_DIR:-$script_dir/.build/swiftpm-state}"
module_cache_dir="${TOKENORB_SWIFT_MODULE_CACHE_PATH:-$state_dir/module-cache}"
cache_dir="$state_dir/cache"
config_dir="$state_dir/config"
security_dir="$state_dir/security"

mkdir -p \
  "$module_cache_dir" \
  "$cache_dir" \
  "$config_dir" \
  "$security_dir"

# Swift can emit a misleading SDK/compiler version diagnostic when SwiftShims
# fails to build only because the default Clang module cache is not writable.
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$module_cache_dir}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$module_cache_dir}"

swiftpm_args=(
  --cache-path "$cache_dir"
  --config-path "$config_dir"
  --security-path "$security_dir"
)

disable_sandbox="${TOKENORB_SWIFTPM_DISABLE_SANDBOX:-auto}"
case "$disable_sandbox" in
  auto)
    if ! command -v sandbox-exec >/dev/null 2>&1 \
      || ! sandbox-exec -p '(version 1) (allow default)' /usr/bin/true >/dev/null 2>&1; then
      swiftpm_args+=(--disable-sandbox)
    fi
    ;;
  1|true|yes)
    swiftpm_args+=(--disable-sandbox)
    ;;
  0|false|no)
    ;;
  *)
    printf 'Invalid TOKENORB_SWIFTPM_DISABLE_SANDBOX value: %s\n' "$disable_sandbox" >&2
    printf 'Use auto, 1, or 0.\n' >&2
    exit 64
    ;;
esac

if [[ -n "${TOKENORB_SWIFT_SDK_PATH:-}" ]]; then
  if [[ ! -d "$TOKENORB_SWIFT_SDK_PATH" ]]; then
    printf 'Swift SDK not found: %s\n' "$TOKENORB_SWIFT_SDK_PATH" >&2
    exit 1
  fi
  swiftpm_args+=(--sdk "$TOKENORB_SWIFT_SDK_PATH")
fi

exec "$swift_exec" "$swift_subcommand" \
  "${swiftpm_args[@]}" \
  --package-path "$script_dir" \
  "$@"
