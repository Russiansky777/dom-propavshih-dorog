"""Лицо и волосы: исходная текстура + деталь и румянец из Retexture (UV совпадают, enable_original_uv)."""
import sys, numpy as np
from PIL import Image, ImageFilter
orig_p, retex_p, mask_p, out_p = sys.argv[1:5]
A = np.asarray(Image.open(orig_p).convert('RGB')).astype(np.float32) / 255
B = np.asarray(Image.open(retex_p).convert('RGB')).astype(np.float32) / 255
M = np.asarray(Image.open(mask_p)).astype(np.float32) / 255
from scipy.ndimage import gaussian_filter
def blur(x, r):
    return gaussian_filter(x, (r, r, 0) if x.ndim == 3 else r)
Ab = blur(A, 3)
skin = ((Ab[..., 0] > 0.55) & (Ab[..., 0] - Ab[..., 2] > 0.10) & (Ab.mean(-1) > 0.45)).astype(np.float32)
skin = np.clip(blur(skin, 10) * 2.5, 0, 1)   # глаза и брови внутри кожи — тоже «лицо»
hair = (1 - skin)
# волосы: цвет исходный (каштан), темнее и теплее; мелкая деталь прядей — из Retexture (яркость к своему размытию)
lB = B.mean(-1) + 1e-3; detail = np.clip(lB / (blur(lB, 4) + 1e-3), 0.5, 1.8) ** 1.1
lA = A.mean(-1) + 1e-3; detA = np.clip(lA / (blur(lA, 4) + 1e-3), 0.5, 1.8)
H = blur(A, 4) * 0.88 * (detail * 0.6 + detA * 0.4)[..., None]
H = H * np.array([1.04, 0.97, 0.90])          # тёплый каштан
H = H + 0.06 * np.clip(detail - 1, 0, None)[..., None] * np.array([0.9, 0.45, 0.2])  # рыжеватые блики на светлых прядях
# лицо: Retexture, приведённый к тону исходной кожи (среднее/разброс по коже), пополам с исходной; чуть плотнее и теплее
w = (skin * M) > 0.5
Bm = (B - B[w].mean(0)) / (B[w].std(0) + 1e-3) * A[w].std(0) + A[w].mean(0)
# из Retexture — только крупное (румянец, тени у носа, губ, глаз; r=6), мелкая деталь — своя (без следов шва Retexture на лбу)
F = 0.4 * blur(A, 6) + 0.6 * blur(Bm, 6) + (A - blur(A, 6))
F = F * np.array([0.90, 0.83, 0.79])           # не высветленная: ниже яркость, теплее
g = F.mean(-1, keepdims=True); F = g + (F - g) * 1.12
out = A * (1 - M[..., None]) + M[..., None] * (skin[..., None] * F + hair[..., None] * H)
Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out_p)
print('skin px', int(w.sum()))
