#!/usr/bin/env python3
"""Быстрая проверка GDScript без Godot (партия J, 29.10): дефект b278bf83 — в carved_frame.gd функции rosette / leaf /
shade / draw_rail объявлены дважды, класс CarvedFrame не разбирался, и вся игра не компилировалась (main.gd), а тесты
частью проходили. Ищет то, что Godot считает ошибкой разбора всего файла:
  - одно имя функции дважды на верхнем уровне файла (func / static func);
  - одно имя var / const / signal / enum дважды на верхнем уровне;
  - одно class_name в двух файлах.
Код 0 — чисто; 1 — ошибки (печатает файл:строка). Запуск: python3 tools/check_gdscript.py [--quiet]"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
TOP = re.compile(r"^(?:static\s+)?(func|var|const|signal|enum)\s+([A-Za-z_]\w*)")
CLASS = re.compile(r"^class_name\s+([A-Za-z_]\w*)")


def main() -> int:
    quiet = "--quiet" in sys.argv
    errors = []
    classes = {}
    files = sorted(p for p in ROOT.rglob("*.gd") if "/.godot/" not in str(p) and "/addons/" not in str(p))
    for f in files:
        seen = {}
        for n, line in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = CLASS.match(line)
            if m:
                classes.setdefault(m.group(1), []).append(f"{f.relative_to(ROOT)}:{n}")
                continue
            m = TOP.match(line)
            if not m:
                continue
            kind = "func" if m.group(1) == "func" else "member"
            key = (kind, m.group(2))
            if key in seen:
                errors.append(f"{f.relative_to(ROOT)}:{n}: «{m.group(2)}» уже объявлено в строке {seen[key]} — Godot не разберёт файл")
            else:
                seen[key] = n
    for name, where in classes.items():
        if len(where) > 1:
            errors.append(f"class_name {name} в нескольких файлах: {', '.join(where)}")
    for e in errors:
        print("  ОШИБКА", e)
    if not quiet or errors:
        print(f"[gdscript] check_gdscript.py: {len(files)} файлов, ошибок {len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
