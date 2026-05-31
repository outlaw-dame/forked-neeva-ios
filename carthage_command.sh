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

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/neeva-carthage.XXXXXX")"
tmp_xcconfig="${tmp_dir}/neeva-carthage.xcconfig"
cleanup() {
  rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

{
  echo 'EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_simulator__NATIVE_ARCH_64_BIT_x86_64=arm64 arm64e armv7 armv7s armv6 armv8'
  echo 'EXCLUDED_ARCHS=$(inherited) $(EXCLUDED_ARCHS__EFFECTIVE_PLATFORM_SUFFIX_$(EFFECTIVE_PLATFORM_SUFFIX)__NATIVE_ARCH_64_BIT_$(NATIVE_ARCH_64_BIT))'
  echo "IPHONEOS_DEPLOYMENT_TARGET=${deployment_target}"
  echo 'SWIFT_TREAT_WARNINGS_AS_ERRORS=NO'
  echo 'GCC_TREAT_WARNINGS_AS_ERRORS=NO'
  # Fuzi 3.1.3 and other old Carthage deps have a macOS deployment target
  # below 10.10, causing Foundation type availability errors under Xcode 26+.
  echo 'MACOSX_DEPLOYMENT_TARGET=10.15'
} > "${tmp_xcconfig}"
chmod 600 "${tmp_xcconfig}"

export XCODE_XCCONFIG_FILE="${tmp_xcconfig}"

# Step 1: check out sources only — do NOT build yet.
retry_with_backoff carthage checkout

# Step 2: patch Fuzi's xcodeproj so its MACOSX_DEPLOYMENT_TARGET no longer
# falls below 10.10.  XCODE_XCCONFIG_FILE cannot override a setting that is
# hard-coded in a target's buildSettings block inside project.pbxproj, so we
# must fix it in-place before invoking the compiler.
# Fuzi 3.1.3 was last updated in 2020 and ships with MACOSX_DEPLOYMENT_TARGET
# as low as 10.9; Xcode 26+ treats that as an error for Foundation types.
fuzi_checkout="${script_dir}/Carthage/Checkouts/Fuzi"
if [[ -d "${fuzi_checkout}" ]]; then
  echo "Patching Fuzi MACOSX_DEPLOYMENT_TARGET → 10.15"
  find "${fuzi_checkout}" -name "*.pbxproj" -print0 | \
    xargs -0 sed -i '' \
      's/MACOSX_DEPLOYMENT_TARGET = [0-9][0-9.]*;/MACOSX_DEPLOYMENT_TARGET = 10.15;/g'
fi

# Step 3: build from the now-patched checkouts.
retry_with_backoff carthage build --platform ios --color auto --cache-builds --use-xcframeworks
