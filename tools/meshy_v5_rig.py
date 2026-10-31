#!/usr/bin/env python3
"""Agata v5: Meshy auto-rig of a chosen candidate (01.11; Director 31.10 «переделать Агату целиком»). Run in the workflow
meshy-agata-v5 (mode rig) after tools/v5_rig_input.py has made agata_v5<V>_rig_input.glb and the workflow has put it in
the release agata-v5-work (Meshy reads it by its public URL). 5 credits; the rigged GLB → release agata-v5-work.
Clips come from Agata v4's rig (same Meshy skeleton, pipeline/3d/retarget_clips.py, 0 credits) — no actions here.
  python3 tools/meshy_v5_rig.py --variant H --out _v5
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pipeline" / "3d"))
import meshy_client as mc  # noqa: E402

URL = "https://github.com/Russiansky777/dom-propavshih-dorog/releases/download/agata-v5-work/agata_v5{v}_rig_input.glb"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", required=True)
    ap.add_argument("--out", default="_v5")
    ap.add_argument("--resume", default="")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    print(f"баланс: {mc.balance()}", flush=True)
    tid = a.resume or mc.create("/rigging", {"model_url": URL.format(v=a.variant), "height_meters": 1.65})
    print(f"риг {a.variant}: задача {tid}", flush=True)
    t = mc.wait("/rigging", tid, poll_s=10, max_s=3600, log=lambda m: print(m, flush=True))
    res = t.get("result") or {}
    mc.download(res["rigged_character_glb_url"], out / f"agata_v5{a.variant}_rigged.glb")
    ba = res.get("basic_animations") or {}
    if ba.get("walking_glb_url"):
        mc.download(ba["walking_glb_url"], out / f"agata_v5{a.variant}_rig_walking.glb")
    keep = {k: t.get(k) for k in ("id", "status", "consumed_credits", "created_at", "finished_at")}
    (out / f"agata_v5{a.variant}_rig_task.json").write_text(json.dumps(keep, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"риг {a.variant}: готово, кредитов {t.get('consumed_credits')}", flush=True)
    print(f"баланс после: {mc.balance()}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
