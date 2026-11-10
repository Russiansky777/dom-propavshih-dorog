#!/usr/bin/env python3
"""A test run's log must hold no script error (10.11).

A GDScript error inside a test function stops that function where it stands: nothing after it is checked, and the
test still counts as passed. Found in the first full run after the night 09→10.11: test_ui_cursors called a handler
removed on 05.11, test_batch_j read a shader parameter gone since 02.11 — both «green» and blind for days.

  python3 tools/check_test_log.py build/logs/tests.log      exit 1 and the lines when the log holds a script error
  python3 tools/check_test_log.py --self-check              the check itself: a log with one is caught, a clean one passes
"""
import re
import sys

BAD = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Failed to load script")


def problems(text: str) -> list[str]:
    out = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if BAD.search(line):
            where = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].strip().startswith("at:") else ""
            out.append(f"{i + 1}: {line.strip()} {where}".rstrip())
    return out


def self_check() -> int:
    blind = (
        "PASS  Hotspots: object → look  (629 ms)\n"
        "SCRIPT ERROR: Invalid call. Nonexistent function '_on_hint_pressed (via call)' in base 'CanvasLayer (game_ui.gd)'.\n"
        "          at: _test_hint_panel (res://tests/test_ui_cursors.gd:344)\n"
        "==== ui cursors: 5 tests, 5 passed, 0 failed ====\n"
    )
    clean = (
        "ERROR: GameState: save 'test_saves_1_dmg' is damaged (and no sound copy)\n"   # a test of a damaged save: expected
        "ERROR: Parse JSON failed. Error at line 25: Expected key\n"
        "==== saves: 9 tests, 9 passed, 0 failed ====\n"
    )
    got = problems(blind)
    if len(got) != 1 or "test_ui_cursors.gd:344" not in got[0]:
        print(f"self-check FAILED: a log with a script error gives {got}")
        return 1
    if problems(clean):
        print(f"self-check FAILED: a clean log (expected ERROR lines of negative tests) gives {problems(clean)}")
        return 1
    print("check_test_log self-check: OK (a script error in a «green» test is caught; expected ERROR lines are not)")
    return 0


def main() -> int:
    if "--self-check" in sys.argv:
        return self_check()
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        found = problems(f.read())
    if found:
        print(f"[tests] script errors in the run ({len(found)}) — a test that stops on one checks nothing after it:")
        for line in found[:20]:
            print("    " + line)
        return 1
    print("[tests] no script errors in the run")
    return 0


if __name__ == "__main__":
    sys.exit(main())
