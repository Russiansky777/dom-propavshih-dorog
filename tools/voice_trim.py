#!/usr/bin/env python3
"""A voice line shortened for the game (data/story/voice_trim.json; tools/sync_voice.sh calls it per file).

    voice_trim.py <src.ogg> <dst.ogg> <lang/name.ogg>
    voice_trim.py --manifest <src manifest.json> <dst manifest.json> <lang>
The game plays a line only while its manifest's text_sha1 is the sha1 of the line on screen (voice_director.gd): the
game's copy of the manifest gets the trimmed line's text and sha1 (expected_manifest — the validators use it too).
Exit 0 — the file is one of the trims: dst is the trimmed copy (made now, or already made from this very source
with this very trim — the mark <dst>.trim.json says so; the Ogg encoder's random stream serial would change the file
on every run otherwise). Exit 1 — not a trimmed line (the caller copies it as is). Exit 2 — trim failed.
"""
import hashlib
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_trims() -> dict:
    try:
        return json.load(open(os.path.join(ROOT, "data/story/voice_trim.json"), encoding="utf-8")).get("trims", {})
    except (OSError, ValueError):
        return {}


def expected_manifest(src_manifest_text: str, lang: str) -> str:
    """The game's manifest: the pipeline's, with the trimmed lines' text and text_sha1 as they sound now."""
    trims = {k[len(lang) + 1:]: v for k, v in load_trims().items() if k.startswith(lang + "/")}
    if not trims:
        return src_manifest_text
    m = json.loads(src_manifest_text)
    lines = m.get("lines", {})
    for lid, e in lines.items():
        t = trims.get(str(e.get("file", "")))
        if t:
            e["text"] = t["text"]
            e["text_sha1"] = hashlib.sha1(t["text"].encode("utf-8")).hexdigest()
            e["trimmed"] = {"to_s": t["to_s"], "from_text_sha1": e.get("voice_sha1", "")}
    return json.dumps(m, ensure_ascii=False, indent=2) + "\n"   # the pipeline writes it so: a minimal diff


def manifest_main(src: str, dst: str, lang: str) -> int:
    want = expected_manifest(open(src, encoding="utf-8").read(), lang)
    have = open(dst, encoding="utf-8").read() if os.path.exists(dst) else None
    if have != want:
        open(dst, "w", encoding="utf-8").write(want)
        print(f"  voice/{lang}/manifest.json updated")
    return 0


def main() -> int:
    if sys.argv[1] == "--manifest":
        return manifest_main(sys.argv[2], sys.argv[3], sys.argv[4])
    src, dst, key = sys.argv[1:4]
    try:
        trims = json.load(open(os.path.join(ROOT, "data/story/voice_trim.json"), encoding="utf-8")).get("trims", {})
    except (OSError, ValueError):
        return 1
    t = trims.get(key)
    if not t:
        return 1
    md5 = hashlib.md5(open(src, "rb").read()).hexdigest()
    mark = {"src_md5": md5, "to_s": t["to_s"], "fade_s": t.get("fade_s", 0.05), "tail_s": t.get("tail_s", 0.25)}
    mark_path = dst + ".trim.json"
    if os.path.exists(dst) and os.path.exists(mark_path):
        try:
            if json.load(open(mark_path, encoding="utf-8")) == mark:
                return 0
        except ValueError:
            pass
    to = float(mark["to_s"])
    fade = float(mark["fade_s"])
    af = f"atrim=0:{to},afade=t=out:st={max(to - fade, 0.0):.3f}:d={fade:.3f},apad=pad_dur={float(mark['tail_s']):.3f}"
    tmp = dst + ".tmp.ogg"
    # -nostdin + stdin=DEVNULL (09.11, 20:30): sync_voice.sh calls this inside `while read … done < <(find -print0)`;
    # ffmpeg read that stream as its console — it ate the "/" of the next path (cp: cannot stat 'home/…') and the run
    # stopped before ru/. Test: tools/test_voice_trim_stdin.sh
    r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-af", af, "-c:a", "libvorbis", "-q:a", "7",
                        "-map_metadata", "-1", tmp], stdin=subprocess.DEVNULL)
    if r.returncode != 0 or not os.path.exists(tmp):
        print(f"  voice trim {key}: ffmpeg failed", file=sys.stderr)
        return 2
    os.replace(tmp, dst)
    json.dump(mark, open(mark_path, "w", encoding="utf-8"))
    print(f"  voice/{key} trimmed to {to} s (data/story/voice_trim.json)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
