#!/usr/bin/env bash
# statusline-cache.sh — composable Claude Code statusLine: context meter + prompt-cache warmth +
# current-segment burn (main+subagents) + rolling first-response latency.
#
# Segments are independent `render_* -> string` functions ('' => dropped), joined left→right by " │ ".
# The node-backed segments (burn, latency) are VENDORED siblings under cc/ + lib/ (self-contained — this
# copy runs on any machine with node, no bloosh-workspace checkout needed). See PROVENANCE.md for the
# .agents source of truth and the re-sync command (prices.json in particular drifts as Anthropic reprices).
#
# Additive + resilient (dotfiles doctrine): every external tool is guarded; a missing jq / node / transcript
# / GNU-date just drops that segment — it never errors out the status bar.
set -u

# self-locate so the vendored meters resolve wherever this script is installed (copied, not symlinked).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

in=$(cat)
command -v jq >/dev/null 2>&1 || { printf ''; exit 0; }   # no jq ⇒ render nothing, quietly

# snapshot rate_limits so the on-demand `heimr-usage --limits` back-out has a source (the payload is the only
# place these live). Written only when present; captured-time lets the reader flag a stale snapshot.
{ rl=$(printf '%s' "$in" | jq -c 'select(.rate_limits) | {captured: now, rate_limits: .rate_limits}' 2>/dev/null); [ -n "$rl" ] && printf '%s' "$rl" > "$HOME/.claude/.heimr-rate-limits.json"; } 2>/dev/null

# ── helpers ────────────────────────────────────────────────────────────────
kfmt()     { local n=$1; if [ "$n" -ge 1000 ] 2>/dev/null; then echo "$(( (n + 500) / 1000 ))k"; else echo "$n"; fi; }
winlabel() { case "$1" in 1000000) echo 1M ;; 200000) echo 200k ;; *) kfmt "$1" ;; esac; }

