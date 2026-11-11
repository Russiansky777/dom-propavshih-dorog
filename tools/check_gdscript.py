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
    загружают в тесте по пути: load("res://scripts/…");
  - такой тест называет саму автозагрузку (RoomManager.player): её берут узлом root.get_node("RoomManager");
  - метод скрипта с именем метода движка его класса (11.11: is_pickable() в story_hotspot.gd — Area2D уже его имеет;
    Godot: «overrides a method from native class», предупреждение = ошибка, файл не компилируется, а с ним и вся игра).
    Имена методов движка — tools/godot_native_methods.json (из godot --dump-extension-api); самопроверка — тот случай.
  - шейдер (строка «shader_type …» в .gd или файл .gdshader), где вспомогательная функция берёт встроенное имя стадии
    (TEXTURE, UV, COLOR, SCREEN_UV, FRAGCOORD, VERTEX…): Godot видит их только в fragment()/vertex()/light() — «Unknown
    identifier», шейдер не собирается, слой рисуется как есть без ошибки в тестах без экрана (11.11: вода переправы,
    water_at() в crossing_panel.gd). Самопроверка — тот случай.
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


NATIVE = Path(__file__).resolve().parent / "godot_native_methods.json"
EXTENDS = re.compile(r"^extends\s+(\w+)", re.M)
FUNC = re.compile(r"^func\s+([A-Za-z]\w*)\s*\(")


def native_overrides(files) -> list:
    """file:line of every script function named as a (non-virtual) method of the engine class it extends, through the
    chain of the game's own classes (extends <class_name>) down to the engine's."""
    import json
    if not NATIVE.exists():
        return [f"нет {NATIVE.name} — пересоздайте: python3 tools/check_gdscript.py --refresh-native <extension_api.json>"]
    nat = json.loads(NATIVE.read_text(encoding="utf-8"))["classes"]
    texts = {f: f.read_text(encoding="utf-8", errors="replace") for f in files}
    own = {}
    for f, t in texts.items():
        m = re.search(r"^class_name\s+(\w+)", t, re.M)
        if m:
            own[m.group(1)] = f

    def native_methods(base: str, depth: int = 0) -> set:
        if depth > 20:
            return set()
        if base in own:
            m = EXTENDS.search(texts[own[base]])
            return native_methods(m.group(1), depth + 1) if m else set()
        out = set()
        while base in nat:
            out |= set(nat[base]["methods"])
            base = nat[base]["inherits"]
        return out

    errs = []
    for f, t in texts.items():
        m = EXTENDS.search(t)
        if not m:
            continue
        names = native_methods(m.group(1))
        for n, ln in enumerate(t.splitlines(), 1):
            fm = FUNC.match(ln)
            if fm and fm.group(1) in names:
                errs.append(f"{f.relative_to(ROOT)}:{n}: метод «{fm.group(1)}» — так уже называется метод движка у {m.group(1)}: "
                            f"Godot не скомпилирует файл (overrides a method from native class); назовите иначе")
    return errs


STAGE_BUILTINS = ("TEXTURE", "UV", "COLOR", "SCREEN_UV", "FRAGCOORD", "VERTEX", "TEXTURE_PIXEL_SIZE", "SCREEN_PIXEL_SIZE",
                  "NORMAL", "NORMAL_MAP", "ALBEDO", "ALPHA", "EMISSION", "ROUGHNESS", "VIEW", "POINT_COORD")
STAGES = {"fragment", "vertex", "light", "start", "process", "sky"}
SHADER_FN = re.compile(r"^\s*(?:\w+\s+)+?(\w+)\s*\(([^)]*)\)\s*\{", re.M)


def shader_stage_problems(code: str, where: str) -> list:
    """Helper functions of one shader that name a stage's built-in."""
    out = []
    for m in SHADER_FN.finditer(code):
        name = m.group(1)
        if name in STAGES or name in ("if", "for", "while", "switch"):
            continue
        depth, i = 1, m.end()
        while i < len(code) and depth > 0:
            depth += {"{": 1, "}": -1}.get(code[i], 0)
            i += 1
        body = re.sub(r"//[^\n]*", "", code[m.end():i])
        for b in STAGE_BUILTINS:
            if re.search(r"(?<![\w.])%s(?!\w)" % b, body):
                out.append(f"{where}: шейдер, функция {name}() берёт {b} — оно есть только в fragment()/vertex()/light(); "
                           f"шейдер не соберётся. Передайте значение аргументом или читайте в fragment()")
    return out


