#!/usr/bin/env python3
"""Проба «как будет в игре» для живой воды у мельничного колеса (Docs/PLAN_WHEEL_WATER.md; Директор 16.11, 15:40:
«Проба 1 нормально, но колесо чуть корёжит всё равно + будет ли это максимально бесшовно циклично? попробуй ещё»;
15:45: «и колесо быстрее крутится почему-то»).

Колесо в ролике fal рисует сама модель — отсюда и «корёжит», и своя скорость. Здесь из ролика берётся только вода:
  кадры игры (двор M1, наше нарисованное колесо крутится с игровой скоростью, воды из кода нет —
  game/tests/probe_wheel_frame.gd, clean_NNN.jpg)  +  вода ролика по маске  →  видео.
Маска — протока и место, где вода падает с колеса (многоугольники по кадру двора), без круга колеса над линией
воды: внутри круга всегда картина игры и наше колесо. Петля воды: кусок ролика [--from, --to], его начало наплывом сводится с
продолжением хвоста (--seam секунд), так что повтор идёт без скачка; у ролика с одинаковыми первым и последним
кадром хватает короткого наплыва.

  python3 tools/wheel_water.py --clip assets/incoming/video/wheel_3/…mp4 --game /path/clean_%03d.jpg \
      --out Docs/evidence/wheel_water/voda_kak_v_igre.mp4 [--from 0 --to 5 --seam 0.5] [--mask-out mask.png]
Печатает: длину петли, разницу на стыке против обычной разницы соседних кадров (в области воды), долю кадра под
маской.

В игру (Директор 16.11, 17:28: «давай вставлять так и собирать игру» — о варианте «вода пробы 1 + струи из игры»):
  python3 tools/wheel_water.py --clip assets/incoming/video/wheel_1/…mp4 --from 1.75 --to 5.05 --seam 0.6 --front \
      --rim 45 --cut 1170,620,1470,730 --pack game/assets/rooms/M1/wheel_water_film.ogv \
      --tone-ref Docs/evidence/wheel_water/start_clean.png
  → один поток Ogg Theora: сверху цвет воды (прямоугольник `--rect`, по умолчанию — охват маски, кратно 16), под ним
    через `--gap` пикселей — её непрозрачность (серым); игра складывает их шейдером (AmbientWheel, `film`) поверх
    своей воды у колеса. Печатает прямоугольник для data/story/ambient/M1.json.
  python3 tools/wheel_water.py --check game/assets/rooms/M1/wheel_water_film.ogv --rect … [--self-check]
  → петля без скачка (стык ≤ 1,5 × обычного шага), колесо ролика не видно (в круге нашего колеса выше воды, вне
    FRONT, непрозрачность ≤ 8 из 255; в FRONT под непрозрачностью — светлая вода), код 0/1; --self-check: обрезанная
    петля и маска без выреза колеса ловятся.
"""
import argparse
import json
import os
import subprocess
import sys

import cv2
import numpy as np

W, H, FPS = 1920, 1080, 24
AMBIENT = "data/story/ambient/M1.json"


def read_clip(path, t0, t1):
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS) or FPS
    frames = []
    i = 0
    while True:
        ok, f = cap.read()
        if not ok:
            break
        t = i / fps
        if t >= t0 - 1e-6 and t < t1 - 1e-6:
            if f.shape[1] != W or f.shape[0] != H:
                f = cv2.resize(f, (W, H), interpolation=cv2.INTER_LANCZOS4)
            frames.append(f)
        i += 1
    cap.release()
    return frames, fps


def loop_frames(frames, seam_n):
    """A seamless loop out of a run of frames: the first `seam_n` frames are a dissolve from what follows the tail
    (the frames that would come after the loop's end) into the head, so frame 0 follows the last frame as in the clip."""
    n = len(frames) - seam_n
    out = []
    for i in range(n):
        if i < seam_n:
            u = (i + 1) / (seam_n + 1)
            u = u * u * (3 - 2 * u)
            out.append(cv2.addWeighted(frames[n + i], 1.0 - u, frames[i], u, 0.0))
        else:
            out.append(frames[i])
    return out


def wheel_geometry(root):
    a = json.load(open(os.path.join(root, AMBIENT), encoding="utf-8"))
    w = a["wheel_water"][0]
    return (float(w["hub"][0]), float(w["hub"][1])), float(w["radius_px"]), w["water_line"]


