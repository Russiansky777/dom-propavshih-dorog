#!/usr/bin/env python3
"""Режиссура озвучки (`direction`) у строк по id выгрузки текстов — точечно, без переформатирования файлов (I-T5).

    python3 -I tools/set_direction.py PATH.json [--dry-run]

PATH.json — список [{"id": "<id tools/export_texts.py>", "direction": {...}, "tags": [...]?}]. Поле direction ставится там, где его
читает конвейер озвучки (pipeline/voice/eleven_voice.py): у реплики сцены / её `then` — в самой реплике, у текста
`text:<ключ>` и `text:<ключ>#line` — в записи ключа. Есть direction — заменяется целиком; нет — вписывается сразу после
значения "text" этой записи. "_merge": true — поля сливаются с прежним direction (новые важнее). Остальной файл (отступы, порядок ключей) не меняется. Ошибка в любой строке — не пишется ничего.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).resolve().parent / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


imp = _load("import_texts")
ex = imp.ex


class ObjSpanParser(imp.SpanParser):
    """SpanParser, который помнит и (начало, конец) значений-объектов."""

    def __init__(self, src: str):
        super().__init__(src)
        self.objs: dict[tuple, tuple[int, int]] = {}

    def _object(self, path):
        st = self.i
        out = super()._object(path)
        self.objs[path] = (st, self.i)
        return out

    def _array(self, path):
        st = self.i
        out = super()._array(path)
        self.objs[path] = (st, self.i)
        return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("spec")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    items = json.loads(Path(a.spec).read_text(encoding="utf-8"))
    rows = {r.id: r for r in ex.collect()}
    errors: list[str] = []
    by_file: dict[str, list[tuple[tuple, dict]]] = {}
    for it in items:
        r = rows.get(it["id"])
        if r is None:
            errors.append(f"нет id {it['id']} в выгрузке")
            continue
        path = tuple(r.path)
        obj = path[:2] if it["id"].startswith("text:") else path[:-1]
        if "direction" in it:
            by_file.setdefault(str(r.file), []).append((obj, dict(it["direction"])))
        if "tags" in it:
            # tags — у самой строки (у `#line` — в line, у осмотра — в записи ключа, у реплики сцены — в реплике)
            by_file.setdefault(str(r.file), []).append((path[:-1], {"_tags": list(it["tags"])}))
    if errors:
        print("\n".join(errors))
        return 1
    for f, edits in by_file.items():
        p = Path(f) if Path(f).is_absolute() else ROOT / f
        src = p.read_text(encoding="utf-8")
        sp = ObjSpanParser(src)
        sp.parse()
        ops = []
        for obj, d in edits:
            if "_tags" in d:
                enc = json.dumps(d["_tags"], ensure_ascii=False)
                if obj + ("tags",) in sp.objs:
                    ops.append((sp.objs[obj + ("tags",)], enc))
                elif obj + ("text",) in sp.spans:
                    end = sp.spans[obj + ("text",)][1]
                    ops.append(((end, end), f', "tags": {enc}'))
                continue
            if obj + ("direction",) in sp.objs and d.pop("_merge", False):
                s0, e0 = sp.objs[obj + ("direction",)]
                d = {**json.loads(src[s0:e0]), **d}
            d.pop("_merge", None)
            enc = json.dumps(d, ensure_ascii=False)
            if obj + ("direction",) in sp.objs:
                ops.append((sp.objs[obj + ("direction",)], enc))
            elif obj + ("text",) in sp.spans:
                end = sp.spans[obj + ("text",)][1]
                ops.append(((end, end), f', "direction": {enc}'))
            else:
                errors.append(f"{f}: у {obj} нет text")
        if errors:
            print("\n".join(errors))
            return 1
        for (s, e), new in sorted(ops, key=lambda o: o[0][0], reverse=True):
            src = src[:s] + new + src[e:]
        json.loads(src)
        if not a.dry_run:
            p.write_text(src, encoding="utf-8")
        print(f"  {p.relative_to(ROOT)}: {len(ops)} direction")
    return 0


if __name__ == "__main__":
    sys.exit(main())
