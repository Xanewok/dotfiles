#!/usr/bin/env node
// latency-meter.mjs — statusLine segment: rolling first-response latency, so "is it getting laggy?" is legible
// LIVE. Shows ⏱ <avg>s = mean over the last 5 turns of (first assistant record ts − your message ts): the
// wait from hitting enter to the reply starting. Lower = snappier, higher = you're losing time.
//
// HONESTY: this is NOT pure time-to-first-token. The transcript records when each assistant message FINISHED,
// not when its first token arrived — so this gap is prefill + a short first-message decode, an UPPER BOUND on
// TTFT. It's the cleanest latency the log affords: it's measured BEFORE any tool runs or approval gate (those
// come after the first tool_use), so it isn't polluted by you being AFK mid-turn the way turn_duration is.
// It's noisy per-turn (decode length + server load), which is why we average 5 turns and drop >120s outliers
// (rate-limit stalls / a stall before the first token). Prefill grows with the window, so at big context this
// trends up — but weakly; treat it as a snappiness gauge, not a precise context-cost meter.
//
// A segment is a pure (input)=>string ('' => dropped); compose via cc/statusline.mjs. Standalone-portable
// (payload JSON on stdin) — no pricing dependency, unlike cost-meter.
import { readFileSync, openSync, readSync, closeSync, statSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const N = 5;                 // rolling window: average the last N clean turns
const OUTLIER_S = 120;       // drop first-response gaps longer than this (rate-limit stall / AFK before 1st token)
const TAIL = 2 * 1024 * 1024; // bytes of transcript tail to scan. Must reach back past ≥N human turns: on a big
                             // tool-heavy session a single turn's tool-results can be ~½MB, pushing the 5th-from-last
                             // human turn ~750KB back — 512KB missed it entirely (latency vanished on big sessions,
                             // where it matters most). 2MB covers it with margin; ~10ms to parse.

function isHuman(r) {         // a real user message, not a tool_result echoed back as a user record
  if (r.type !== 'user' || r.isSidechain) return false;
  const c = r.message && r.message.content;
  if (typeof c === 'string') return true;
  if (Array.isArray(c)) return !c.some((x) => x && x.type === 'tool_result');
  return false;
}

// last N clean (human msg → first assistant record) latencies from the transcript tail, in seconds.
function recentLatencies(transcriptPath) {
  let text;
  const st = statSync(transcriptPath);
  const start = Math.max(0, st.size - TAIL);
  const fd = openSync(transcriptPath, 'r');
  try { const len = st.size - start; const buf = Buffer.allocUnsafe(len); const n = readSync(fd, buf, 0, len, start); text = buf.toString('utf8', 0, n); }
  finally { closeSync(fd); }
  if (start > 0) { const nl = text.indexOf('\n'); if (nl >= 0) text = text.slice(nl + 1); }   // drop the partial first line
  const out = [];
  let pending = null;
  for (const line of text.split('\n')) {
    if (!line) continue;
    let r; try { r = JSON.parse(line); } catch { continue; }
    const ts = r.timestamp ? Date.parse(r.timestamp) : null;
    if (isHuman(r) && ts) { pending = ts; continue; }
    if (pending && r.type === 'assistant' && r.message && !r.isSidechain && ts) {
      const dt = (ts - pending) / 1000;
      if (dt >= 0 && dt < OUTLIER_S) out.push(dt);
      pending = null;
    }
  }
  return out;
}

export function latencyMeter(input = {}) {
  const tp = input.transcript_path;
  if (!tp) return '';
  const lat = safe(() => recentLatencies(tp)) || [];
  if (!lat.length) return '';
  const recent = lat.slice(-N);
  const avg = recent.reduce((s, x) => s + x, 0) / recent.length;
  const s = avg >= 100 ? `${Math.round(avg)}s` : avg >= 10 ? `${avg.toFixed(0)}s` : `${avg.toFixed(1)}s`;
  let color = '';                            // lower = better; escalate as the reply gets laggy
  if (avg >= 60) color = '\x1b[31m';         // red
  else if (avg >= 40) color = '\x1b[38;5;208m'; // orange
  else if (avg >= 25) color = '\x1b[33m';    // yellow
  else if (avg < 12) color = '\x1b[32m';     // green (snappy)
  const reset = color ? '\x1b[0m' : '';
  return `\u{23F1} ${color}${s}${reset}`;    // ⏱
}
function safe(fn) { try { return fn(); } catch { return null; } }

// standalone: node cc/latency-meter.mjs  (reads the statusLine payload JSON on stdin)
const isMain = (() => { try { return !!process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } })();
if (isMain) {
  let input = {}; try { input = JSON.parse(readFileSync(0, 'utf8') || '{}'); } catch { /* no/!JSON stdin */ }
  process.stdout.write(latencyMeter(input));
}
