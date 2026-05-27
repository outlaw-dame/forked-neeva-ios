#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/retry.sh
source "${script_dir}/Scripts/lib/retry.sh"

if ! command -v carthage >/dev/null 2>&1; then
  echo "carthage is required. Install it with: brew install carthage" >&2
  exit 127
fi

deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-14.0}"
if [[ ! "${deployment_target}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "Invalid IPHONEOS_DEPLOYMENT_TARGET: ${deployment_target}" >&2
  exit 64
fi

tmp_xcconfig="$(mktemp "${TMPDIR:-/tmp}/neeva-carthage.XXXXXX")"
cleanup() {
  rm -f -- "${tmp_xcconfig}"
}
trap cleanup EXIT

{
  echo 'EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64=arm64 arm64e armv7 armv7s armv6 armv8'
  echo 'EXCLUDED_ARCHS=$(inherited) $(EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_$(EFFECTIVE_PLATFORM_SUFFIX)__NATIVE_ARCH_64_BIT_$(NATIVE_ARCH_64_BIT))'
  echo "IPHONEOS_DEPLOYMENT_TARGET=${deployment_target}"
  echo 'SWIFT_TREAT_WARNINGS_AS_ERRORS=NO'
  echo 'GCC_TREAT_WARNINGS_AS_ERRORS=NO'
} > "${tmp_xcconfig}"
chmod 600 "${tmp_xcconfig}"

export XCODE_XCCONFIG_FILE="${tmp_xcconfig}"

retry_with_backoff carthage bootstrap --platform ios --color auto --cache-builds --use-xcframeworks
