#!/usr/bin/env python3
"""Быстрая проверка GDScript без Godot (партия J, 29.10): дефект b278bf83 — в carved_frame.gd функции rosette / leaf /
shade / draw_rail объявлены дважды, класс CarvedFrame не разбирался, и вся игра не компилировалась (main.gd), а тесты
частью проходили. Ищет то, что Godot считает ошибкой разбора всего файла:
  - одно имя функции дважды на верхнем уровне файла (func / static func);
  - одно имя var / const / signal / enum дважды на верхнем уровне;
  - одно class_name в двух файлах;
  - тест, который запускается сам (`extends SceneTree`, godot -s), называет по имени класс, которому нужны автозагрузки
    (StoryData, GameState…, прямо или через другой класс): тест компилируется раньше, чем они появятся, — «Identifier
    not found: StoryData», тест не загружается (J, ночь 30.10: TimingBar.slow в test_batch_j.gd). Такой класс
    загружают в тесте по пути: load("res://scripts/…").
Код 0 — чисто; 1 — ошибки (печатает файл:строка). Запуск: python3 tools/check_gdscript.py [--quiet]"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
TOP = re.compile(r"^(?:static\s+)?(func|var|const|signal|enum)\s+([A-Za-z_]\w*)")
CLASS = re.compile(r"^class_name\s+([A-Za-z_]\w*)")
STR = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')


def _code(text: str) -> str:
    """The code without strings and comments (a name in a string or a comment is not a reference)."""
    return "\n".join(STR.sub('""', ln).split("#")[0] for ln in text.splitlines())


def autoload_classes(files) -> dict:
    """class_name → file, for the classes that need the autoloads (directly or through another such class)."""
    auto = re.findall(r'^(\w+)="\*res://', (ROOT / "project.godot").read_text(encoding="utf-8"), re.M)
    cls = {}
    for f in files:
        m = re.search(r"^class_name\s+(\w+)", f.read_text(encoding="utf-8", errors="replace"), re.M)
        if m:
            cls[m.group(1)] = f
    code = {c: _code(f.read_text(encoding="utf-8", errors="replace")) for c, f in cls.items()}
    bad = {c for c in cls if any(re.search(r"\b%s\b" % a, code[c]) for a in auto)}
    grew = True
    while grew:
        grew = False
        for c in cls:
            if c not in bad and any(re.search(r"\b%s\b" % o, code[c]) for o in bad if o != c):
                bad.add(c)
                grew = True
    return {c: cls[c] for c in bad}


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
    need_auto = autoload_classes(files)
    for f in files:
        if "/tests/" not in str(f):
            continue
        code = _code(f.read_text(encoding="utf-8", errors="replace"))
        if "extends SceneTree" not in code:
            continue
        for c in need_auto:
            if re.search(r"\bvar\s+%s\b" % c, code):   # a local `var TimingBar: GDScript = load(...)` shadows the class
                continue
            for n, ln in enumerate(code.splitlines(), 1):
                if re.search(r"(?<![.\w])%s\b" % c, ln):
                    errors.append(f"{f.relative_to(ROOT)}:{n}: класс {c} по имени в тесте (godot -s) — ему нужны автозагрузки, "
                                  f"тест не скомпилируется; загрузите его: load(\"res://{need_auto[c].relative_to(ROOT)}\")")
                    break
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
