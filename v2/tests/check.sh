#!/usr/bin/env bash
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
while IFS= read -r -d '' file; do bash -n "$file"; done < <(find . -type f -name '*.sh' -print0)
shellcheck nik.sh lib/*.sh tests/check.sh
python3 tools/audit-items.py
python3 tools/audit-project.py
python3 -m unittest discover -s tests -p 'test_*.py'
bats tests/nik.bats
