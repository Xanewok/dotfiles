#!/usr/bin/env node
// cost-meter.mjs — statusLine segment: what continuing costs, so "when to compact" is legible LIVE.
//
// Default unit is TOKENS (set COST_METER_USD=1 for dollars — notional on a flat-rate subscription, where the
// constraint is rate-limit burn + context quality, not money). Shown, all for the CURRENT segment (since the
// last compaction — a new segment starts from the compacted SUMMARY, not the dropped prefix, so these numbers
// reset at each compaction and then climb, which is the "ballooning" signal):
//   🧠 <tok> — MAIN-session burn this segment: every assistant turn re-reads the whole current window (hot
//              0.1× / cold 1.25–2×), and the window grows each turn, so this sum climbs ~quadratically within a
//              segment (Σ ≈ turns × avg-window). THIS is the number that says "compact — the segment is steep."
//   🤖 <tok> — subagent burn this segment. Subagents run in their own contexts and DON'T inflate the main
//              window, so a fanout / dynamic-workflow burst is invisible to the context meter. Summed from
//              <session>/subagents/*.jsonl.
//   Both are COST-WEIGHTED "effective (input-equivalent) tokens": reads 0.1×, cache writes 1.25×/2× (by TTL),
//   output ×5 — not raw throughput, so a cheap cache-read isn't tallied like an expensive output token.
//   💸 $/turn — (USD mode only) cost to re-read the whole window once (window × 0.1 × base input).
//   ⟳ compact — hint escalating with window fill (soon ≥50%, now ≥75%).
//
// Cheap on the hot render path via a sidecar cache (<projectDir>/.<sessionId>.cost-cache.json): per-file token
// tallies and byte positions persist, so each tick parses only the bytes appended since the last one. The first
// tick on a large session pays one chunked pass.
//
// A segment is a pure (input)=>string ('' => dropped); compose via cc/statusline.mjs. Not standalone-portable
// like context-meter (depends on ../lib/usage.mjs + prices.json — deliberately, so pricing has one source).
import { readFileSync, writeFileSync, readdirSync, existsSync, openSync, readSync, closeSync, statSync, realpathSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeCost, priceFor } from '../lib/usage.mjs';

