#!/usr/bin/env python3
"""Скачать исходные клипы из clips.json (stdlib): Mesh2Motion и зеркало BVH CMU — с GitHub по закреплённым коммитам,
100STYLE — архив с Zenodo (проверка md5), из него — только нужные BVH.

  python3 fetch_sources.py --clips clips.json --out _src
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

RAW = {"m2m": "https://raw.githubusercontent.com/Mesh2Motion/mesh2motion-app/{sha}/{path}",
       "cmu": "https://raw.githubusercontent.com/Shriinivas/cmubvh/{sha}/{path}"}


def get(url: str, dst: Path, md5: str | None = None) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            h = hashlib.md5()
            with urllib.request.urlopen(url, timeout=120) as r, open(dst, "wb") as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
                    h.update(chunk)
            if md5 and h.hexdigest() != md5:
                raise IOError(f"md5 {h.hexdigest()} != {md5}")
            print(f"  {url} → {dst} ({dst.stat().st_size} байт){' md5 OK' if md5 else ''}", flush=True)
            return
        except Exception as e:  # noqa: BLE001
            print(f"  попытка {attempt + 1}: {url}: {e}", flush=True)
            time.sleep(5 * (attempt + 1))
    raise SystemExit(f"не скачалось: {url}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    cfg = json.load(open(args.clips, encoding="utf-8"))
    pins = cfg["pins"]
    out = Path(args.out)
    need100 = []
    for c in cfg["clips"]:
        f = c["source"].get("file")
        if not f:
            continue
        lib, rel = f.split(":", 1)
        rel = rel.split("!", 1)[0]
        if lib in RAW:
            dst = out / lib / rel
            if not dst.exists():
                get(RAW[lib].format(sha=pins[lib], path=urllib.parse.quote(rel)), dst)
        elif lib == "100style":
            need100.append(rel)
    if need100:
        z = out / "_100STYLE.zip"
        get(pins["zenodo_100style"], z, pins.get("zenodo_100style_md5"))
        with zipfile.ZipFile(z) as zf:
            names = set(zf.namelist())
            for rel in need100:
                if rel not in names:
                    raise SystemExit(f"нет в архиве 100STYLE: {rel}")
                dst = out / "100style" / rel
                dst.parent.mkdir(parents=True, exist_ok=True)
                dst.write_bytes(zf.read(rel))
                print(f"  100STYLE: {rel} ({dst.stat().st_size} байт)", flush=True)
        z.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())