# Где у двора мельницы вода (экран 1920×1080, по кадру Docs/evidence/wheel_water/start_clean.png): протока под
# колесом и перед ним — от линии воды до берега, справа до каменной стенки; и место, где вода падает с колеса, —
# между ободом и дощатой стенкой лотка. При внесении в игру эти точки уйдут в data/story/ambient/M1.json.
RACE = [(1200, 655), (1500, 650), (1760, 645), (1920, 730), (1920, 872), (1800, 846), (1700, 816), (1600, 782),
        (1500, 746), (1400, 713), (1300, 702), (1215, 690)]
FALL = [(1470, 500), (1670, 500), (1670, 665), (1470, 665)]
# Где вода в ролике идёт поверх колеса и рядом с ним (16.11, по первой пробе, которую Директор назвал «намного
# реалистичнее»: «там и вода на колесе и под ним была лучше»): нижняя правая четверть обода. Вне круга колеса
# (место падения, протока) ролик берётся целиком; внутри круга — только сама вода, светлое и бесцветное (струи,
# брызги, пена); дерево колеса ролика (оно у модели гнётся и крутится по-своему) не берётся: под водой — наше колесо.
FRONT = [(1490, 430), (1690, 430), (1690, 700), (1490, 700)]


def waterlike(frame, lo=85.0, span=55.0, s_hi=125.0, s_span=55.0):
    """0…1 per pixel: how much a clip pixel is water (light, colourless) rather than wood, boards or shadow."""
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV).astype(np.float32)
    lum = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY).astype(np.float32)
    a = np.clip((lum - lo) / span, 0.0, 1.0) * np.clip((s_hi - hsv[..., 1]) / s_span, 0.0, 1.0)
    return cv2.GaussianBlur(a, (0, 0), 1.2)


def poly_soft(poly, feather_px):
    m = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m, [np.array(poly, np.int32)], 255)
    k = int(feather_px) * 2 + 1
    m = cv2.erode(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    return cv2.GaussianBlur(m.astype(np.float32) / 255.0, (0, 0), feather_px * 0.6)


def water_mask(hub, radius, water_line, rim_px, feather_px, cut=None, fall=True):
    """Where the clip's water is taken: the race and the place of the fall, feathered; nothing inside the wheel's
    circle (radius + rim_px) above the water line — there the game's own picture and wheel."""
    m = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m, [np.array(RACE, np.int32)], 255)
    if fall:
        cv2.fillPoly(m, [np.array(FALL, np.int32)], 255)
    # feather inwards: the mask never reaches past the polygons (the banks stay the game's own picture)
    k = int(feather_px) * 2 + 1
    m = cv2.erode(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k)))
    full = cv2.GaussianBlur(m.astype(np.float32) / 255.0, (0, 0), feather_px * 0.6)
    full[:, W - 2:] = full[:, W - 3:W - 2]          # the frame's right edge is water: no fade there
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    (xa, ya), (xb, yb) = water_line
    line_y = ya + (xx - xa) * (yb - ya) / (xb - xa)
    d = np.sqrt((xx - hub[0]) ** 2 + (yy - hub[1]) ** 2)
    inside = np.clip((radius + rim_px - d) / 6.0, 0.0, 1.0)          # 1 inside the circle, soft 6 px edge
    above = np.clip((line_y - yy) / 6.0, 0.0, 1.0)                    # 1 above the water line
    full *= 1.0 - inside * above
    if cut:
        cx0, cy0, cx1, cy1 = cut
        c = np.ones((H, W), np.float32)
        c[cy0:cy1, cx0:cx1] = 0
        full *= cv2.GaussianBlur(c, (0, 0), 16)
    return np.clip(full, 0.0, 1.0)


def tone_match(loop, game0, mask, hub, radius):
    """Per-channel gain and offset that bring the clip to the game's picture where nothing moves — a band of banks
    and boards around the water (outside the mask, outside the wheel): a clip drifts a little in tone from its start
    picture, and it is at the water's edge that the two meet. Kept within ±10 %, ±10 levels; otherwise left as is."""
    near = cv2.dilate((mask > 0.01).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (141, 141))) > 0
    yy, xx = np.mgrid[0:H, 0:W]
    wheel = (xx - hub[0]) ** 2 + (yy - hub[1]) ** 2 < (radius + 24) ** 2
    still = near & (mask < 0.02) & ~wheel
    clip_mean = np.mean(np.stack(loop[::4]).astype(np.float64), axis=0)
    g = game0.astype(np.float64)
    gains = []
    for c in range(3):
        x = clip_mean[..., c][still]
        y = g[..., c][still]
        sel = np.abs(x - y) < 30                     # what differs outright (a moving shadow, spray) is left out
        if int(sel.sum()) < 2000:
            gains.append((1.0, 0.0))
            continue
        a, b = np.polyfit(x[sel], y[sel], 1)
        if not (0.9 <= a <= 1.1 and -10.0 <= b <= 10.0):
            a, b = 1.0, float(np.clip(np.mean(y[sel] - x[sel]), -10.0, 10.0))
        gains.append((float(a), float(b)))
    return gains


