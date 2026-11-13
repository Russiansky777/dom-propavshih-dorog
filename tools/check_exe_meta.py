#!/usr/bin/env python3
"""The Windows exe carries the game's own icon and name (review 12.11, finding 11: «в exe нет значка и версии» — the
exported file had the engine's icon and «Godot Engine» in its properties; Director 12.11, 23:35: «Значок — подумай
какой и отрисуй»).

    python3 tools/check_exe_meta.py build/windows/DomPropavshihDorog.exe
    python3 tools/check_exe_meta.py --self-check [<engine template .exe>]

Checks, in the exe's resources:
  - an icon group with the sizes 16, 32, 48, 64, 128, 256;
  - its 256 px picture is the game's `game/icon.png` (mean difference per channel ≤ 6 of 255);
  - ProductName and FileDescription are the game's name (`application/product_name` of the preset), CompanyName —
    the publisher (`application/company_name`).
The engine writes these itself on export (`application/modify_resources=true`) with no rcedit or Wine — verified on
Godot 4.7.2 here on 13.11 with a test project (six sizes and the strings in the exe); the 4.4 manual still asks for
rcedit, so after an engine change run this check before trusting the build.
--self-check: the engine's own export template (given, or found among the installed templates) must fail the same
checks — it has the engine's icon and name. Needs `pefile` and Pillow; exit code 2 if they are missing.
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "game" / "icon.png"
PRESETS = ROOT / "game" / "export_presets.cfg"
SIZES = [16, 32, 48, 64, 128, 256]


def preset_value(key: str) -> str:
    for line in PRESETS.read_text(encoding="utf-8").splitlines():
        if line.startswith(f"application/{key}="):
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def wanted_name() -> str:
    return preset_value("product_name")


def read_exe(path: Path) -> dict:
    import pefile

    pe = pefile.PE(str(path), fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_RESOURCE"]])
    out: dict = {"group": [], "icons": {}, "strings": {}}
    for t in getattr(getattr(pe, "DIRECTORY_ENTRY_RESOURCE", None), "entries", []):
        kind = pefile.RESOURCE_TYPE.get(t.id, "")
        for e in t.directory.entries:
            for lang in e.directory.entries:
                d = lang.data.struct
                data = pe.get_data(d.OffsetToData, d.Size)
                if kind == "RT_ICON":
                    out["icons"][e.id] = data
                elif kind == "RT_GROUP_ICON" and not out["group"]:
                    n = int.from_bytes(data[4:6], "little")
                    for i in range(n):
                        rec = data[6 + 14 * i: 20 + 14 * i]
                        out["group"].append((rec[0] or 256, int.from_bytes(rec[12:14], "little")))
    for fi in getattr(pe, "FileInfo", []) or []:
        for x in fi:
            for st in getattr(x, "StringTable", []):
                for k, v in st.entries.items():
                    out["strings"][k.decode("utf-8", "replace")] = v.decode("utf-8", "replace")
    pe.close()
    return out


def icon_difference(data: bytes) -> float | None:
    """Mean difference per channel between the exe's 256 px icon and game/icon.png; None — the picture is not a PNG."""
    from PIL import Image, ImageChops, ImageStat

    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    got = Image.open(io.BytesIO(data)).convert("RGB")
    want = Image.open(ICON).convert("RGB").resize(got.size, Image.LANCZOS)
    return sum(ImageStat.Stat(ImageChops.difference(got, want)).mean) / 3.0


def problems(path: Path) -> list[str]:
    name = wanted_name()
    info = read_exe(path)
    bad: list[str] = []
    sizes = sorted(s for s, _id in info["group"])
    if sizes != SIZES:
        bad.append(f"icon sizes {sizes}, wanted {SIZES}")
    big = next((info["icons"].get(i) for s, i in info["group"] if s == 256), None)
    if big is None:
        bad.append("no 256 px icon")
    else:
        diff = icon_difference(big)
        if diff is None:
            bad.append("the 256 px icon is not a PNG — cannot be compared with game/icon.png")
        elif diff > 6.0:
            bad.append(f"the 256 px icon is not game/icon.png (mean difference {diff:.1f} of 255)")
    for key in ("ProductName", "FileDescription"):
        if not name or info["strings"].get(key) != name:
            bad.append(f"{key} is «{info['strings'].get(key, '')}», wanted «{name}»")
    # the publisher (Director 13.11, 16:18: «Издатель Yahor Zavatski») — `application/company_name` of the preset
    company = preset_value("company_name")
    if not company or info["strings"].get("CompanyName") != company:
        bad.append(f"CompanyName is «{info['strings'].get('CompanyName', '')}», wanted «{company}»")
    # the copyright line (Director 13.11, 22:45: «Строка да, верная» — «© 2026 Yahor Zavatski») — `application/copyright`
    rights = preset_value("copyright")
    if not rights or info["strings"].get("LegalCopyright") != rights:
        bad.append(f"LegalCopyright is «{info['strings'].get('LegalCopyright', '')}», wanted «{rights}»")
    return bad


def find_template() -> Path | None:
    base = Path.home() / ".local" / "share" / "godot" / "export_templates"
    for p in sorted(base.glob("*/windows_release_x86_64.exe")):
        return p
    return None


def main(argv: list[str]) -> int:
    try:
        import pefile  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError as e:
        print(f"check_exe_meta: {e} — pip install pefile pillow")
        return 2
    if argv and argv[0] == "--self-check":
        tpl = Path(argv[1]) if len(argv) > 1 else find_template()
        if tpl is None or not tpl.exists():
            print("check_exe_meta --self-check: no engine template to try")
            return 2
        bad = problems(tpl)
        if not any("icon" in b for b in bad) or not any("ProductName" in b for b in bad):
            print(f"check_exe_meta: self-check FAILED — the engine's template {tpl.name} passes: {bad}")
            return 1
        print(f"check_exe_meta: self-check OK — the engine's template is caught ({len(bad)} differences)")
        return 0
    if len(argv) != 1:
        print(__doc__)
        return 2
    exe = Path(argv[0])
    bad = problems(exe)
    if bad:
        print(f"check_exe_meta: {exe.name} FAILED")
        for b in bad:
            print(f"  - {b}")
        return 1
    print(f"check_exe_meta: {exe.name} OK — the game's icon in six sizes, «{wanted_name()}» and «{preset_value('company_name')}» in the file's properties")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
