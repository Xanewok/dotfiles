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

echo "checking guarded-block editor..."
. "$ROOT/scripts/lib.sh"
. "$ROOT/scripts/guarded-block.sh"

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/smoke-test.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT
rc="$tmpd/target.rc"

# Append: body must land verbatim (backslashes and $ are the historical mangling risks).
printf 'existing line\n' > "$rc"
body_v1='line with \backslash\ and $dollar'
ensure_guarded_block "$rc" "smoke" "#" "$body_v1" >/dev/null
grep -qF "$body_v1" "$rc" || die "smoke: append lost the body verbatim"

# Replace: new body in, old body out, surrounding content intact.
ensure_guarded_block "$rc" "smoke" "#" "body v2" >/dev/null
grep -qF "body v2" "$rc" || die "smoke: replace did not update the body"
if grep -qF "$body_v1" "$rc"; then die "smoke: replace left the old body behind"; fi
grep -qF "existing line" "$rc" || die "smoke: surrounding content was lost"

# Idempotency: same body again must be byte-identical.
before="$(cat "$rc")"
ensure_guarded_block "$rc" "smoke" "#" "body v2" >/dev/null
[ "$(cat "$rc")" = "$before" ] || die "smoke: re-run with same body changed the file"

# Malformed (start marker, no end): file must be left untouched.
grep -v '<<<' "$rc" > "$tmpd/malformed.rc"
cp "$tmpd/malformed.rc" "$tmpd/malformed.orig"
ensure_guarded_block "$tmpd/malformed.rc" "smoke" "#" "body v3" >/dev/null 2>&1
cmp -s "$tmpd/malformed.rc" "$tmpd/malformed.orig" || die "smoke: malformed block was modified"

# Removal: block and markers gone, surrounding content intact.
remove_guarded_block "$rc" "smoke" "#" >/dev/null
if grep -qF "body v2" "$rc"; then die "smoke: removal left the body behind"; fi
if grep -qF ">>>" "$rc"; then die "smoke: removal left markers behind"; fi
grep -qF "existing line" "$rc" || die "smoke: removal lost surrounding content"

# Removing an absent block is a no-op; a malformed block is left untouched.
before="$(cat "$rc")"
remove_guarded_block "$rc" "smoke" "#" >/dev/null
[ "$(cat "$rc")" = "$before" ] || die "smoke: no-op removal changed the file"
remove_guarded_block "$tmpd/malformed.rc" "smoke" "#" >/dev/null 2>&1
cmp -s "$tmpd/malformed.rc" "$tmpd/malformed.orig" || die "smoke: removal modified a malformed file"

echo "ok"