# --- Пакет для игры: цвет над непрозрачностью в одном потоке Theora ------------------------------------------------

GAP = 16
SEAM_K = 1.5          # стык петли — не больше полутора обычных шагов между кадрами
WHEEL_ALPHA_MAX = 8   # из 255: столько колеса ролика можно «видеть» в круге нашего колеса (99,9 % точек; шум сжатия)
WHEEL_ALPHA_PEAK = 24 # из 255: и ни одной точки ярче (звон сжатия у края маски)
FRONT_LUMA_MIN = 110  # средняя яркость того, что взято из ролика внутри круга (вода светлая, дерево тёмное)


def auto_rect(mask, front):
    m = np.maximum(mask, front if front is not None else 0.0) > 0.004
    ys, xs = np.nonzero(m)
    x0 = int(xs.min()) // 16 * 16
    y0 = int(ys.min()) // 16 * 16
    x1 = min(W, -(-int(xs.max() + 1) // 16) * 16)
    y1 = min(H, -(-int(ys.max() + 1) // 16) * 16)
    return [x0, y0, x1 - x0, y1 - y0]


def theora(path, w, h, n, quality=10):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    return subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", "%dx%d" % (w, h),
                             "-r", str(FPS), "-i", "-", "-an", "-c:v", "libtheora", "-q:v", str(quality), "-g", str(n + 8), path],
                            stdin=subprocess.PIPE)


def pack_frame(color, alpha, rect, gap=GAP):
    x, y, w, h = rect
    out = np.zeros((h * 2 + gap, w, 3), np.uint8)
    out[:h] = color[y:y + h, x:x + w]
    a = np.clip(alpha[y:y + h, x:x + w] * 255.0 + 0.5, 0, 255).astype(np.uint8)
    out[h + gap:] = a[..., None]
    return out


def read_pack(path, rect, gap=GAP):
    """The packed stream back: [(colour BGR h×w, alpha 0…1 h×w)] per frame."""
    x, y, w, h = rect
    cap = cv2.VideoCapture(path)
    out = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        out.append((f[:h], f[h + gap:h * 2 + gap, :, 1].astype(np.float32) / 255.0))
    cap.release()
    return out


def wheel_zone(rect, hub, radius, water_line):
    """Inside the pack's rectangle: True where our wheel stands above the water and no clip but water may show."""
    x, y, w, h = rect
    yy, xx = np.mgrid[y:y + h, x:x + w].astype(np.float32)
    (xa, ya), (xb, yb) = water_line
    line_y = ya + (xx - xa) * (yb - ya) / (xb - xa)
    inside = (xx - hub[0]) ** 2 + (yy - hub[1]) ** 2 < (radius - 4) ** 2
    above = yy < line_y - 6
    fr = np.zeros((H, W), np.uint8)
    cv2.fillPoly(fr, [np.array(FRONT, np.int32)], 1)
    front = fr[y:y + h, x:x + w] > 0
    return inside & above & ~front, inside & above & front


def check_pack(frames, rect, hub, radius, water_line):
    """[(ok, message)] — the loop goes round without a jump; the clip's wheel never shows over ours."""
    res = []
    alpha_any = np.max(np.stack([a for _, a in frames]), axis=0) > 0.5
    lum = [cv2.cvtColor(c, cv2.COLOR_BGR2GRAY).astype(np.float32) for c, _ in frames]
    steps = [float(np.abs(lum[k + 1] - lum[k])[alpha_any].mean()) for k in range(len(lum) - 1)]
    step = float(np.median(steps))
    seam = float(np.abs(lum[0] - lum[-1])[alpha_any].mean())
    res.append((seam <= SEAM_K * step, "петля %d кадров: стык (последний → первый) %.2f из 255, обычный шаг %.2f (предел — %.1f шага)" % (len(frames), seam, step, SEAM_K)))
    off, front = wheel_zone(rect, hub, radius, water_line)
    offa = np.concatenate([a[off] for _, a in frames]) * 255.0
    p999, peak = float(np.percentile(offa, 99.9)), float(offa.max())
    res.append((p999 <= WHEEL_ALPHA_MAX and peak <= WHEEL_ALPHA_PEAK, "колесо ролика над нашим не видно: непрозрачность в круге колеса вне места падения воды — %.1f из 255 у 99,9 %% точек, наибольшая %.1f (пределы %d и %d)" % (p999, peak, WHEEL_ALPHA_MAX, WHEEL_ALPHA_PEAK)))
    num = sum(float((l * a)[front & (a > 0.15)].sum()) for l, (_, a) in zip(lum, frames))
    den = sum(float(a[front & (a > 0.15)].sum()) for _, a in frames)
    share = den / max(1.0, float(front.sum()) * len(frames))
    took = num / den if share >= 0.002 else 255.0      # under 0.2 % of the zone taken — nothing of the clip shows there
    res.append((took >= FRONT_LUMA_MIN, "поверх нашего колеса из ролика берётся только вода: средняя яркость взятого %s при доле %.2f %% зоны (вода светлая; предел %d)" % ("%.0f" % took if share >= 0.002 else "— (почти ничего)", 100.0 * share, FRONT_LUMA_MIN)))
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip", default="")
    ap.add_argument("--game", default="", help="кадры игры, шаблон printf: /path/clean_%%03d.jpg")
    ap.add_argument("--out", default="")
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=1e9)
    ap.add_argument("--seam", type=float, default=0.5)
    ap.add_argument("--rim", type=float, default=10.0, help="запас вокруг круга колеса, px")
    ap.add_argument("--feather", type=float, default=8.0, help="мягкий край маски воды, px")
    ap.add_argument("--cut", default="", help="x0,y0,x1,y1 — область, где ролик не брать (брак дубля)")
    ap.add_argument("--front", action="store_true", help="у колеса брать из ролика только воду (FRONT, waterlike)")
    ap.add_argument("--pack", default="", help="в игру: поток Theora — цвет над непрозрачностью")
    ap.add_argument("--rect", default="", help="x,y,w,h прямоугольника пакета (по умолчанию — охват маски)")
    ap.add_argument("--tone-ref", default="", help="кадр игры для подгонки тона (при --pack)")
    ap.add_argument("--check", default="", help="проверить готовый пакет .ogv")
    ap.add_argument("--self-check", action="store_true")
    ap.add_argument("--mask-out", default="")
    ap.add_argument("--crf", type=int, default=17)
    a = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if a.check:
        hub, radius, wl = wheel_geometry(root)
        rect = [int(v) for v in a.rect.split(",")]
        frames = read_pack(a.check, rect)
        if not frames:
            print("FAIL  %s: не читается" % a.check)
            return 1
        ok_all = True
        for ok, msg in check_pack(frames, rect, hub, radius, wl):
            print(("PASS  " if ok else "FAIL  ") + "%s: %s" % (os.path.basename(a.check), msg))
            ok_all = ok_all and ok
        if a.self_check:
            cut = frames[:len(frames) - len(frames) // 3]          # a loop cut short: its end is not its beginning
            bad = check_pack(cut, rect, hub, radius, wl)[0]
            print(("PASS  " if not bad[0] else "FAIL  ") + "self-check: петля, обрезанная на треть, ловится — " + bad[1])
            ok_all = ok_all and not bad[0]
            off, _ = wheel_zone(rect, hub, radius, wl)
            leak = [(c, np.where(off, 1.0, al)) for c, al in frames[:6]]   # the clip's wheel let through
            bad2 = check_pack(leak, rect, hub, radius, wl)[1]
            print(("PASS  " if not bad2[0] else "FAIL  ") + "self-check: маска без выреза колеса ловится — " + bad2[1])
            ok_all = ok_all and not bad2[0]
            _, fr = wheel_zone(rect, hub, radius, wl)
            wood = [(np.full_like(c, (40, 60, 90)), np.where(fr, 1.0, al)) for c, al in frames[:6]]   # brown wood taken
            bad3 = check_pack(wood, rect, hub, radius, wl)[2]
            print(("PASS  " if not bad3[0] else "FAIL  ") + "self-check: дерево ролика поверх колеса ловится — " + bad3[1])
            ok_all = ok_all and not bad3[0]
        return 0 if ok_all else 1
    if not a.clip or (not a.pack and (not a.game or not a.out)):
        ap.error("нужны --clip и --game с --out, или --pack, или --check")
    frames, fps = read_clip(a.clip, a.t0, a.t1)
    if len(frames) < 24:
        print("слишком мало кадров ролика: %d" % len(frames), file=sys.stderr)
        return 1
    seam_n = max(1, int(round(a.seam * fps)))
    loop = loop_frames(frames, seam_n)
    hub, radius, wl = wheel_geometry(root)
    cut = [int(v) for v in a.cut.split(",")] if a.cut else None
    mask = water_mask(hub, radius, wl, a.rim, a.feather, cut)
    front = poly_soft(FRONT, a.feather) if a.front else None
    if a.mask_out:
        cv2.imwrite(a.mask_out, (mask * 255).astype(np.uint8))
    if a.pack:
        front = poly_soft(FRONT, a.feather) if a.front else None
        rect = [int(v) for v in a.rect.split(",")] if a.rect else auto_rect(mask, front)
        ref = cv2.imread(a.tone_ref) if a.tone_ref else None
        if ref is None:
            ap.error("--pack: нужен --tone-ref (кадр игры)")
        gains = tone_match(loop, ref, mask, hub, radius)
        lut = [np.clip(np.arange(256, dtype=np.float32) * g[0] + g[1], 0, 255).astype(np.uint8) for g in gains]
        x, y, w, h = rect
        p = theora(a.pack, w, h * 2 + GAP, len(loop))
        for fr in loop:
            col = np.stack([lut[c][fr[..., c]] for c in range(3)], axis=-1)
            al = np.maximum(mask, front * waterlike(fr)) if front is not None else mask
            p.stdin.write(pack_frame(col, al, rect).tobytes())
        p.stdin.close()
        p.wait()
        print("пакет: %s — %d кадров (%.2f с), прямоугольник %s, тон B,G,R: %s" % (a.pack, len(loop), len(loop) / fps, ",".join(str(v) for v in rect),
              ", ".join("%.3f %+.1f" % g for g in gains)))
        return 0 if p.returncode == 0 else 1
    game = []
    i = 0
    while os.path.exists(a.game % i):
        game.append(a.game % i)
        i += 1
    if not game:
        print("нет кадров игры: %s" % a.game, file=sys.stderr)
        return 1
    g0 = cv2.imread(game[0])
    gains = tone_match(loop, g0, mask, hub, radius)
    m3 = mask[..., None]
    # the seam against an ordinary step between frames, where the water is
    sel = mask > 0.5
    step = float(np.mean([np.abs(loop[k + 1].astype(np.int16) - loop[k].astype(np.int16))[sel].mean() for k in range(seam_n, len(loop) - 1, 3)]))
    seam = float(np.abs(loop[0].astype(np.int16) - loop[-1].astype(np.int16))[sel].mean())
    print("петля: %d кадров, %.2f с; наплыв %d кадров" % (len(loop), len(loop) / fps, seam_n))
    print("стык (последний → первый кадр петли) в области воды: %.2f из 255; обычный шаг между кадрами: %.2f" % (seam, step))
    print("под маской воды: %.1f %% кадра; тон ролика к игре (усиление, сдвиг) B,G,R: %s" % (100.0 * float(mask.mean()), ", ".join("%.3f %+.1f" % g for g in gains)))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
           "-c:v", "libx264", "-crf", str(a.crf), "-pix_fmt", "yuv420p", "-movflags", "+faststart", a.out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    lut = [np.clip(np.arange(256, dtype=np.float32) * g[0] + g[1], 0, 255) for g in gains]
    for k, path in enumerate(game):
        g = cv2.imread(path).astype(np.float32)
        w = loop[k % len(loop)]
        wt = np.stack([lut[c][w[..., c]] for c in range(3)], axis=-1)
        mk = m3
        if front is not None:
            mk = np.maximum(mask, front * waterlike(w))[..., None]
        out = g * (1.0 - mk) + wt * mk
        out = np.clip(out, 0, 255).astype(np.uint8)
        p.stdin.write(out.tobytes())
    p.stdin.close()
    p.wait()
    print("видео: %s, %d кадров, %.1f с" % (a.out, len(game), len(game) / FPS))
    return 0 if p.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
