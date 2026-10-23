#!/usr/bin/env python3
"""Обратный импорт текстов из TSV выгрузки (tools/export_texts.py) в data/story (H59, T3).

    python3 -I tools/import_texts.py PATH.tsv [--dry-run]

TSV — колонки выгрузки (id, speaker, scene_room, context, text) плюс new_text. Строка, где new_text
не пуст и отличается от text, записывается ровно в то место JSON, откуда текст выгружен. Файл
меняется точечно: заменяется только сама строка JSON, отступы, порядок ключей и остальное — как было.

Проверки до записи (при любой ошибке не пишется ничего, код выхода 1):
  * в TSV есть все id свежей выгрузки и нет лишних (дубликаты тоже ошибка);
  * колонка text совпадает с нынешними данными (иначе выгрузка устарела — выгрузить заново);
  * подстановки и разметка ({item}, %s, $var, [тег голоса], [b]/BBCode, <тег>) в new_text те же,
    что в text (как мультимножество);
  * new_text не начинается с «@» (так в данных пишутся ссылки на ключи).
Строки ui_code:* (тексты, зашитые в код) не импортируются — только предупреждение.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load_exporter():
    spec = importlib.util.spec_from_file_location("export_texts", Path(__file__).resolve().parent / "export_texts.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ex = _load_exporter()

# Markup that must survive a text edit unchanged.
PLACEHOLDER_RES = [
    re.compile(r"\{[^{}\s]*\}"),                    # {item} {slot} {n}
    re.compile(r"\[[^\[\]\n]{1,40}\]"),             # [sleepy] [short pause] [b] [/b] [color=#fff]
    re.compile(r"</?[A-Za-z][^<>\n]{0,40}>"),        # <b> </i>
    re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?[sdifxX%]"),  # %s %d %.1f %%
    re.compile(r"\$\{[^}]*\}|\$[A-Za-z_]\w*"),     # $var ${var}
]


def placeholders(s: str) -> Counter:
    c = Counter()
    for r in PLACEHOLDER_RES:
        c.update(r.findall(s))
    return c


# --- JSON with source spans of string values ------------------------------------------------------

class SpanParser:
    """Minimal JSON parser recording (start, end) offsets of every string *value* by its path."""

    WS = " \t\n\r"

    def __init__(self, src: str):
        self.s = src
        self.i = 0
        self.spans: dict[tuple, tuple[int, int]] = {}

    def parse(self):
        self._ws()
        v = self._value(())
        self._ws()
        if self.i != len(self.s):
            raise ValueError(f"trailing data at {self.i}")
        return v

    def _ws(self):
        s, n = self.s, len(self.s)
        while self.i < n and s[self.i] in self.WS:
            self.i += 1

    def _value(self, path):
        c = self.s[self.i]
        if c == "{":
            return self._object(path)
        if c == "[":
            return self._array(path)
        if c == '"':
            st = self.i
            v = self._string()
            self.spans[path] = (st, self.i)
            return v
        m = re.compile(r"-?\d+(\.\d+)?([eE][-+]?\d+)?|true|false|null").match(self.s, self.i)
        if not m:
            raise ValueError(f"bad JSON at {self.i}")
        self.i = m.end()
        return json.loads(m.group(0))

    def _string(self):
        st = self.i
        self.i += 1
        s, n = self.s, len(self.s)
        while self.i < n:
            c = s[self.i]
            if c == "\\":
                self.i += 2
                continue
            if c == '"':
                self.i += 1
                return json.loads(s[st:self.i])
            self.i += 1
        raise ValueError("unterminated string")

    def _object(self, path):
        self.i += 1
        out = {}
        self._ws()
        if self.s[self.i] == "}":
            self.i += 1
            return out
        while True:
            self._ws()
            k = self._string()
            self._ws()
            assert self.s[self.i] == ":", f"':' expected at {self.i}"
            self.i += 1
            self._ws()
            out[k] = self._value(path + (k,))
            self._ws()
            c = self.s[self.i]
            self.i += 1
            if c == "}":
                return out
            assert c == ",", f"',' expected at {self.i - 1}"

    def _array(self, path):
        self.i += 1
        out = []
        self._ws()
        if self.s[self.i] == "]":
            self.i += 1
            return out
        while True:
            self._ws()
            out.append(self._value(path + (len(out),)))
            self._ws()
            c = self.s[self.i]
            self.i += 1
            if c == "]":
                return out
            assert c == ",", f"',' expected at {self.i - 1}"


def _set(doc, path, value):
    for p in path[:-1]:
        doc = doc[p]
    doc[path[-1]] = value


def _encode(value: str, original_token: str) -> str:
    # Same style as the files: UTF-8 literally (ensure_ascii=False). Keep \u-escapes if the file used them.
    if "\\u" in original_token and not re.search(r"\\u00[0-7]", original_token):
        return json.dumps(value, ensure_ascii=True)
    return json.dumps(value, ensure_ascii=False)


# --- TSV --------------------------------------------------------------------------------------------

def read_tsv(path: Path, errors: list[str]):
    raw = path.read_text(encoding="utf-8-sig")
    lines = raw.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines:
        errors.append("TSV is empty")
        return []
    header = [h.strip() for h in lines[0].rstrip("\r").split("\t")]
    for need in ("id", "text", "new_text"):
        if need not in header:
            errors.append(f"TSV header has no column '{need}' (header: {header})")
    if errors:
        return []
    ci, ct, cn = header.index("id"), header.index("text"), header.index("new_text")
    rows = []
    for no, ln in enumerate(lines[1:], 2):
        ln = ln.rstrip("\r")
        if ln.strip() == "":
            continue
        f = ln.split("\t")
        if len(f) > len(header):
            errors.append(f"line {no}: {len(f)} fields, header has {len(header)} (unescaped tab?)")
            continue
        f += [""] * (len(header) - len(f))
        rows.append((no, ex.unesc(f[ci]), ex.unesc(f[ct]), ex.unesc(f[cn])))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description="Import edited texts (column new_text) back into data/story.")
    ap.add_argument("tsv", help="TSV from tools/export_texts.py with an extra column new_text")
    ap.add_argument("--dry-run", action="store_true", help="only report what would change")
    a = ap.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    tsv_rows = read_tsv(Path(a.tsv), errors)
    if errors:
        return _fail(errors)

    fresh = {r.id: r for r in ex.collect()}
    seen: dict[str, int] = {}
    for no, rid, _, _ in tsv_rows:
        if rid in seen:
            errors.append(f"line {no}: duplicate id {rid} (first at line {seen[rid]})")
        seen.setdefault(rid, no)
    missing = [i for i in fresh if i not in seen]
    unknown = [(no, i) for no, i, _, _ in tsv_rows if i not in fresh]
    if missing:
        errors.append(f"{len(missing)} id(s) of the current export are missing in the TSV (rows lost?):")
        errors += [f"  missing: {i}" for i in missing[:50]] + ([f"  … and {len(missing) - 50} more"] if len(missing) > 50 else [])
    if unknown:
        errors.append(f"{len(unknown)} unknown id(s) in the TSV (not in the current data):")
        errors += [f"  line {no}: {i}" for no, i in unknown[:50]]

    changes = []   # (row, new_text)
    for no, rid, text, new in tsv_rows:
        r = fresh.get(rid)
        if r is None or new == "" or new == text:
            continue
        if text != r.text:
            errors.append(f"line {no}: {rid}: column text differs from current data — export is stale "
                          f"(or the spreadsheet changed quoting); re-export and move the edits")
            continue
        if new == r.text:
            continue
        if not r.importable:
            warnings.append(f"line {no}: {rid}: hard-coded in {r.file} — not imported, change it in code")
            continue
        if new.startswith("@"):
            errors.append(f"line {no}: {rid}: new_text starts with '@' (would become a key reference)")
            continue
        po, pn = placeholders(r.text), placeholders(new)
        if po != pn:
            lost = list((po - pn).elements())
            added = list((pn - po).elements())
            errors.append(f"line {no}: {rid}: placeholders/markup differ — lost {lost}, added {added}")
            continue
        if new != new.strip() and r.text == r.text.strip():
            warnings.append(f"line {no}: {rid}: new_text has leading/trailing spaces")
        if new.count("\n") != r.text.count("\n"):
            warnings.append(f"line {no}: {rid}: number of line breaks changed ({r.text.count(chr(10))} → {new.count(chr(10))})")
        changes.append((r, new))

    # A line with voice_text: voice_text without its [tags] must equal text (tools/validate_voice.py, item 6).
    new_by_id = {r.id: n for r, n in changes}
    for rid, r in fresh.items():
        if rid.endswith(".voice_text"):
            tid = rid[: -len(".voice_text")] + ".text"
            if tid in fresh and (tid in new_by_id or rid in new_by_id):
                t = new_by_id.get(tid, fresh[tid].text)
                v = new_by_id.get(rid, r.text)
                if " ".join(re.sub(r"\[[^\[\]]*\]", "", v).split()) != " ".join(t.split()):
                    warnings.append(f"{rid}: voice_text without [tags] no longer equals {tid} — edit both")

    for w in warnings:
        print("WARNING: " + w)
    if errors:
        return _fail(errors)

    if not changes:
        print("[import_texts] nothing to change (new_text empty or equal to text everywhere)")
        return 0

    by_file: dict[str, list] = {}
    for r, new in changes:
        by_file.setdefault(r.file, []).append((r, new))

    # Prepare all edits first; write only if every file is consistent.
    outputs: dict[Path, str] = {}
    for rel, items in sorted(by_file.items()):
        p = ROOT / rel
        src = p.read_text(encoding="utf-8")
        sp = SpanParser(src)
        doc = sp.parse()
        edits = []
        for r, new in items:
            span = sp.spans.get(r.path)
            if span is None:
                errors.append(f"{r.id}: JSON path {r.path} not found in {rel}")
                continue
            tok = src[span[0]:span[1]]
            if json.loads(tok) != r.text:
                errors.append(f"{r.id}: value at {r.path} in {rel} is not the exported text")
                continue
            edits.append((span, _encode(new, tok)))
            _set(doc, r.path, new)
        out = src
        for (st, en), tok in sorted(edits, key=lambda e: e[0][0], reverse=True):
            out = out[:st] + tok + out[en:]
        if json.loads(out) != doc:
            errors.append(f"{rel}: internal check failed (edited JSON differs from expected)")
        outputs[p] = out
    if errors:
        return _fail(errors)

    for r, new in changes:
        print(f"{'would change' if a.dry_run else 'changed'}: {r.id}\n    old: {r.text!r}\n    new: {new!r}")
    print(f"[import_texts] {len(changes)} text(s) in {len(outputs)} file(s)" + (" — dry run, nothing written" if a.dry_run else " written"))
    if a.dry_run:
        return 0
    for p, out in outputs.items():
        fd, tmp = tempfile.mkstemp(dir=p.parent, prefix=p.name + ".", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(out)
        os.replace(tmp, p)
    print("Next: python3 tools/validate_story.py && bash tools/sync_story_data.sh\n"
          "      (voiced lines whose text changed are no longer played until re-recorded — "
          "python3 tools/validate_voice.py lists them as stale)")
    return 0


def _fail(errors: list[str]) -> int:
    print("[import_texts] FAILED — nothing written:", file=sys.stderr)
    for e in errors:
        print("  " + e, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
