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
// Cheap on the hot render path via a sidecar cache (<projectDir>/.<sessionId>.cost-cache.json): the segment
// boundary is found by scanning ONLY the bytes appended to the main transcript since the last tick (append-only
// JSONL) and its byte offset is cached, so main burn re-reads only the segment TAIL (offset→EOF), never the
// whole file after warmup; subagent files are re-priced only when their mtime+size changes.
//
// A segment is a pure (input)=>string ('' => dropped); compose via cc/statusline.mjs. Not standalone-portable
// like context-meter (depends on ../lib/usage.mjs + prices.json — deliberately, so pricing has one source).
import { readFileSync, writeFileSync, readdirSync, existsSync, openSync, readSync, closeSync, statSync, realpathSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeCost, priceFor } from '../lib/usage.mjs';

const CACHE_READ_MULT = 0.1;
const OVERLAP = 64 * 1024;   // re-scan this many bytes before the prior EOF, to catch a boundary that straddled it
const PV = 3;                // pricing/format version — bump when cache shape or computeCost's tiers change
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
function readRange(path, start, end) {
  const len = end - start;
  if (len <= 0) return '';
  const fd = openSync(path, 'r');
  try { const buf = Buffer.allocUnsafe(len); const n = readSync(fd, buf, 0, len, start); return buf.toString('utf8', 0, n); }
  finally { closeSync(fd); }
}
// newest compact_boundary in a chunk → {ts, offset} (byte offset of the boundary line's start; base = the
// chunk's absolute start offset). {ts:null, offset:0} if the chunk has none (⇒ segment = whole file so far).
function scanLastBoundary(text, base) {
  let ts = null, offset = 0, pos = 0;
  for (const line of text.split('\n')) {
    if (line && line.indexOf('compact_boundary') >= 0) {
      let r; try { r = JSON.parse(line); } catch { r = null; }
      if (r && r.type === 'system' && r.subtype === 'compact_boundary' && r.timestamp) {
        ts = r.timestamp; offset = base + Buffer.byteLength(text.slice(0, pos), 'utf8');
      }
    }
    pos += line.length + 1;   // +1 for the consumed '\n' (char index; converted to bytes above)
  }
  return { ts, offset };
}

// accumulate one usage record into a per-model bucket (assistant turn or subagent turn).
function addUsage(byModel, model, u) {
  const cc = u.cache_creation || {};
  const a = byModel.get(model) || { input: 0, output: 0, cache_read: 0, cache_creation: 0, cache_creation_1h: 0, cache_creation_5m: 0 };
  a.input += u.input_tokens || 0; a.output += u.output_tokens || 0;
  a.cache_read += u.cache_read_input_tokens || 0; a.cache_creation += u.cache_creation_input_tokens || 0;
  a.cache_creation_1h += cc.ephemeral_1h_input_tokens || 0; a.cache_creation_5m += cc.ephemeral_5m_input_tokens || 0;
  byModel.set(model, a);
}
// price a per-model map → {eff, cost} (eff = cost-weighted input-equivalent tokens).
function priceModels(byModel) {
  let eff = 0, cost = 0;
  for (const [model, u] of byModel) {
    const c = computeCost(u, model).cost_usd; const p = priceFor(model);
    if (c != null) { cost += c; if (p) eff += (c / p.input) * 1e6; }
  }
  return { eff, cost };
}

// one subagent file → { cost, tokens, eff, firstTs } (deduped by message.id, priced per its own model).
function priceSubagent(path) {
  const seen = new Set();
  const byModel = new Map();
  let firstTs = null;
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line) continue;
    let r; try { r = JSON.parse(line); } catch { continue; }
    if (!firstTs && r.timestamp) firstTs = r.timestamp;
    if (r.type !== 'assistant') continue;
    const u = r.message && r.message.usage, id = r.message && r.message.id;
    if (!u || !id || seen.has(id)) continue;
    seen.add(id);
    addUsage(byModel, r.message.model || null, u);
  }
  let tokens = 0;
  for (const [, u] of byModel) tokens += u.input + u.output + u.cache_read + u.cache_creation;   // raw throughput
  const { eff, cost } = priceModels(byModel);
  return { cost, tokens, eff, firstTs };
}

// current-segment MAIN burn: assistant turns from the boundary byte offset to EOF (deduped, priced per model).
function mainSegmentCost(transcriptPath, offset, size) {
  let text; try { text = readRange(transcriptPath, offset || 0, size); } catch { return null; }
  if (!text) return null;
  const seen = new Set(); const byModel = new Map();
  for (const line of text.split('\n')) {
    if (!line || line.indexOf('"assistant"') < 0) continue;
    let r; try { r = JSON.parse(line); } catch { continue; }
    if (r.type !== 'assistant') continue;
    const u = r.message && r.message.usage, id = r.message && r.message.id;
    if (!u || !id || seen.has(id)) continue;
    seen.add(id);
    addUsage(byModel, r.message.model || null, u);
  }
  return byModel.size ? priceModels(byModel) : null;
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
    const key = `${st.mtimeMs}:${st.size}`, ck = `sub:${f}`;
    let ent = cache[ck];
    if (!ent || ent.key !== key || ent.v !== PV) {   // recompute on file change OR a stale cache version
      const s = priceSubagent(p); ent = { v: PV, key, cost: s.cost, tokens: s.tokens, eff: s.eff, firstTs: s.firstTs }; dirty = true;
    }
    cache[ck] = ent;
    if (!since || (ent.firstTs && ent.firstTs >= since)) { cost += ent.cost; tokens += ent.tokens; eff += ent.eff; count++; }
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

  // segment start: last compact_boundary {ts, byte offset}, tracked incrementally over the append-only file.
  let since = null, offset = 0, size = 0;
  try {
    const st = statSync(transcriptPath); size = st.size;
    const prev = (cache._main && typeof cache._main.size === 'number') ? cache._main : { size: 0, ts: null, offset: 0 };
    let ts = prev.ts, off = prev.offset || 0;
    if (st.size < prev.size) { const b = scanLastBoundary(readRange(transcriptPath, 0, st.size), 0); ts = b.ts; off = b.offset; dirty = true; }   // shrank/rotated ⇒ full rescan
    else if (st.size > prev.size) {
      const base = Math.max(0, prev.size - OVERLAP);
      const b = scanLastBoundary(readRange(transcriptPath, base, st.size), base);
      if (b.ts) { ts = b.ts; off = b.offset; }   // no boundary in the new bytes ⇒ keep the prior one
      dirty = true;
    }
    if (!cache._main || cache._main.size !== st.size || cache._main.ts !== ts || cache._main.offset !== off) { cache._main = { size: st.size, ts, offset: off }; dirty = true; }
    since = ts; offset = off;
  } catch { /* unreadable ⇒ offset 0 ⇒ whole file counts as one segment */ }

  const main = mainSegmentCost(transcriptPath, offset, size);
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
