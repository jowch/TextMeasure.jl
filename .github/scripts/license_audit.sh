#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# License-audit gate for the demos milestone (#J).
#
# Every Julia source file under examples/ MUST carry an SPDX MIT header
# (`# SPDX-License-Identifier: MIT`) within its first few lines. This guards
# against demo source drifting in without a license marker.
#
# Scope: *.jl files under examples/. Data files (.toml/.shp/.json/.pdf/.png/...),
# READMEs, and Manifest/Project metadata are intentionally NOT audited — they
# cannot carry a comment header.
#
# The asteroid TUI (examples/asteroid_tui, #E) is WIP and not yet on main; it is
# excluded here and folded into the audit when #E merges.
#
# Usage: bash .github/scripts/license_audit.sh
# Exit 0 if every audited file has a header; exit 1 (listing offenders) otherwise.

set -euo pipefail

EXPECTED="SPDX-License-Identifier: MIT"
# How many leading lines to scan for the header (allows a shebang / blank line first).
HEAD_LINES=5

missing=()
total=0

while IFS= read -r -d '' f; do
  total=$((total + 1))
  if ! head -n "$HEAD_LINES" "$f" | grep -qF "$EXPECTED"; then
    missing+=("$f")
  fi
done < <(find examples -type f -name '*.jl' -not -path 'examples/asteroid_tui/*' -print0)

echo "license-audit: scanned ${total} Julia source file(s) under examples/ for '${EXPECTED}'"

if [ "${#missing[@]}" -ne 0 ]; then
  echo "::error::license-audit FAILED — ${#missing[@]} file(s) missing the SPDX MIT header:"
  for f in "${missing[@]}"; do
    echo "  - $f"
    # Emit a GitHub annotation on the offending file so it surfaces in the PR diff.
    echo "::error file=${f},line=1::Missing '# ${EXPECTED}' header"
  done
  exit 1
fi

echo "license-audit: OK — all ${total} file(s) carry the SPDX MIT header."
