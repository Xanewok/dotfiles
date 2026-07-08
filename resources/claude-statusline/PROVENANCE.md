# claude-statusline — vendored from bloosh-workspace/.agents

The Claude Code statusLine and its two node-backed meters. Vendored here so the line is
**self-contained** — it renders on any machine with `node`, without a `bloosh-workspace`
checkout. `install.sh` copies this dir to `~/.config/xanewok-dotfiles/resources/claude-statusline/`
and jq-merges the `statusLine` command into `~/.claude/settings.json` (see `profiles/config.sh`).

## The line
```
759k/1M (76%)  │  🔥 warm 3m  │  🧠 692k /seg  ⟳ compact now  │  ⏱ 27s
   context fill    cache warmth    segment burn (main+sub eff)      responsiveness
```
- **context** (`render_ctx`, pure bash) — window fill; colour green→red as it grows.
- **cache warmth** (`render_cache`, pure bash) — 🔥 warm / ❄️ COLD / ⏳ working; TTL read from traffic.
- **burn** (`cc/cost-meter.mjs`) — 🧠 main + 🤖 subagent effective (input-equiv) tokens since the last
  compaction. Needs the pricer (`lib/usage.mjs` + `lib/prices.json`).
- **latency** (`cc/latency-meter.mjs`) — ⏱ mean first-response latency over the last 5 turns (upper
  bound on TTFT; see the file header). Standalone, no pricer.

## Source of truth & re-sync (the vendoring drift)
These four files are **byte-identical copies** — maintain them in `.agents`, re-sync here:
```
AG=~/repos/bloosh-workspace/.agents/bin/driver
cp "$AG/cc/cost-meter.mjs" "$AG/cc/latency-meter.mjs"  cc/
cp "$AG/lib/usage.mjs"     "$AG/lib/prices.json"       lib/
```
`prices.json` is the one that rots: when Anthropic reprices, update it in `.agents` and re-run the
copy above. `statusline-cache.sh` is NOT a copy — it's canonical here (meters resolved relative to its
own dir, not the `.agents` path) — edit it in place.
