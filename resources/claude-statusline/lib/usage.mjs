// usage.mjs — token/cost telemetry for `agents run` (coordination infra; additive-only per-job signal, NOT
// a billing reconciliation). Two backends report usage very differently:
//   - cc:    `claude -p --output-format json` → one JSON object on stdout carrying `usage` AND an
//            authoritative `total_cost_usd` the CLI itself computed (correct cache-tier multipliers,
//            whatever model actually served the turn incl. --fallback-model). Prefer that cost outright.
//   - codex: `codex exec --json` → a JSONL event stream; the terminal `turn.completed` event carries
//            `usage` (input/cached-input/output/reasoning tokens) but NO cost and NO cache-WRITE figure —
//            codex/OpenAI don't expose that split the way Claude does. We price it ourselves from
//            prices.json; this is an approximation (undiscounted — it does not know each provider's cache
//            read discount), which is called out in the emitted `prices_used` note.
// Unknown model → cost_usd stays null. Never fabricate a number we can't justify.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const PRICES_PATH = join(HERE, 'prices.json');

let _prices = null;
function loadPrices() {
  if (_prices) return _prices;
  try { _prices = JSON.parse(readFileSync(PRICES_PATH, 'utf8')); } catch { _prices = {}; }
  return _prices;
}

// exact id match first, else the longest table key that is a PREFIX of the model id (covers dated/suffixed
// variants of a family without needing an entry per snapshot). No match → null (caller must not invent a price).
export function priceFor(model) {
  if (!model) return null;
  const prices = loadPrices();
  if (prices[model]) return prices[model];
  let best = null, bestLen = 0;
  for (const key of Object.keys(prices)) {
    if (key === '_comment') continue;
    if (model.startsWith(key) && key.length > bestLen) { best = prices[key]; bestLen = key.length; }
  }
  return best;
}

// Prompt-cache pricing multipliers on the base input rate (Anthropic; see shared/prompt-caching.md):
// reads bill ~0.1x, writes bill 1.25x (5m TTL) or 2x (1h TTL). Applied to Claude models only.
const CACHE_READ_MULT = 0.1;
const CACHE_WRITE_5M_MULT = 1.25;
const CACHE_WRITE_1H_MULT = 2.0;   // CC's main session caches at the 1h tier — the common case

// usage: {input, output, cache_read, cache_creation} (nulls allowed). Cache WRITES are priced by TTL when the
// usage carries the split — cache_creation_1h / cache_creation_5m (from CC's usage.cache_creation.ephemeral_
// {1h,5m}_input_tokens) are billed 2x / 1.25x exactly; otherwise the flat cache_creation is priced at the 5m
// rate (1.25x). Reads bill 0.1x. This is what makes the cc no-total_cost_usd fallback realistic (reads
// dominate throughput at 0.1x, so folding cache in at full price overestimated ~8-9x). Non-Claude (codex/
// OpenAI): cache tokens stay full-price input — the provider's cache discount differs and isn't known here.
export function computeCost(usage, model) {
  const p = priceFor(model);
  if (!p) return { cost_usd: null, prices_used: null };
  const claude = typeof model === 'string' && model.startsWith('claude');
  const readMult = claude ? CACHE_READ_MULT : 1;
  let writeTok;
  if (claude && (usage.cache_creation_1h != null || usage.cache_creation_5m != null)) {   // exact TTL split
    writeTok = (usage.cache_creation_1h || 0) * CACHE_WRITE_1H_MULT + (usage.cache_creation_5m || 0) * CACHE_WRITE_5M_MULT;
  } else {                                                                                 // flat fallback
    writeTok = (usage.cache_creation || 0) * (claude ? CACHE_WRITE_5M_MULT : 1);
  }
  const inTok = (usage.input || 0) + (usage.cache_read || 0) * readMult + writeTok;
  const cost = (inTok / 1e6) * p.input + ((usage.output || 0) / 1e6) * p.output;
  return { cost_usd: Math.round(cost * 1e6) / 1e6, prices_used: { model, input_per_1m: p.input, output_per_1m: p.output } };
}