def shader_problems(files) -> list:
    errors = []
    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        if f.suffix == ".gdshader":
            errors += shader_stage_problems(text, str(f.relative_to(ROOT)))
            continue
        for m in re.finditer(r'"((?:\\.|[^"\\])*)"', text):
            body = m.group(1)
            if "shader_type" not in body:
                continue
            code = body.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"')
            line = text.count("\n", 0, m.start()) + 1
            errors += shader_stage_problems(code, f"{f.relative_to(ROOT)}:{line}")
    return errors


def _shader_selfcheck() -> list:
    """The defect of 11.11 must be caught: TEXTURE read in a helper; the same read in fragment() is fine."""
    bad = "shader_type canvas_item;\nvec4 water_at(vec2 q) {\n\treturn texture(TEXTURE, q);\n}\nvoid fragment() { COLOR = water_at(UV); }\n"
    good = "shader_type canvas_item;\nvec2 water_uv(vec2 q) {\n\treturn q * 0.5;\n}\nvoid fragment() { COLOR = texture(TEXTURE, water_uv(UV)); }\n"
    a = shader_stage_problems(bad, "probe")
    b = shader_stage_problems(good, "probe")
    if len(a) != 1 or "water_at" not in a[0] or b:
        return [f"самопроверка шейдеров: TEXTURE во вспомогательной функции не пойман или пойман лишний: {a} {b}"]
    return []


def _native_selfcheck() -> list:
    """The defect of 11.11 must be caught: a hotspot (Area2D) with func is_pickable()."""
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "probe.gd"
        f.write_text("extends Area2D\nfunc is_pickable() -> bool:\n\treturn true\nfunc can_click() -> bool:\n\treturn true\n", encoding="utf-8")
        global ROOT
        keep = ROOT
        ROOT = Path(d)
        try:
            got = native_overrides([f])
        finally:
            ROOT = keep
    if len(got) != 1 or "is_pickable" not in got[0]:
        return [f"самопроверка: is_pickable() у Area2D не пойман (или пойман лишний): {got}"]
    return []


def main() -> int:
    if "--refresh-native" in sys.argv:
        import json
        api = json.loads(Path(sys.argv[sys.argv.index("--refresh-native") + 1]).read_text(encoding="utf-8"))
        cls = {c["name"]: c for c in api["classes"]}
        old = json.loads(NATIVE.read_text(encoding="utf-8")) if NATIVE.exists() else {}
        need = set()
        for f in ROOT.rglob("*.gd"):
            m = EXTENDS.search(f.read_text(encoding="utf-8", errors="replace"))
            c = m.group(1) if m else ""
            while c in cls:
                need.add(c)
                c = cls[c].get("inherits", "")
        out = {"_comment": old.get("_comment", ""), "version": api["header"].get("version_full_name"),
               "classes": {n: {"inherits": cls[n].get("inherits", ""), "methods": sorted(m["name"] for m in cls[n].get("methods", []) if not m.get("is_virtual"))} for n in sorted(need)}}
        NATIVE.write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding="utf-8")
        print(f"{NATIVE.name}: {len(need)} классов")
        return 0
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
        # The autoloads themselves by name (30.10: RoomManager.player in test_batch_j.gd — «Identifier not found:
        # RoomManager»): a godot -s test reaches them through root.get_node("RoomManager").
        for a in re.findall(r'^(\w+)="\*res://', (ROOT / "project.godot").read_text(encoding="utf-8"), re.M):
            if re.search(r"\bvar\s+%s\b" % a, code):
                continue
            for n, ln in enumerate(code.splitlines(), 1):
                if re.search(r"(?<![.\w])%s\s*\." % a, ln):
                    errors.append(f"{f.relative_to(ROOT)}:{n}: автозагрузка {a} по имени в тесте (godot -s) — тест не скомпилируется; "
                                  f"возьмите узел: root.get_node(\"{a}\")")
                    break
        for c in need_auto:
            if re.search(r"\bvar\s+%s\b" % c, code):   # a local `var TimingBar: GDScript = load(...)` shadows the class
                continue
            for n, ln in enumerate(code.splitlines(), 1):
                if re.search(r"(?<![.\w])%s\b" % c, ln):
                    errors.append(f"{f.relative_to(ROOT)}:{n}: класс {c} по имени в тесте (godot -s) — ему нужны автозагрузки, "
                                  f"тест не скомпилируется; загрузите его: load(\"res://{need_auto[c].relative_to(ROOT)}\")")
                    break
    errors += native_overrides(files)
    errors += _native_selfcheck()
    errors += shader_problems(files + sorted(p for p in ROOT.rglob("*.gdshader") if "/.godot/" not in str(p) and "/addons/" not in str(p)))
    errors += _shader_selfcheck()
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