const CACHE_READ_MULT = 0.1;
const PV = 4;                // pricing/format version — bump when cache shape or computeCost's tiers change
const USD = process.env.COST_METER_USD === '1';   // default tokens; dollars are notional on a subscription plan
function kfmt(n) { return n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${Math.round(n / 1e3)}k` : `${n}`; }

// ── main-window marginal cost (payload-only) ─────────────────────────────────
function marginalPerTurn(input) {
  const cw = input.context_window;
  const model = input.model && input.model.id;
  if (!cw || !cw.context_window_size || !model) return null;
  const window = cw.total_input_tokens || 0;
  if (!window) return null;
  const p = priceFor(model);
  if (!p) return null;
  return { perTurn: (window / 1e6) * p.input * CACHE_READ_MULT, fill: window / cw.context_window_size };
}

// ── file helpers ─────────────────────────────────────────────────────────────
function readBuf(path, start, end) {
  const len = end - start;
  if (len <= 0) return Buffer.alloc(0);
  const fd = openSync(path, 'r');
  try { const buf = Buffer.allocUnsafe(len); const n = readSync(fd, buf, 0, len, start); return buf.subarray(0, n); }
  finally { closeSync(fd); }
}

// accumulate one usage record into a per-model bucket (assistant turn or subagent turn).
function addUsage(byModel, model, u) {
  const cc = u.cache_creation || {};
  const k = model || '';
  const a = byModel[k] || { input: 0, output: 0, cache_read: 0, cache_creation: 0, cache_creation_1h: 0, cache_creation_5m: 0 };
  a.input += u.input_tokens || 0; a.output += u.output_tokens || 0;
  a.cache_read += u.cache_read_input_tokens || 0; a.cache_creation += u.cache_creation_input_tokens || 0;
  a.cache_creation_1h += cc.ephemeral_1h_input_tokens || 0; a.cache_creation_5m += cc.ephemeral_5m_input_tokens || 0;
  byModel[k] = a;
}
// price a per-model map → {eff, cost} (eff = cost-weighted input-equivalent tokens).
function priceModels(byModel) {
  let eff = 0, cost = 0;
  for (const [k, u] of Object.entries(byModel)) {
    const model = k || null;
    const c = computeCost(u, model).cost_usd; const p = priceFor(model);
    if (c != null) { cost += c; if (p) eff += (c / p.input) * 1e6; }
  }
  return { eff, cost };
}

// Incremental usage tally over an append-only JSONL. Reads only bytes after `st.pos`, in CHUNK-sized buffers (a
// transcript can exceed V8's maximum string length), and only whole lines, so a record still being written is
// read on the next tick. Assistant records of one API response share message.id and repeat its usage; `st.ids`
// keeps recent ids to count each response once. With `boundaries`, a compact_boundary record starts a new
// segment: the tally resets and `st.since` takes the boundary's timestamp.
const CHUNK = 8 * 1024 * 1024;
const RECENT_IDS = 256;
function newTally() { return { pos: 0, ids: [], byModel: {}, firstTs: null, since: null }; }
function tally(path, st, size, boundaries) {
  let changed = false;
  while (st.pos < size) {
    const buf = readBuf(path, st.pos, Math.min(size, st.pos + CHUNK));
    const end = buf.lastIndexOf(0x0a);
    if (end < 0) {
      if (buf.length < CHUNK) break;            // a partial last line: wait for the rest
      st.pos += buf.length; changed = true;     // one line longer than CHUNK: skip it
      continue;
    }
    for (const line of buf.toString('utf8', 0, end).split('\n')) {
      if (!line) continue;
      if (!st.firstTs && line.indexOf('"timestamp"') >= 0) { try { st.firstTs = JSON.parse(line).timestamp || null; } catch { /* fragment */ } }
      if (boundaries && line.indexOf('compact_boundary') >= 0) {
        let r; try { r = JSON.parse(line); } catch { r = null; }
        if (r && r.type === 'system' && r.subtype === 'compact_boundary') { st.byModel = {}; st.ids = []; st.since = r.timestamp || null; }
        continue;
      }
      if (line.indexOf('"assistant"') < 0) continue;
      let r; try { r = JSON.parse(line); } catch { continue; }
      if (r.type !== 'assistant') continue;
      const u = r.message && r.message.usage, id = r.message && r.message.id;
      if (!u || !id || st.ids.includes(id)) continue;
      st.ids.push(id); if (st.ids.length > RECENT_IDS) st.ids.shift();
      addUsage(st.byModel, r.message.model || null, u);
    }
    st.pos += end + 1; changed = true;
  }
  return changed;
}
// Effective (input-equivalent) tokens with fixed weights, so the token view needs no price table:
// cache reads 0.1x, 5-minute cache writes 1.25x, 1-hour writes 2x, output 5x.
function effTokens(byModel) {
  let n = 0;
  for (const u of Object.values(byModel)) {
    const w5 = u.cache_creation_5m, w1 = u.cache_creation_1h, wOther = Math.max(0, u.cache_creation - w5 - w1);
    n += u.input + 0.1 * u.cache_read + 1.25 * (w5 + wOther) + 2 * w1 + 5 * u.output;
  }
  return n;
}
function rawTokens(byModel) {
  let n = 0; for (const u of Object.values(byModel)) n += u.input + u.output + u.cache_read + u.cache_creation; return n;
}

// current-segment SUBAGENT burn: files whose first turn is at/after the segment start. Mutates `cache`
// (per-file entries) and returns { sub, dirty }.
function subagentSegmentCost(transcriptPath, since, cache) {
  const subDir = join(dirname(transcriptPath), basename(transcriptPath, '.jsonl'), 'subagents');
  if (!existsSync(subDir)) return { sub: null, dirty: false };
  let files; try { files = readdirSync(subDir).filter((f) => f.endsWith('.jsonl')); } catch { return { sub: null, dirty: false }; }
  if (!files.length) return { sub: null, dirty: false };
  let dirty = false, cost = 0, tokens = 0, eff = 0, count = 0;
  const live = new Set(files.map((f) => `sub:${f}`));
  for (const f of files) {
    const p = join(subDir, f);
    let st; try { st = statSync(p); } catch { continue; }
    const ck = `sub:${f}`;
    let ent = cache[ck];
    if (!ent || ent.v !== PV || st.size < ent.t.pos) { ent = { v: PV, t: newTally() }; dirty = true; }   // new, stale or truncated
    if (tally(p, ent.t, st.size, false)) { ent.cost = USD ? priceModels(ent.t.byModel).cost : 0; ent.eff = effTokens(ent.t.byModel); ent.tokens = rawTokens(ent.t.byModel); dirty = true; }
    cache[ck] = ent;
    if (ent.tokens == null) continue;
    if (!since || (ent.t.firstTs && ent.t.firstTs >= since)) { cost += ent.cost; tokens += ent.tokens; eff += ent.eff; count++; }
  }
  for (const k of Object.keys(cache)) if (k.startsWith('sub:') && !live.has(k)) { delete cache[k]; dirty = true; }   // prune vanished files
  return { sub: count ? { cost, tokens, eff, count } : null, dirty };
}

// orchestrate: locate the current segment once (incremental boundary scan), then price main + subagents,
// sharing (and persisting) one sidecar cache.
function segmentCost(transcriptPath) {
  const cachePath = join(dirname(transcriptPath), `.${basename(transcriptPath, '.jsonl')}.cost-cache.json`);
  let cache = {}; try { cache = JSON.parse(readFileSync(cachePath, 'utf8')); } catch { /* cold cache */ }
  let dirty = false;

  let size = 0;
  try { size = statSync(transcriptPath).size; } catch { return { main: null, sub: null }; }
  let mt = cache._mainTally;
  if (!mt || mt.v !== PV || size < mt.t.pos) { mt = { v: PV, t: newTally() }; dirty = true; }   // new, stale or truncated
  if (tally(transcriptPath, mt.t, size, true)) dirty = true;
  cache._mainTally = mt; delete cache._main;
  const since = mt.t.since;
  const main = Object.keys(mt.t.byModel).length
    ? { eff: effTokens(mt.t.byModel), cost: USD ? priceModels(mt.t.byModel).cost : 0 } : null;
  const { sub, dirty: subDirty } = subagentSegmentCost(transcriptPath, since, cache);
  if (dirty || subDirty) { try { writeFileSync(cachePath, JSON.stringify(cache)); } catch { /* read-only fs ⇒ recompute next tick */ } }
  return { main, sub };
}

export function costMeter(input = {}) {
  const m = marginalPerTurn(input);                               // {perTurn, fill} — fill drives the hint
  const tp = input.transcript_path;
  const seg = tp ? safe(() => segmentCost(tp)) : null;
  const main = seg && seg.main, sub = seg && seg.sub;

  const parts = [];
  if (USD && m) parts.push(`\u{1F4B8} $${m.perTurn.toFixed(2)}/turn`);   // 💸 (USD mode only)
  const sp = [];
  if (main) sp.push(`\u{1F9E0} ${USD ? `$${main.cost.toFixed(2)}` : kfmt(main.eff)}`);   // 🧠 main this segment
  if (sub)  sp.push(`\u{1F916} ${USD ? `$${sub.cost.toFixed(2)}` : kfmt(sub.eff)}`);      // 🤖 subagents this segment
  if (sp.length) parts.push(sp.join(' + ') + ' /seg');
  if (!parts.length) return '';
  return parts.join(' · ');
  // "⟳ compact now" lives on the context-meter (it's a verdict on the FILL number, not the burn) — see
  // context-meter.mjs. (Warm/cold is the cache-meter's 🔥/❄️; per-turn ramp lives in cc/session-tokens.mjs.)
}
function safe(fn) { try { return fn(); } catch { return null; } }

// standalone: node cc/cost-meter.mjs  (reads the statusLine payload JSON on stdin)
const isMain = (() => { try { return !!process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } })();
if (isMain) {
  let input = {}; try { input = JSON.parse(readFileSync(0, 'utf8') || '{}'); } catch { /* no/!JSON stdin */ }
  process.stdout.write(costMeter(input));
}
