#!/usr/bin/env python3
"""Собирает preview/fx_demo.html — демо приёмов «живой» анимации на наших спрайтах.

Всё (спрайты, свечение, слои степи) встраивается в один HTML как base64.
"""
import base64
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import art_pipeline as P  # noqa: E402

ROOT = P.ROOT
row = lambda r, n=4: [(r, c) for c in range(n)]
R8 = [(0, c) for c in range(4)] + [(1, c) for c in range(4)]


def b64(img, fmt="PNG", quality=88):
    buf = io.BytesIO()
    if fmt == "JPEG":
        img.convert("RGB").save(buf, "JPEG", quality=quality)
    else:
        img.save(buf, "PNG", optimize=True)
    return f"data:image/{fmt.lower()};base64," + base64.b64encode(buf.getvalue()).decode()


def glow_strip(strip):
    """Маска бирюзовых орнаментов → размытое свечение (для аддитивного слоя)."""
    a = np.asarray(strip.convert("RGBA")).astype(np.float32) / 255
    rgb, al = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    g, b, r = rgb[..., 1], rgb[..., 2], rgb[..., 0]
    teal = (g > 0.5) & (b > 0.45) & (r < 0.55) & (sat > 0.35) & (al > 0.5)
    m = Image.fromarray((teal * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    m = m.point(lambda v: min(255, int(v * 2.2)))
    out = Image.new("RGBA", strip.size, (90, 255, 225, 0))
    out.putalpha(m)
    return out


def hair_anchors(strip, n, fw, fh, ax, ay, whole=False):
    """Точка на затылке в каждом кадре — к ней крепится процедурная лента."""
    """Ищем лицо: кожа, над которой чёрные волосы. Лента крепится чуть позади лица."""
    arr = np.asarray(strip.convert("RGBA")).astype(np.int32)
    res, last = [], (-20.0, -190.0)
    for i in range(n):
        f = arr[:, i * fw:(i + 1) * fw]
        r, g, b, al = f[..., 0], f[..., 1], f[..., 2], f[..., 3]
        lum = (r * 3 + g * 6 + b) / 10
        ys, _ = np.nonzero(al > 200)
        if len(ys) == 0:
            res.append(last)
            continue
        top, bot = ys.min(), ys.max()
        skin = (al > 200) & (r > 150) & (g > 95) & (b > 60) & (r > g + 15) & (g > b) & (r - b > 45)
        if not whole:
            skin[int(top + (bot - top) * 0.5):] = False
        hair = (al > 200) & (lum < 40)
        lab, k = ndimage.label(skin)
        best, score = None, 0
        for j, sl in enumerate(ndimage.find_objects(lab)):
            m = lab[sl] == j + 1
            area = int(m.sum())
            if area < 60:
                continue
            y0, x0, x1 = sl[0].start, sl[1].start, sl[1].stop
            above = hair[max(0, y0 - 30):y0 + 6, max(0, x0 - 20):x1 + 5].sum()
            sc = area * 0.2 + above
            if sc > score:
                best, score = (x0, y0, x1, sl[0].stop), sc
        if best is None:
            res.append(last)
            continue
        x0, y0, x1, y1 = best
        px, py = x0 - 14, y0 + (y1 - y0) * 0.12
        last = (round(float(px - ax), 1), round(float(py - ay), 1))
        res.append(last)
    return res


def white_strip(strip):
    a = strip.split()[3]
    w = Image.new("RGBA", strip.size, (255, 255, 255, 0))
    w.putalpha(a)
    return w


def main():
    out_html = os.path.join(ROOT, "preview", "fx_demo.html")
    tpl = open(os.path.join(os.path.dirname(__file__), "preview_demo.html"), encoding="utf-8").read()

    # ---------------- герой
    S = {
        "A": ("hero/hero_A.png", 4, 3),
        "B": ("hero/hero_B.png", 4, 3, ("A", [2], [0])),
        "C": ("hero/hero_C.png", 4, 3, ("A", [2], [1])),
        "K8": ("test/hero_attack8.png", 4, 2, ("A", [0], [(0, 0), (1, 3)])),
    }
    HERO = [
        ("idle", "A", row(0), 6, True, "body"),
        ("run", "A", row(1), 10, True, "body"),
        ("attack1", "A", row(2), 14, False, "body"),
        ("attack1_8", "K8", R8, 20, False, "body"),
        ("attack2", "B", row(0), 14, False, "body"),
        ("attack3", "B", row(1), 12, False, "body"),
        ("dash", "B", row(2), 14, False, "body"),
        ("roll", "C", row(0), 12, False, "bbox"),
        ("block", "C", [(1, 0), (1, 1), (1, 2)], 6, False, "body"),
        ("parry", "C", [(1, 3)], 6, False, "body"),
        ("hurt", "C", [(2, 0), (2, 1)], 8, False, "body"),
    ]
    hm = P.build_character("demo_hero", S, 0.78, HERO)
    hero = {"fw": hm["frame_w"], "fh": hm["frame_h"], "ax": hm["anchor_x"], "ay": hm["anchor_y"], "anims": {}}
    for name, info in hm["anims"].items():
        strip = Image.open(os.path.join(ROOT, "assets", "sprites", "demo_hero", f"{name}.png"))
        hero["anims"][name] = {
            "n": info["frames"], "fps": info["fps"],
            "src": b64(strip), "glow": b64(glow_strip(strip)),
            "hair": hair_anchors(strip, info["frames"], hm["frame_w"], hm["frame_h"], hm["anchor_x"],
                                 hm["anchor_y"], whole=(name == "roll")),
        }

    # ---------------- балбал
    BAL = [
        ("walk", "K", row(0), 7, True, "body"),
        ("attack", "K", row(1), 8, False, "body"),
        ("idle", "K", [(2, 0)], 4, True, "body"),
        ("hurt", "K", [(2, 1)], 4, False, "body"),
        ("stun", "K", [(2, 2)], 4, False, "body"),
        ("crumble", "K", [(2, 3)], 4, False, "body"),
    ]
    bm = P.build_character("demo_balbal", {"K": ("enemies/balbal.png", 4, 3)}, 0.78, BAL)
    bal = {"fw": bm["frame_w"], "fh": bm["frame_h"], "ax": bm["anchor_x"], "ay": bm["anchor_y"], "anims": {}}
    for name, info in bm["anims"].items():
        strip = Image.open(os.path.join(ROOT, "assets", "sprites", "demo_balbal", f"{name}.png"))
        bal["anims"][name] = {"n": info["frames"], "fps": info["fps"], "src": b64(strip), "white": b64(white_strip(strip))}

    # ---------------- слои степи
    src = lambda p: Image.open(os.path.join(P.SRC, p))
    sky = src("bg/sky.png").convert("RGB").crop((0, 60, 1536, 924)).resize((1400, 788), Image.LANCZOS)

    g = P.clean_alpha(P.key_magenta(src("bg/ground.png")))
    g = g.crop((0, 580, 1536, 1024))
    ga = np.asarray(g).astype(np.float32)
    blend = 220  # бесшовность: переход конца ленты в её начало
    w = ga.shape[1] - blend
    tile = ga[:, :w].copy()
    k = np.linspace(0, 1, blend)[None, :, None]
    tile[:, :blend] = ga[:, w:] * (1 - k) + ga[:, :blend] * k
    ground = Image.fromarray(tile.clip(0, 255).astype(np.uint8), "RGBA")
    ground = ground.resize((int(ground.width * 0.62), int(ground.height * 0.62)), Image.LANCZOS)

    def objs(path, scale):
        rgba = P.clean_alpha(P.key_magenta(src(path)))
        res = []
        for o in P.extract_objects(rgba, min_area=4000):
            im = o["img"]
            res.append(b64(im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)))
        return res

    env = {
        "sky": b64(sky, "JPEG"), "ground": b64(ground), "ground_h": ground.height, "ground_w": ground.width,
        "ruins": objs("bg/ruins.png", 0.5), "stones": objs("bg/stones.png", 0.42),
        "grass": objs("bg/grass.png", 0.3),
    }
    data = {"hero": hero, "bal": bal, "env": env}
    html = tpl.replace("__DATA__", json.dumps(data))
    os.makedirs(os.path.dirname(out_html), exist_ok=True)
    with open(out_html, "w", encoding="utf-8") as f:
        f.write(html)
    print(out_html, f"{os.path.getsize(out_html) / 1e6:.1f} MB", "hero", hero["fw"], hero["fh"], "bal", bal["fw"], bal["fh"])
    print("hair run:", hero["anims"]["run"]["hair"])
    print("hair idle:", hero["anims"]["idle"]["hair"])


if __name__ == "__main__":
    main()
