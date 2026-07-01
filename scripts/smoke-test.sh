#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "checking required files..."
for f in \
  install.sh \
  profiles/config.sh \
  profiles/dev.sh \
  scripts/guarded-block.sh \
  fragments/shell/loader.sh \
  resources/shell/git-prompt.sh; do
  test -f "$ROOT/$f" || { echo "missing: $f"; exit 1; }
done

echo "checking shell syntax..."
find "$ROOT" -name '*.sh' -type f -print0 | xargs -0 -n1 bash -n
bash -n "$ROOT/install.sh"

echo "ok"
