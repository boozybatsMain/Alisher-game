#!/usr/bin/env python3
"""Процедурные силуэты гор (хребет Алатау / Тянь-Шань) для 2D-задника арен.

Пишет assets/bg/mountains_far_0..3.png — горизонтально бесшовные полосы 2048x480 RGBA:
  0 — день, дальний хребет (пыльно-сиреневый, снежные шапки в закатном свете)
  1 — день, ближний хребет (тёмная охра)
  2 — ночь, дальний хребет (сине-фиолетовый, бледный снег)
  3 — ночь, ближний хребет (тёмный индиго)
Запуск: python3 tools/make_mountains.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

W, H = 2048, 480
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "bg")


def ridge(seed, base, amp, octaves, sharp):
    """Периодический профиль высоты (доля высоты картинки сверху вниз: 0 — верх)."""
    rng = np.random.default_rng(seed)
    x = np.arange(W) / W
    h = np.zeros(W)
    a = 1.0
    for o in range(octaves):
        for _ in range(3):
            f = rng.integers(1 + 2 ** o, 2 + 2 ** (o + 1))
            ph = rng.random() * 2 * np.pi
            h += a * np.cos(2 * np.pi * f * x + ph)
        a *= 0.5
    h = (h - h.min()) / (h.max() - h.min())
    h = h ** sharp           # острые пики, широкие долины
    return base - amp * h    # y верхней кромки (0..1)


def layer(seed, base, amp, sharp, top, bottom, snow, snow_line, light_side):
    top_y = ridge(seed, base, amp, 6, sharp) * H
    yy = np.arange(H)[:, None].astype(np.float32)
    inside = yy >= top_y[None, :]
    t = np.clip((yy - top_y[None, :]) / (H - top_y[None, :] + 1e-3), 0, 1)
    top = np.array(top, np.float32)
    bottom = np.array(bottom, np.float32)
    col = top[None, None, :] * (1 - t[..., None]) + bottom[None, None, :] * t[..., None]
    # освещённый склон: по знаку наклона профиля
    slope = np.gradient(top_y)
    lit = np.clip(-slope * light_side * 0.35, -1, 1)
    lit = np.convolve(lit, np.ones(41) / 41, mode="same")
    col *= (1.0 + 0.18 * lit)[None, :, None]
    # снег: у вершин выше линии снега, рваная кромка
    if snow is not None:
        rng = np.random.default_rng(seed + 7)
        jag = np.convolve(rng.random(W), np.ones(5) / 5, mode="same") * 14
        depth = yy - top_y[None, :]
        cap = (top_y[None, :] < snow_line * H) & (depth < (snow_line * H - top_y[None, :]) * 0.55 + jag[None, :])
        sn = np.array(snow, np.float32)
        snow_col = sn[None, None, :] * (1.0 + 0.12 * lit)[None, :, None]
        col = np.where(cap[..., None], snow_col, col)
    alpha = inside.astype(np.float32)
    img = np.dstack([np.clip(col, 0, 255), alpha * 255]).astype(np.uint8)
    im = Image.fromarray(img, "RGBA")
    # лёгкое сглаживание кромки
    a = im.getchannel("A").filter(ImageFilter.GaussianBlur(0.8))
    im.putalpha(a)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    specs = [
        # seed, base, amp, sharp, top, bottom, snow, snow_line, light
        (11, 0.92, 0.80, 1.6, (176, 112, 112), (214, 140, 96), (255, 214, 176), 0.42, 1),
        (23, 0.95, 0.55, 1.3, (120, 64, 48), (168, 92, 52), None, 0, 1),
        (11, 0.92, 0.80, 1.6, (70, 62, 120), (96, 70, 130), (196, 196, 236), 0.42, -1),
        (23, 0.95, 0.55, 1.3, (34, 28, 64), (52, 40, 84), None, 0, -1),
    ]
    for i, s in enumerate(specs):
        im = layer(*s)
        p = os.path.join(OUT, "mountains_far_%d.png" % i)
        im.save(p)
        print("wrote", os.path.normpath(p))


if __name__ == "__main__":
    main()
