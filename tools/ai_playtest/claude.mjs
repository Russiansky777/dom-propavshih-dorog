// Anthropic Messages API for the AI playtester: one call with retries, prices, the budget guard.
//
// Prices — USD per 1M tokens, from the official pricing page
// https://platform.claude.com/docs/en/about-claude/pricing (read 2026-10-22). Models and IDs —
// https://platform.claude.com/docs/en/models/overview. A model missing from this table is refused: the
// budget is counted from the actual `usage` of every response, so an unknown price cannot be guarded.
// Image tokens are ordinary input tokens (⌈w/28⌉·⌈h/28⌉ per image on Claude 4.7+; 1280×720 → 1196).

export const PRICES = {
  // Haiku 5.5 is priced by prompt length: a prompt over 100k input tokens (cache included) pays the long rates.
  "claude-haiku-5-5": { in: 0.10, cw: 0.125, cr: 0.01, out: 0.50, long: { over: 100000, in: 0.50, cw: 0.625, cr: 0.05, out: 2.50 } },
  "claude-sonnet-5-5": { in: 2, cw: 2.5, cr: 0.10, out: 10 },
  "claude-opus-5-5": { in: 4, cw: 5, cr: 0.20, out: 20 },
  "claude-haiku-4-5": { in: 1, cw: 1.25, cr: 0.10, out: 5 },
};
export const PRICES_SOURCE = "https://platform.claude.com/docs/en/about-claude/pricing (2026-10-22)";

const API_BASE = (process.env.ANTHROPIC_BASE_URL || "https://api.anthropic.com").replace(/\/$/, "");
const API_URL = `${API_BASE}/v1/messages`;
const API_VERSION = process.env.ANTHROPIC_VERSION || "2023-06-01";

// A key that is not scoped to a workspace (personal / service account key) must name the workspace in the
// `anthropic-workspace-id` header of every request (platform.claude.com/docs/manage-claude/workspaces).
// The ID comes from ANTHROPIC_WORKSPACE_ID (secret CLAUDE_WORKSPACE); without it, on the first such 400 the
// workspaces are listed once with the same key (GET /v1/organizations/workspaces — allowed for keys not
// scoped to a workspace) and one is chosen: a name about this game / playtests, else «Default», else the first.
export const workspace = { id: process.env.ANTHROPIC_WORKSPACE_ID || "", name: "", source: process.env.ANTHROPIC_WORKSPACE_ID ? "secret" : "", tried: false, error: "" };

async function discoverWorkspace(apiKey, log) {
  workspace.tried = true;
  try {
    const res = await fetch(`${API_BASE}/v1/organizations/workspaces?include_default=true&limit=100`,
      { headers: { "x-api-key": apiKey, "anthropic-version": API_VERSION } });
    if (!res.ok) {
      let m = "";
      try { const j = await res.json(); m = String((j && j.error && j.error.message) || "").slice(0, 300); } catch (_) {}
      workspace.error = redact(`список пространств: HTTP ${res.status} ${m}`);
      log(`api: workspaces list HTTP ${res.status}`);
      return false;
    }
    const j = await res.json();
    const ws = (j.data || []).filter((w) => w && w.id && !w.archived_at);
    const pick = ws.find((w) => /дом|dom|propav|игр|game|playtest|плейтест/i.test(w.name || "")) || ws.find((w) => /^default$/i.test(w.name || "")) || ws[0];
    if (!pick) { workspace.error = "список пространств пуст"; return false; }
    workspace.id = pick.id;
    workspace.name = pick.name || "";
    workspace.source = `выбрано из ${ws.length} по списку`;
    log(`api: workspace chosen of ${ws.length}`);
    return true;
  } catch (e) {
    workspace.error = `список пространств: ${String((e && e.message) || e).slice(0, 120)}`;
    return false;
  }
}

export function priceKnown(model) { return Object.prototype.hasOwnProperty.call(PRICES, model); }

/** USD of one response from its usage block (thinking tokens are inside output_tokens). */
export function costOf(model, u) {
  const p = PRICES[model];
  if (!p || !u) return 0;
  const inp = u.input_tokens || 0, cw = u.cache_creation_input_tokens || 0, cr = u.cache_read_input_tokens || 0, out = u.output_tokens || 0;
  const r = p.long && inp + cw + cr > p.long.over ? { ...p, ...p.long } : p;
  const cw1h = (u.cache_creation && u.cache_creation.ephemeral_1h_input_tokens) || 0;   // 1-hour cache writes: 2× base input
  return (inp * r.in + (cw - cw1h) * r.cw + cw1h * r.in * 2 + cr * r.cr + out * r.out) / 1e6;
}

/** Rough USD of a request before sending it (chars/2.5 per token for Russian text after the 4.7+ tokenizer, images by patches). */
export function estimateCost(model, { textChars = 0, images = [], maxOut = 600 }) {
  const p = PRICES[model];
  if (!p) return Infinity;
  let tokens = Math.ceil(textChars / 2.5);
  for (const im of images) tokens += Math.ceil(im.w / 28) * Math.ceil(im.h / 28);
  const r = p.long && tokens > p.long.over ? { ...p, ...p.long } : p;
  return (tokens * r.in + maxOut * r.out) / 1e6;
}

// IDs and keys never reach the logs or the committed report.
export const redact = (t) => String(t || "").replace(/wrkspc_[A-Za-z0-9]+/g, "wrkspc_…").replace(/sk-ant-[A-Za-z0-9_-]+/g, "sk-ant-…");

