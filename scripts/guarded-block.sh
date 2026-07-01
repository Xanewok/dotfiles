#!/usr/bin/env bash
set -euo pipefail

# ensure_guarded_block TARGET NAME COMMENT_PREFIX BODY
# Append the block if absent; replace its body if present. A start marker with no
# end marker is malformed: leave the file untouched and warn (never guess which
# lines are "the block").
# Precondition: BODY must not contain a marker line (bodies are static config).
ensure_guarded_block() {
  local target=$1 name=$2 prefix=$3 body=$4
  local start="$prefix >>> $name >>>"
  local end="$prefix <<< $name <<<"

  mkdir -p "$(dirname "$target")"
  [ -e "$target" ] || touch "$target"   # create if missing; don't bump mtime otherwise

  local tmp rc=0
  tmp=$(mktemp "${TMPDIR:-/tmp}/guarded-block.XXXXXX")

  # Markers/BODY are passed as env vars (read via ENVIRON), NOT `awk -v`, on
  # purpose: `-v` applies backslash-escape processing and would mangle a body
  # containing '\'. The rule order below is also load-bearing.
  start=$start end=$end body=$body awk '
    BEGIN {
      start = ENVIRON["start"]
      end   = ENVIRON["end"]
      body  = ENVIRON["body"]
    }

    $0 == start && !done { holding = 1; next }

    holding && $0 == end {
      print start ORS body ORS end
      holding = 0
      done = 1
      next
    }

    holding { next }
    { print }

    END {
      if (holding) exit 3   # start seen but no end: signal "leave the file alone"
      else if (!done) {
        if (NR > 0) print ""
        print start ORS body ORS end
      }
    }
  ' "$target" > "$tmp" || rc=$?

  if [ "$rc" -eq 3 ]; then
    warn "unterminated guarded block '$name' in $target; left unchanged"
    rm -f "$tmp"
    return 0
  fi
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; die "guarded-block: awk failed on $target"; }

  cmp -s "$tmp" "$target" || cat "$tmp" > "$target"   # write only if changed
  rm -f "$tmp"
}
