#!/usr/bin/env python3
"""I-T4 (25.10): жители v2 в игру — данные game/data/actors/<id>.json переводятся на листы assets/characters/<id>_v2
(конвейер, запросы pipeline/requests/npc_<id>_b.json): idle / listen / talk (+ walk у тех, кто ходит).

  python3 tools/i_t4_npc_v2.py nina ilya ...      (по умолчанию — все, у кого лист v2 уже в assets/characters)

Делает: tools/sync_characters.sh <id>_v2; sheet_dir → листы v2; состояния I-T2 (listen — свой клип, talk — свой, темп 1);
talk — цикл (Talk_with_Hands_Open цикличный, рот по кадрам листа), прежнее pingpong_eased реплики снято;
стойка и «слушает» — туда-обратно по листу; ходьба — цикл 1,18 м (Walking_Woman, как у Агаты).
Рост и масштаб по замыслу (npc.scale_factor) — прежние: лист нормирует фигуру по кадру.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALL = ["nina", "ilya", "ilya_wife", "ulyana", "mitya", "pelageya", "pavel", "tamara"]


def ready(i: str) -> bool:
    p = os.path.join(ROOT, "assets", "characters", f"{i}_v2", "sprites.json")
    if not os.path.exists(p):
        return False
    acts = json.load(open(p, encoding="utf-8"))["actions"]
    # черновой лист этапа A (96 px, 2 кадра) не годится — только рендер этапа B
    return "listen" in acts and acts["talk"]["frames"] >= 24


def main() -> int:
    ids = sys.argv[1:] or [i for i in ALL if ready(i)]
    for i in ids:
        if not ready(i):
            print(f"{i}: листа v2 этапа B ещё нет — пропущен")
            continue
        src = os.path.join(ROOT, "assets", "characters", f"{i}_v2", "sprites.json")
        dst = os.path.join(ROOT, "game", "assets", "characters", f"{i}_v2", "sprites.json")
        if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src):   # упаковка атласов — минуты
            subprocess.run(["bash", os.path.join(ROOT, "tools", "sync_characters.sh"), f"{i}_v2"], check=True)
        p = os.path.join(ROOT, "game", "data", "actors", f"{i}.json")
        d = json.load(open(p, encoding="utf-8"))
        sprites = json.load(open(os.path.join(ROOT, "assets", "characters", f"{i}_v2", "sprites.json"), encoding="utf-8"))
        d["sheet_dir"] = f"res://assets/characters/{i}_v2"
        d["_comment_v2"] = ("I-T4 (25.10): модель v2 по листу ChatGPT (assets/reference/npc_v2), Meshy → Blender "
                            "(pipeline/3d/npc_v2/build_npc.py) → рендер 2,25× (pipeline/requests/npc_%s_b.json). "
                            "Состояния: idle — стойка Text to Motion, listen — «слушает» (кивок), talk — Talk_with_Hands_Open "
                            "с ртом по кадрам листа%s. Перенос данных — tools/i_t4_npc_v2.py." %
                            (i, ", walk — ходьба Meshy (уходит шагом в постановке)" if "walk" in sprites["actions"] else ""))
        acts = d.setdefault("actions", {})
        acts["_comment"] = ("I-T4: стойка и «слушает» — туда-обратно по листу (стойка — по замеру measure_idle --all-frames: "
                            "все 24 кадра окна, время по пути); "
                            "реплика — цикл листа (клип цикличный).")
        acts.pop("talk", None)
        acts["idle"] = {"playback": "pingpong_eased", "period_s": 3.6, "hold_s": 0.2}
        acts["listen"] = {"playback": "pingpong_eased", "period_s": 3.0, "hold_s": 0.2}
        d["states"] = {"_comment": "I-T4: свои клипы v2 для состояний I-T2.",
                       "listen": {"action": "listen", "speed": 1.0}, "talk": {"action": "talk", "speed": 1.0}}
        if "walk" in sprites["actions"]:
            d["walk_action"] = "walk"
            w = d.setdefault("walk", {})
            w["cycle_meters"] = 1.18
            w["speed_mps"] = 1.0
        em = d.get("eased_motion", {})
        em.pop("talk", None)
        em.pop("idle", None)
        d["eased_motion"] = em
        json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        open(p, "a", encoding="utf-8").write("\n")
        # все кадры окна (в нём и развороты на нулевой скорости), время — по измеренному пути
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "measure_idle.py"), i, "--write", "--all-frames",
                        "--period", "3.6", "--hold", "0.2"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "measure_idle.py"), i, "--write", "--all-frames",
                        "--action", "listen", "--period", "3.0", "--hold", "0.2"], check=True, stdout=subprocess.DEVNULL)
        print(f"{i}: v2 в данных")
    return 0


if __name__ == "__main__":
    sys.exit(main())