// `claude -p --output-format json` result → { text, usage, cost_usd, model } or null if stdout isn't that JSON
// shape (e.g. an older CLI without --output-format support, or a user --output-format override via `--`
// passthrough) — callers must fall back to treating stdout as plain text on null, unchanged from today.
export function parseCcResult(rawStdout) {
  let j; try { j = JSON.parse(String(rawStdout).trim()); } catch { return null; }
  if (!j || typeof j !== 'object' || typeof j.result !== 'string') return null;
  const u = j.usage || {};
  const usage = {
    input: typeof u.input_tokens === 'number' ? u.input_tokens : null,
    output: typeof u.output_tokens === 'number' ? u.output_tokens : null,
    cache_read: typeof u.cache_read_input_tokens === 'number' ? u.cache_read_input_tokens : null,
    cache_creation: typeof u.cache_creation_input_tokens === 'number' ? u.cache_creation_input_tokens : null,
  };
  const model = j.modelUsage && typeof j.modelUsage === 'object' ? Object.keys(j.modelUsage)[0] || null : null;
  // total_cost_usd is authoritative (the CLI already applied real cache-tier pricing) — prefer it; only fall
  // back to our own price-table math (undiscounted, see computeCost) if it's missing.
  let cost_usd = typeof j.total_cost_usd === 'number' ? j.total_cost_usd : null;
  let prices_used = null;
  if (cost_usd == null) { const c = computeCost(usage, model); cost_usd = c.cost_usd; prices_used = c.prices_used; }
  else { const p = priceFor(model); if (p) prices_used = { model, input_per_1m: p.input, output_per_1m: p.output }; }
  const sessionId = typeof j.session_id === 'string' ? j.session_id : null;   // heimr-registry: points to the transcript
  return { text: j.result, usage, cost_usd, prices_used, model, sessionId };
}

// `codex exec --json` JSONL stdout → { usage } (input/output/cache_read; codex reports no cache-creation
// figure — left null) or null if no `turn.completed` event with a `usage` field was found (older codex, or
// the turn errored before completing).
export function parseCodexUsage(rawStdout) {
  const lines = String(rawStdout || '').split('\n').map((l) => l.trim()).filter(Boolean);
  // session/thread id (== the rollout file's uuid) — for heimr-registry to point at the rollout log.
  let sessionId = null;
  for (const l of lines) { let ev; try { ev = JSON.parse(l); } catch { continue; }
    if (ev && (ev.type === 'thread.started' || ev.type === 'session.created')) { sessionId = ev.thread_id || ev.session_id || ev.id || null; break; } }
  for (let i = lines.length - 1; i >= 0; i--) {
    let ev; try { ev = JSON.parse(lines[i]); } catch { continue; }
    if (ev && ev.type === 'turn.completed' && ev.usage) {
      const u = ev.usage;
      return { sessionId, usage: {
        input: typeof u.input_tokens === 'number' ? u.input_tokens : null,
        output: typeof u.output_tokens === 'number' ? u.output_tokens : null,
        cache_read: typeof u.cached_input_tokens === 'number' ? u.cached_input_tokens : null,
        cache_creation: null,
      } };
    }
  }
  return null;
}

// one always-on stderr line, whatever we managed to capture (never withheld — the whole point is visibility).
export function formatTelemetryLine(jobId, usage, cost) {
  if (!usage) return `[${jobId}] tokens: unavailable (usage capture failed — backend/version may not support it)`;
  const cachedTotal = (usage.cache_read || 0) + (usage.cache_creation || 0);
  const costStr = cost && cost.cost_usd != null ? `$${cost.cost_usd.toFixed(4)}` : '$? (unknown model — add it to lib/prices.json)';
  const priceStr = cost && cost.prices_used ? ` (in $${cost.prices_used.input_per_1m}/1M, out $${cost.prices_used.output_per_1m}/1M)` : '';
  return `[${jobId}] tokens in=${usage.input ?? '?'} out=${usage.output ?? '?'} cached=${cachedTotal} · ${costStr}${priceStr}`;
}
