#!/usr/bin/env bash

#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/. */
#
# Bootstrap the Carthage dependencies. If the Carthage directory
# already exists then nothing is done. This speeds up builds on
# CI services where the Carthage directory can be cached.
#
# Use the --force option to force a rebuild of the dependencies.
# Use the --importLocales option to fetch and update locales only
#

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/lib/retry.sh
source "${script_dir}/Scripts/lib/retry.sh"

remove_path() {
  local path="$1"
  if [[ -e "${path}" || -L "${path}" ]]; then
    rm -rf -- "${path}"
  fi
}

getLocale()
{
  echo "Getting locale..."
  retry_with_backoff git clone --branch new_tool --single-branch https://github.com/boek/ios-l10n-scripts.git

  echo "Creating firefoxios-l10n Git repo"
  remove_path firefoxios-l10n
  retry_with_backoff git clone --depth 1 https://github.com/mozilla-l10n/firefoxios-l10n firefoxios-l10n
}

if [[ "${1:-}" == "--force" ]]; then
    remove_path firefoxios-l10n
    remove_path ios-l10n-scripts
    remove_path Carthage
    remove_path "${HOME}/Library/Caches/org.carthage.CarthageKit"
fi

if [[ "${1:-}" == "--importLocales" ]]; then
  # Import locales
  if [[ -d "firefoxios-l10n" && -d "ios-l10n-scripts" ]]; then
      echo "l10n directories found. Not downloading scripts."
  else
      echo "l10n directory not found. Downloading repo and scripts."
      getLocale
  fi

  ./ios-l10n-scripts/ios-l10n-tools --project-path Client.xcodeproj --l10n-project-path ./firefoxios-l10n --import
  exit 0
fi

# Build generated config
bash Scripts/build-api-config.sh

# Run carthage
bash carthage_command.sh

# Install Node.js dependencies and build user scripts
if [[ -f package-lock.json ]]; then
  retry_with_backoff npm ci
else
  retry_with_backoff npm install
fi
npm run build

# swift-format
if [[ "${SKIP_SWIFT_FORMAT_BUILD:-0}" == "1" ]]; then
  echo "Skipping swift-format build because SKIP_SWIFT_FORMAT_BUILD=1" >&2
else
  retry_with_backoff git submodule update --init --recursive swift-format
  (
    cd swift-format
    swift build -c release
  )
fi
