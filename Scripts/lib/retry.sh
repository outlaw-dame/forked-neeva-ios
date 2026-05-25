#!/usr/bin/env bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

if [[ -n "${NEEVA_RETRY_LIB_SOURCED:-}" ]]; then
  return 0
fi
NEEVA_RETRY_LIB_SOURCED=1
readonly NEEVA_RETRY_LIB_SOURCED

_is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

_is_non_negative_integer() {
  [[ "${1:-}" =~ ^(0|[1-9][0-9]*)$ ]]
}

retry_with_backoff() {
  if [[ "$#" -eq 0 ]]; then
    echo "retry_with_backoff: missing command" >&2
    return 64
  fi

  local max_attempts="${RETRY_MAX_ATTEMPTS:-5}"
  local initial_delay="${RETRY_INITIAL_DELAY_SECONDS:-2}"
  local max_delay="${RETRY_MAX_DELAY_SECONDS:-30}"

  if ! _is_positive_integer "$max_attempts"; then
    echo "retry_with_backoff: RETRY_MAX_ATTEMPTS must be a positive integer" >&2
    return 64
  fi
  if ! _is_non_negative_integer "$initial_delay"; then
    echo "retry_with_backoff: RETRY_INITIAL_DELAY_SECONDS must be a non-negative integer" >&2
    return 64
  fi
  if ! _is_non_negative_integer "$max_delay"; then
    echo "retry_with_backoff: RETRY_MAX_DELAY_SECONDS must be a non-negative integer" >&2
    return 64
  fi

  local attempt=1
  local delay="$initial_delay"
  local status=0

  while true; do
    "$@" && return 0
    status=$?

    if (( attempt >= max_attempts )); then
      echo "Command failed after ${attempt} attempt(s): $*" >&2
      return "$status"
    fi

    local sleep_for="$delay"
    if (( delay > 0 )); then
      # Apply equal jitter so capped delays still vary instead of collapsing
      # deterministically to RETRY_MAX_DELAY_SECONDS.
      local min_sleep=$(( delay / 2 ))
      sleep_for=$(( min_sleep + (RANDOM % (delay - min_sleep + 1)) ))
      if (( sleep_for > max_delay )); then
        sleep_for="$max_delay"
      fi
    fi

    echo "Command failed with status ${status}; retrying attempt $((attempt + 1))/${max_attempts} in ${sleep_for}s: $*" >&2
    sleep "$sleep_for"

    attempt=$(( attempt + 1 ))
    if (( delay == 0 )); then
      delay=1
    else
      delay=$(( delay * 2 ))
    fi
    if (( delay > max_delay )); then
      delay="$max_delay"
    fi
  done
}