# ── cache warmth — a compact suffix fused onto the context meter: 🔥[Xm] warm (min left, [<1m] under a
# minute), ❄️ cold, ⏳ working. idle = now - last transcript ts; window = 1h/5m per the most recent cache-WRITE.
render_cache() {
  local tp; tp=$(printf '%s' "$in" | jq -r '.transcript_path // empty')
  [ -n "$tp" ] && [ -f "$tp" ] || return 0
  local tail80; tail80=$(tail -n 80 "$tp" 2>/dev/null)

  # Last CONVERSATIONAL record (skip meta records + sidechains): "type<TAB>stop_reason<TAB>timestamp"
  local last; last=$(printf '%s' "$tail80" | jq -rR 'fromjson?
      | select((.type=="user" or .type=="assistant") and .isSidechain != true)
      | "\(.type)\t\(.message.stop_reason // "")\t\(.timestamp // "")"' 2>/dev/null | tail -n1)
  [ -n "$last" ] || return 0
  local ltype lsr ts; IFS=$'\t' read -r ltype lsr ts <<< "$last"

  # WORKING ⇔ mid-turn; IDLE (awaiting you) ⇔ an assistant turn that handed control back.
  if ! { [ "$ltype" = assistant ] && { [ "$lsr" = end_turn ] || [ "$lsr" = stop_sequence ]; }; }; then
    printf '\342\217\263'                                                    # ⏳
    return 0
  fi
  [ -n "$ts" ] || return 0

  local win
  win=$(printf '%s' "$tail80" | jq -rR 'fromjson? | .message.usage.cache_creation
      | select(. != null)
      | if (.ephemeral_1h_input_tokens // 0) > 0 then "3600"
        elif (.ephemeral_5m_input_tokens // 0) > 0 then "300"
        else empty end' 2>/dev/null | tail -n1)
  [ -n "$win" ] || win=3600

  local then; then=$(date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${ts%.*}" +%s 2>/dev/null || true)
  [ -n "${then:-}" ] || return 0
  local idle=$(( $(date +%s) - then )); [ "$idle" -lt 0 ] && idle=0

  if [ "$idle" -lt "$win" ]; then
    local left=$((win - idle))
    if [ "$left" -ge 60 ]; then
      printf '\360\237\224\245[%dm]' $((left / 60))                          # 🔥[Xm]
    else
      printf '\360\237\224\245[<1m]'                                         # 🔥[<1m] — about to go cold, reuse now
    fi
  else
    printf '\342\235\204\357\270\217'                                        # ❄️
  fi
}

# ── segment: context meter — "759k/1M (76%)" ────────────────────────────────
# Reads CC's context_window payload directly (same fields as heimr context-meter.mjs).
# Colour trains a 200k ceiling without crying wolf: uncolored <200k (good), yellow ≥200k, orange ≥350k, red ≥500k.
ctx_color() {
  if   [ "$1" -ge 500000 ] 2>/dev/null; then printf '\033[31m'        # red — compact now
  elif [ "$1" -ge 350000 ] 2>/dev/null; then printf '\033[38;5;208m'  # orange
  elif [ "$1" -ge 200000 ] 2>/dev/null; then printf '\033[33m'        # yellow — past the 200k ceiling
  fi
}
render_ctx() {
  local used size pct
  read -r used size pct < <(printf '%s' "$in" | jq -r \
    '"\(.context_window.total_input_tokens // 0) \(.context_window.context_window_size // 0) \(.context_window.used_percentage // 0)"')

  if [ "${used:-0}" -gt 0 ] 2>/dev/null && [ "${size:-0}" -gt 0 ] 2>/dev/null; then
    local p=$(( (used * 100 + size / 2) / size ))             # integer round — locale-proof
    local c r; c=$(ctx_color "$used"); [ -n "$c" ] && r=$(printf '\033[0m') || r=''
    printf '%s%s%s/%s (%s%%)' "$c" "$(kfmt "$used")" "$r" "$(winlabel "$size")" "$p"
    # ⟳ compact now — a verdict on the fill number, so it sits right here. Red-zone only (≥500k); silent below.
    [ "$used" -ge 500000 ] 2>/dev/null && printf ' \033[31m\342\237\263 compact now\033[0m'
  elif [ -n "${pct:-}" ] && [ "$pct" != 0 ]; then
    printf '%s%%' "${pct%.*}"                                  # older CC: percentage only
  fi
}

# ── segment: current-segment burn (main + subagents) — vendored cost-meter ──
# 🧠 main + 🤖 subagent effective (input-equiv) tokens SINCE the last compaction — the ballooning number that
# says "compact when it's steep". Guarded so a missing node just drops the segment. Cheap: the line refreshes
# every 10s and the meter caches (warm tick ~80ms; one-time ~1s to prime a huge session's cache).
COST_METER="${COST_METER_BIN:-$SCRIPT_DIR/cc/cost-meter.mjs}"
render_cost() {
  command -v node >/dev/null 2>&1 || return 0
  [ -f "$COST_METER" ] || return 0
  printf '%s' "$in" | node "$COST_METER" 2>/dev/null
}

# ── segment: ⏱ rolling first-response latency (avg of last 5 turns) — the responsiveness gauge ──
# "How long from hitting enter to the reply starting?" Lower = snappier. Upper bound on TTFT (see the meter);
# noisy per-turn, so it's a 5-turn mean. Same guard pattern — a missing node just drops it.
LATENCY_METER="${LATENCY_METER_BIN:-$SCRIPT_DIR/cc/latency-meter.mjs}"
render_latency() {
  command -v node >/dev/null 2>&1 || return 0
  [ -f "$LATENCY_METER" ] || return 0
  printf '%s' "$in" | node "$LATENCY_METER" 2>/dev/null
}

# ── segment: 🔋 plan budget — rolling rate-limit windows straight from the payload (authoritative, no parse) ──
# Shows the TIGHTER of the two windows (5h throttle / 7d weekly cap) — the binding constraint — as budget LEFT
# (100−used%) + a ↻countdown to its refill (Xd/Xh/Xm). Colour drains green→red. Quiet until a window is ≥50%
# used (lean line while you have headroom). Tie → the window that refills slowest (the scarcer one). No limits ⇒ ''.
render_limits() {
  local now w best_rem='' best_reset='' best_label='' elevated=0
  now=$(date +%s)
  for w in "5h:five_hour" "7d:seven_day"; do
    local label=${w%%:*} key=${w#*:} used reset
    IFS=$'\t' read -r used reset < <(printf '%s' "$in" | jq -r --arg k "$key" '.rate_limits[$k] // {} | "\(.used_percentage // "")\t\(.resets_at // "")"' 2>/dev/null)
    case "${used:-}" in ''|null) continue;; esac
    local rem=$((100 - used))
    [ "$rem" -le 50 ] 2>/dev/null && elevated=1   # quiet until a window is ≥50% used
    # binding = least budget left; tie → later reset (refills slowest, so scarcer)
    if [ -z "$best_rem" ] || [ "$rem" -lt "$best_rem" ] 2>/dev/null \
       || { [ "$rem" -eq "$best_rem" ] 2>/dev/null && [ -n "$reset" ] && [ "$reset" != null ] && [ "${best_reset:-0}" != null ] && [ "$reset" -gt "${best_reset:-0}" ] 2>/dev/null; }; then
      best_rem=$rem; best_reset=$reset; best_label=$label
    fi
  done
  [ -n "$best_rem" ] && [ "$elevated" = 1 ] || return 0
  local c='' r=''
  if   [ "$best_rem" -le 10 ] 2>/dev/null; then c='\033[31m'        # red
  elif [ "$best_rem" -le 25 ] 2>/dev/null; then c='\033[38;5;208m'  # orange
  elif [ "$best_rem" -le 50 ] 2>/dev/null; then c='\033[33m'        # yellow
  fi
  [ -n "$c" ] && r='\033[0m'
  local tail=''
  if [ -n "$best_reset" ] && [ "$best_reset" != null ]; then
    local left=$((best_reset - now))
    if   [ "$left" -ge 86400 ] 2>/dev/null; then tail=" \342\206\273$((left/86400))d"
    elif [ "$left" -ge 3600 ]  2>/dev/null; then tail=" \342\206\273$((left/3600))h"
    elif [ "$left" -gt 0 ]     2>/dev/null; then tail=" \342\206\273$((left/60))m"
    fi
  fi
  printf '\360\237\224\213 %s %b%d%%%b%b' "$best_label" "$c" "$best_rem" "$r" "$tail"   # 🔋 <win> <rem>% ↻<reset>
}

# ── compose ─────────────────────────────────────────────────────────────────
# Context fill + cache warmth are ONE visual unit (space-joined: "759k/1M (76%) 🔥[3m]") — same window, two
# facets of the compact-or-continue call. Burn + latency + budget stay separate segments. Empty pieces drop.
ctx="$(render_ctx)"; warmth="$(render_cache)"
if [ -n "$ctx" ] && [ -n "$warmth" ]; then ctxunit="$ctx $warmth"; else ctxunit="$ctx$warmth"; fi
out=""
for seg in "$ctxunit" "$(render_cost)" "$(render_latency)" "$(render_limits)"; do
  [ -n "$seg" ] || continue
  if [ -n "$out" ]; then out="$out  │  $seg"; else out="$seg"; fi
done
printf '%s' "$out"
