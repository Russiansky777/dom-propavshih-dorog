// Shared parts of the AI checks (tools/ai_checks/*.mjs): repository paths, git reads, the canon, the API
// call with the per-run cost line, the report file. API, prices, budget and redaction — tools/ai_playtest/claude.mjs.
// Rules: a check reads the repository and writes only Docs/ai_checks/<check>_<date>.md (+ its frames);
// it never edits game/ or data/. The key and the workspace ID never reach stdout or the report.

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { callClaude, callTool, Budget, ApiError, redact } from "../ai_playtest/claude.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(__dirname, "..", "..");
export const OUT_DIR = path.join(ROOT, "Docs", "ai_checks");

export function args() {
  const a = process.argv.slice(2);
  const o = {};
  for (let i = 0; i < a.length; i++) {
    if (!a[i].startsWith("--")) continue;
    const k = a[i].slice(2);
    if (i + 1 < a.length && !a[i + 1].startsWith("--")) { o[k] = a[i + 1]; i++; } else o[k] = true;
  }
  return o;
}

export const log = (s) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${s}`);

export function git(...a) {
  return execFileSync("git", a, { cwd: ROOT, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
}
export function gitBuf(...a) {
  return execFileSync("git", a, { cwd: ROOT, maxBuffer: 256 * 1024 * 1024 });
}
/** A usable base commit (the push's `before`), or "" when it is missing / all zeros / unknown here. */
export function validBase(ref) {
  if (!ref || /^0+$/.test(ref)) return "";
  try { git("cat-file", "-e", `${ref}^{commit}`); return ref; } catch (_) { return ""; }
}
export function changedFiles(base, head = "HEAD", ...paths) {
  if (!base) return [];
  return git("diff", "--name-only", "--diff-filter=AMR", base, head, "--", ...paths).split("\n").filter(Boolean);
}
/** File text at a ref ("" = working tree), or null when it does not exist there. */
export function readAt(ref, rel) {
  if (!ref) { const f = path.join(ROOT, rel); return fs.existsSync(f) ? fs.readFileSync(f, "utf8") : null; }
  try { return git("show", `${ref}:${rel}`); } catch (_) { return null; }
}
export function listAt(ref, dirRel) {
  if (!ref) {
    const out = [];
    const walk = (d) => { for (const e of fs.readdirSync(path.join(ROOT, d), { withFileTypes: true })) { const r = `${d}/${e.name}`; if (e.isDirectory()) walk(r); else out.push(r); } };
    if (fs.existsSync(path.join(ROOT, dirRel))) walk(dirRel);
    return out.sort();
  }
  try { return git("ls-tree", "-r", "--name-only", ref, "--", dirRel).split("\n").filter(Boolean); } catch (_) { return []; }
}

/** The canon block of CLAUDE.md + the cast (names, ages, roles) + the law of the world. */
export function canonText() {
  const md = fs.readFileSync(path.join(ROOT, "CLAUDE.md"), "utf8");
  const m = /## Неизменный канон[^\n]*\n([\s\S]*?)\n## /.exec(md);
  const L = ["КАНОН (CLAUDE.md, не меняется без решения Директора):", m ? m[1].trim() : ""];
  try {
    const ch = JSON.parse(fs.readFileSync(path.join(ROOT, "data/story/characters.json"), "utf8")).characters || [];
    L.push("\nПЕРСОНАЖИ (data/story/characters.json):");
    for (const c of ch) L.push(`- ${c.name} (${c.id})${c.age !== undefined ? `, ${c.age}` : ""}${c.age_at_cut !== undefined ? ` (при разрыве ${c.age_at_cut})` : ""}: ${String(c.role || "").slice(0, 400)}`);
  } catch (_) { /* no cast file */ }
  return L.join("\n");
}

export function readDoc(rel, max = 200000) {
  const f = path.join(ROOT, rel);
  if (!fs.existsSync(f)) return "";
  const t = fs.readFileSync(f, "utf8");
  return t.length > max ? t.slice(0, max) + "\n…(обрезано)" : t;
}

/** Docs/ai_checks/<name>_<date>.md, with _2, _3 … when that day already has one. */
export function reportPath(name) {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const date = new Date().toISOString().slice(0, 10);
  let p = path.join(OUT_DIR, `${name}_${date}.md`);
  for (let n = 2; fs.existsSync(p); n++) p = path.join(OUT_DIR, `${name}_${date}_${n}.md`);
  return p;
}

/** One API call through the shared client; the cost goes into `budget`. Throws a readable Error. */
export async function ask(budget, tag, body) {
  const apiKey = process.env.ANTHROPIC_API_KEY || "";
  if (!apiKey) throw new Error("нет ключа API (секрет CLAUDE_API → ANTHROPIC_API_KEY)");
  try {
    const resp = await callClaude(apiKey, body, { log });
    budget.add(body.model, resp.usage, tag);
    return resp;
  } catch (e) {
    if (e instanceof ApiError) throw new Error(redact(`API: ${e.message}`));
    throw e;
  }
}

/** A call that must answer with the tool `name` (forced where the model allows, else auto; one retry). */
export async function askTool(budget, tag, body, name) {
  const apiKey = process.env.ANTHROPIC_API_KEY || "";
  if (!apiKey) throw new Error("нет ключа API (секрет CLAUDE_API → ANTHROPIC_API_KEY)");
  try {
    for (let attempt = 0; attempt < 2; attempt++) {
      // Long answers (Opus, high effort, up to 32k tokens) take minutes: 15 min per attempt, 3 attempts.
      const { resp, input } = await callTool(apiKey, body, name, { log, timeoutMs: 900000, attempts: 3 });
      budget.add(body.model, resp.usage, attempt ? `${tag}-retry` : tag);
      if (input) return input;
      log(`${tag}: no ${name} call (stop_reason ${resp.stop_reason}), retry`);
    }
    return null;
  } catch (e) {
    if (e instanceof ApiError) throw new Error(redact(`API: ${e.message}`));
    throw e;
  }
}

/** The input of the first tool_use block named `name`, or null. */
export const toolInput = (resp, name) => {
  const b = (resp.content || []).find((c) => c.type === "tool_use" && c.name === name);
  return b ? b.input : null;
};

export const cell = (s) => String(s ?? "").replace(/\|/g, "/").replace(/\s*\n\s*/g, " ").trim();
export const runLine = () => (process.env.GITHUB_RUN_ID ? `запуск Actions ${process.env.GITHUB_RUN_NUMBER} (id ${process.env.GITHUB_RUN_ID})` : "локальный запуск");
export { Budget, redact };
