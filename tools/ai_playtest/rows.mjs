// Row ids of an acceptance checklist (Docs/ACCEPTANCE_*.md): the first cell of a table row, as written —
// "140", "6а", "24б", "И2". Until 23.10 the gates read only plain numbers, so the lettered rows (M2: 6а, 11а,
// 12а, 18а, 21а, 22а, 24а, 24б, И1–И10; M1: 140а…149а; M3: 11а) were never checked. Ids are strings now.

// A row: "| 6а | …", "| И10 | …". Latin a/b in the suffix are read as the Cyrillic а/б they stand for.
export const ROW_RE = /^\|\s*([А-ЯЁA-Z]{0,3}\d+[а-яёa-z]?)\s*\|/;
const LAT = { a: "а", b: "б", v: "в", g: "г" };

export function normId(s) {
  const t = String(s ?? "").trim();
  const m = /^([A-Za-zА-ЯЁа-яё]{0,3})(\d+)([A-Za-zА-ЯЁа-яё]?)$/.exec(t);
  if (!m) return t;
  const suf = m[3].toLowerCase();
  return `${m[1].toUpperCase()}${Number(m[2])}${LAT[suf] || suf}`;
}

export function rowIdOf(line) {
  const m = ROW_RE.exec(line);
  return m ? normId(m[1]) : null;
}

/** Row ids of a checklist text, in document order. */
export const docRowIds = (text) => String(text || "").split("\n").map(rowIdOf).filter(Boolean);

const split = (id) => { const m = /^(\D*)(\d+)(.*)$/.exec(id); return m ? { pre: m[1], n: Number(m[2]), suf: m[3] } : null; };

/** Tokens of an item spec: "1-20, 6а" | ["140", 141, "И1-И3"] | 140. */
function tokens(v) {
  if (v === undefined || v === null || v === "") return [];
  const list = Array.isArray(v) ? v : [v];
  return list.flatMap((x) => String(x).split(",")).map((s) => s.trim()).filter(Boolean);
}

/**
 * Resolve an item spec against the checklist's row ids (doc order). A range takes every row with the same
 * prefix whose number is inside it, the lettered ones included («1-20» → … 6, 6а, 7 …; «И1-И10»); a single id
 * stays as written (normalised), so a row missing from the doc is reported as missing. Without ids, ranges of
 * plain numbers expand to the numbers.
 */
export function resolveItems(v, ids = null) {
  const out = [];
  for (const t of tokens(v)) {
    const r = /^(.+?)\s*[-–—]\s*(.+)$/.exec(t);
    if (!r) { out.push(normId(t)); continue; }
    const a = split(normId(r[1])), b = split(normId(r[2]));
    if (!a || !b || a.pre !== b.pre) continue;
    if (ids && ids.length) {
      for (const id of ids) { const s = split(id); if (s && s.pre === a.pre && s.n >= a.n && s.n <= b.n) out.push(id); }
    } else if (!a.pre) {
      for (let i = a.n; i <= b.n; i++) out.push(String(i));
    }
  }
  return [...new Set(out)];
}

/** Comparator of ids by their place in the checklist (unknown ids last, then by number). */
export function byDocOrder(ids) {
  const at = new Map(ids.map((id, i) => [String(id), i]));
  return (a, b) => {
    const x = at.has(String(a)) ? at.get(String(a)) : 1e9, y = at.has(String(b)) ? at.get(String(b)) : 1e9;
    if (x !== y) return x - y;
    return (parseInt(String(a).replace(/^\D*/, ""), 10) || 0) - (parseInt(String(b).replace(/^\D*/, ""), 10) || 0);
  };
}
