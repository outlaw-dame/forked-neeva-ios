#!/usr/bin/env bash

# Render Client/APIConfig.xcconfig from Client/APIConfig-sample.xcconfig.
# Values are read from environment variables referenced by the template.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
template_path="${repo_root}/Client/APIConfig-sample.xcconfig"
output_path="${repo_root}/Client/APIConfig.xcconfig"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to render ${output_path}" >&2
  exit 127
fi

if [[ ! -f "${template_path}" ]]; then
  echo "Missing config template: ${template_path}" >&2
  exit 66
fi

tmp_output="$(mktemp "${output_path}.tmp.XXXXXX")"
cleanup() {
  rm -f -- "${tmp_output}"
}
trap cleanup EXIT

python3 - "${template_path}" "${tmp_output}" <<'PY'
import os
import pathlib
import re
import sys

_, template_arg, output_arg = sys.argv
template_path = pathlib.Path(template_arg)
output_path = pathlib.Path(output_arg)
placeholder_pattern = re.compile(r"\$([A-Z][A-Z0-9_]*)")
missing = set()


def escape_xcconfig_value(value: str) -> str:
    return (
        value
        .replace("$", "$$")
        .replace("\\", "\\\\")
        .replace("//", "/$()/")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace('"', '\\"')
    )


def replacement(match) -> str:
    name = match.group(1)
    value = os.environ.get(name)
    if value is None:
        missing.add(name)
        value = ""
    return escape_xcconfig_value(value)

rendered = placeholder_pattern.sub(
    replacement,
    template_path.read_text(encoding="utf-8"),
)

if missing:
    print(
        "Rendering config with empty values for unset variables: "
        + ", ".join(sorted(missing)),
        file=sys.stderr,
    )

output_path.write_text(rendered, encoding="utf-8")
PY

chmod 600 "${tmp_output}"
mv -- "${tmp_output}" "${output_path}"
trap - EXIT

echo "Rendered config: ${output_path}" >&2