export class ApiError extends Error {
  constructor(status, type, message) { super(redact(`HTTP ${status} ${type}: ${message}`)); this.status = status; this.type = type; }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * POST /v1/messages with retries on overload / rate limits / network errors. Never logs the key or the body.
 * Returns the parsed response. Throws ApiError on a permanent error (401, 400, …).
 */
export async function callClaude(apiKey, body, { log = () => {}, attempts = 6, timeoutMs = 180000 } = {}) {
  let lastErr = null;
  for (let a = 0; a < attempts; a++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    let res;
    try {
      const headers = { "x-api-key": apiKey, "anthropic-version": API_VERSION, "content-type": "application/json" };
      if (workspace.id) headers["anthropic-workspace-id"] = workspace.id;
      res = await fetch(API_URL, {
        method: "POST",
        headers,
        body: JSON.stringify(body),
        signal: ctrl.signal,
      });
    } catch (e) {
      clearTimeout(timer);
      lastErr = new ApiError(0, "network", String(e && e.name === "AbortError" ? "timeout" : (e && e.message) || e).slice(0, 120));
      log(`api: network error (${lastErr.message}), retry ${a + 1}`);
      await sleep(Math.min(60000, 3000 * 2 ** a));
      continue;
    }
    clearTimeout(timer);
    if (res.ok) return res.json();
    let type = "error", msg = "";
    try {
      const j = await res.json();
      type = (j && j.error && j.error.type) || type;
      msg = String((j && j.error && j.error.message) || "").slice(0, 500);
    } catch (_) { /* not JSON */ }
    lastErr = new ApiError(res.status, type, msg);
    if (res.status === 400 && /anthropic-workspace-id/.test(msg) && !workspace.tried) {
      if (await discoverWorkspace(apiKey, log)) { a -= 1; continue; }
      throw new ApiError(400, "workspace", `ключ не привязан к рабочему пространству, а ${workspace.error || "выбрать его не удалось"}; нужен секрет CLAUDE_WORKSPACE (wrkspc_…)`);
    }
    if ([408, 409, 429, 500, 502, 503, 504, 529].includes(res.status)) {
      const ra = Number(res.headers.get("retry-after"));
      const wait = Number.isFinite(ra) && ra > 0 ? Math.min(120, ra) * 1000 : Math.min(60000, 4000 * 2 ** a);
      log(`api: HTTP ${res.status} ${type}, retry ${a + 1} in ${Math.round(wait / 1000)} s`);
      await sleep(wait);
      continue;
    }
    throw lastErr;
  }
  throw lastErr || new ApiError(0, "unknown", "no response");
}

// Models that reject a forced tool_choice ({type: "tool"} / "any"): 400 «not supported for this model» (seen
// 22.10 on claude-sonnet-5-5 and claude-opus-5-5). They get {type: "auto"} and the prompt asks for the tool.
const NO_FORCED = new Set(["claude-sonnet-5-5", "claude-opus-5-5", "claude-fable-5-1"]);

/**
 * One call that should answer with the tool `toolName`: forced where the model allows it, else auto (learned on
 * the first 400 too). Returns {resp, input} — input of the tool_use block, or null when the model answered
 * without it (the caller decides whether to retry).
 */
export async function callTool(apiKey, body, toolName, opts = {}) {
  const forced = !NO_FORCED.has(body.model);
  let b = { ...body, tool_choice: forced ? { type: "tool", name: toolName } : { type: "auto" } };
  let resp;
  try { resp = await callClaude(apiKey, b, opts); }
  catch (e) {
    if (!(e instanceof ApiError && e.status === 400 && /tool_choice/.test(e.message) && forced)) throw e;
    NO_FORCED.add(body.model);
    b = { ...body, tool_choice: { type: "auto" } };
    resp = await callClaude(apiKey, b, opts);
  }
  const tu = (resp.content || []).find((c) => c.type === "tool_use" && c.name === toolName);
  return { resp, input: tu ? tu.input : null };
}

/** Spending of one run: every call with its usage, totals per model, the stop check. */
export class Budget {
  constructor(maxUsd) {
    this.maxUsd = maxUsd;
    this.spent = 0;
    this.calls = [];
    this.byModel = {};
  }
  add(model, usage, tag) {
    const usd = costOf(model, usage);
    this.spent += usd;
    const u = usage || {};
    const m = (this.byModel[model] ||= { calls: 0, input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, usd: 0 });
    m.calls += 1;
    for (const k of ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]) m[k] += u[k] || 0;
    m.usd += usd;
    this.calls.push({ tag, model, in: u.input_tokens || 0, out: u.output_tokens || 0, cw: u.cache_creation_input_tokens || 0, cr: u.cache_read_input_tokens || 0, usd: Number(usd.toFixed(6)) });
    return usd;
  }
  left() { return this.maxUsd - this.spent; }
  /** True when `next` USD more (plus the reserve kept for the final report) still fits under the ceiling. */
  fits(next, reserve = 0) { return this.spent + next + reserve <= this.maxUsd; }
  recentStepCost(model, n = 5) {
    const steps = this.calls.filter((c) => c.tag.startsWith("step") && c.model === model).slice(-n);
    return steps.length ? Math.max(...steps.map((c) => c.usd)) : 0;
  }
  toJSON() {
    const r = (x) => Number(x.toFixed(6));
    const byModel = {};
    for (const [k, v] of Object.entries(this.byModel)) byModel[k] = { ...v, usd: r(v.usd) };
    return { max_usd: this.maxUsd, spent_usd: r(this.spent), by_model: byModel, workspace: { source: workspace.source, error: workspace.error },
      prices_per_mtok: PRICES, prices_source: PRICES_SOURCE, calls: this.calls };
  }
}
