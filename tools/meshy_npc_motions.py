#!/usr/bin/env python3
"""Жители v3 — движения действий (блок 3, Директор 05.11: «где кто-то делает что-то, что можно отразить анимацией»):
Text to Motion Meshy (prime, 10 кредитов за движение) → на риг жителя v3 (/animations с motion_task_id, 3 кредита).
Одно движение может лечь на несколько ригов (смолят лодку — Митя и Пелагея): оно создаётся один раз.

  python3 tools/meshy_npc_motions.py --request pipeline/requests/v3/npc_v3_motions.json --rigs _v3 --out _v3 [--only a,b]

--rigs: папка с <имя>_v3_<проба>_rig_task.json (из релиза npc-v3-work; проба — поле "rigs" запроса).
Состояние (id задач) — <out>/motions_state.json; если оно уже есть (скачано из релиза), задачи не создаются заново.
Итог — <out>/<имя>_m_<движение>.glb (риг с одним клипом) → релиз npc-v3-work; в игру — tools/build_npc_v3.sh.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pipeline" / "3d"))
import meshy_client as mc  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--request", required=True)
    ap.add_argument("--rigs", default="_v3")
    ap.add_argument("--out", default="_v3")
    ap.add_argument("--only", default="", help="только эти движения (через запятую)")
    a = ap.parse_args()
    req = json.loads(Path(a.request).read_text(encoding="utf-8"))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    sp = out / "motions_state.json"
    st = json.loads(sp.read_text(encoding="utf-8")) if sp.exists() else {"motions": {}, "apply": {}}
    only = {x for x in a.only.split(",") if x}

    def save() -> None:
        sp.write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")

    # "redo": {движение: метка} — движение переделать один раз (новая формулировка): прежние задачи и наложения
    # забываются, новая задача запоминает метку
    for m, tag in (req.get("redo") or {}).items():
        if st["motions"].get(m, {}).get("tag") != tag:
            st["motions"].pop(m, None)
            for k in [k for k in st["apply"] if k.endswith("/" + m)]:
                st["apply"].pop(k)
            st.setdefault("redo_pending", {})[m] = tag
    rig_ids = {}
    for who, s in req["rigs"].items():
        f = Path(a.rigs) / f"{who}_v3_{s}_rig_task.json"
        if f.exists():
            rig_ids[who] = json.loads(f.read_text(encoding="utf-8"))["id"]
    print(f"риги: {sorted(rig_ids)}; баланс: {mc.balance()}", flush=True)
    jobs = [(who, m) for who, ms in req["apply"].items() for m in ms if who in rig_ids and (not only or m in only)]
    need = sorted({m for _, m in jobs})
    # 1. движения
    for m in need:
        if m in st["motions"] and st["motions"][m].get("status") == "SUCCEEDED":
            continue
        cfg = {k: v for k, v in req["motions"][m].items() if not k.startswith("_")}
        cfg.setdefault("mode", "prime")
        if "task" not in st["motions"].get(m, {}):
            st["motions"][m] = {"task": mc.create("/text-to-motion", cfg)}
            if m in st.get("redo_pending", {}):
                st["motions"][m]["tag"] = st["redo_pending"].pop(m)
            save()
            print(f"движение {m}: задача {st['motions'][m]['task']}", flush=True)
    for m in need:
        e = st["motions"][m]
        if e.get("status") == "SUCCEEDED":
            continue
        try:
            t = mc.wait("/text-to-motion", e["task"], poll_s=10, max_s=2400, log=lambda x: None)
            e["status"] = "SUCCEEDED"
            e["credits"] = t.get("consumed_credits")
        except mc.MeshyError as ex:
            e["status"] = "FAILED"
            e["error"] = str(ex)
            print(f"движение {m}: {ex}", flush=True)
        save()
    # 2. на риги
    for who, m in jobs:
        if st["motions"].get(m, {}).get("status") != "SUCCEEDED":
            continue
        key = f"{who}/{m}"
        e = st["apply"].setdefault(key, {})
        if e.get("status") == "SUCCEEDED" and (out / f"{who}_m_{m}.glb").exists():
            continue
        if "task" not in e:
            e["task"] = mc.create("/animations", {"rig_task_id": rig_ids[who], "motion_task_id": st["motions"][m]["task"]})
            save()
        try:
            t = mc.wait("/animations", e["task"], poll_s=10, max_s=2400, log=lambda x: None)
            mc.download(t["result"]["animation_glb_url"], out / f"{who}_m_{m}.glb")
            e["status"] = "SUCCEEDED"
            e["credits"] = t.get("consumed_credits")
            print(f"{key}: готово ({(out / f'{who}_m_{m}.glb').stat().st_size // 1024} КБ)", flush=True)
        except mc.MeshyError as ex:
            e["status"] = "FAILED"
            e["error"] = str(ex)
            print(f"{key}: {ex}", flush=True)
        save()
    print(f"баланс после: {mc.balance()}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
