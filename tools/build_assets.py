#!/usr/bin/env python3
"""Сборка всех игровых ассетов из art_src/ (листы Codex) в assets/ для Godot.

Запуск: python3 tools/build_assets.py [персонаж ...]
Без аргументов собирает всё. Отсутствующие листы пропускаются.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "art"))
import art_pipeline as P  # noqa: E402

ROOT, SRC, ASSETS = P.ROOT, P.SRC, P.ASSETS
row = lambda r, n=4: [(r, c) for c in range(n)]
R8 = [(0, c) for c in range(4)] + [(1, c) for c in range(4)]


def exists(rel):
    return os.path.exists(os.path.join(SRC, rel))


def measure(rel, cols, rows, cells):
    """Средний рост персонажа (px) в выбранных ячейках листа — для подбора масштаба."""
    rgba = P.clean_alpha(P.key_magenta(Image.open(os.path.join(SRC, rel))))
    fr = P.grid_frames(rgba, cols, rows)
    hs = [fr[c]["main_bottom"] - fr[c]["main_top"] for c in cells if c in fr]
    return float(np.median(hs))


# ======================================================================= персонажи
# (имя анимации, лист, ячейки, fps, loop, опора, длительности кадров)
# Длительности — «удержание ключевых поз»: замах дольше, удар короче.
CHARACTERS = {
    "batyr": dict(
        height=235, ref=("hero/hero_A.png", 4, 3, row(0)),
        sheets={"A": ("hero/hero_A.png", 4, 3), "B": ("hero/hero_B.png", 4, 3, ("A", [2], [0])),
                "C": ("hero/hero_C.png", 4, 3, ("A", [2], [1])),
                "K8": ("test/hero_attack8.png", 4, 2, ("A", [0], [(0, 0), (1, 3)]))},
        anims=[
            ("idle", "A", row(0), 6, True, "body"),
            ("run", "A", row(1), 19, True, "body"),
            ("attack1", "K8", R8, 26, False, "body", [1.2, 1.0, 2.0, 0.6, 0.5, 2.4, 1.1, 1.3]),
            ("attack2", "B", row(0), 18.2, False, "body", [1.6, 2.0, 1.0, 1.4]),
            ("attack3", "B", row(1), 15.6, False, "body", [2.4, 0.6, 2.6, 2.6]),
            ("dash", "B", row(2), 18.2, False, "body", [1.3, 1.6, 1.8, 1.3]),
            ("roll", "C", row(0), 12, False, "bbox", [0.8, 1, 1, 1.4]),
            ("block", "C", [(1, 0), (1, 1), (1, 2)], 6, False, "body"),
            ("parry", "C", [(1, 3)], 6, False, "body"),
            ("hurt", "C", [(2, 0), (2, 1)], 8, False, "body", [1.6, 1.6]),
            ("death", "C", [(2, 2), (2, 3)], 3, False, "bbox", [1, 3]),
        ],
        glow=True, hair=True),
    "balbal": dict(
        height=215, ref=("enemies/balbal.png", 4, 3, [(2, 0)]),
        sheets={"K": ("enemies/balbal.png", 4, 3)},
        anims=[
            ("walk", "K", row(0), 8.75, True, "body"),
            ("attack", "K", row(1), 10, False, "body", [2.0, 2.4, 0.6, 2.2]),
            ("idle", "K", [(2, 0)], 4, True, "body"),
            ("hurt", "K", [(2, 1)], 4, False, "body"),
            ("stun", "K", [(2, 2)], 4, True, "body"),
            ("crumble", "K", [(2, 3)], 4, False, "body"),
        ],
        crumble=True),
    "spirit": dict(
        height=190, ref=("enemies/spirit.png", 4, 3, row(0)),
        sheets={"K": ("enemies/spirit.png", 4, 3)},
        anims=[
            ("float", "K", row(0), 8, True, "body"),
            ("attack", "K", row(1), 12, False, "body", [1.8, 1.6, 0.8, 1.0]),
            ("hurt", "K", [(2, 0)], 4, False, "body"),
            ("stun", "K", [(2, 1)], 4, True, "body"),
            ("death", "K", [(2, 2), (2, 3)], 5, False, "body"),
        ]),
    "wolf": dict(
        height=150, ref=("enemies/wolf.png", 4, 3, [(2, 0)]),
        sheets={"K": ("enemies/wolf.png", 4, 3)},
        anims=[
            ("run", "K", row(0), 14, True, "bbox"),
            ("attack", "K", row(1), 12, False, "bbox", [2.0, 1.0, 0.7, 1.3]),
            ("idle", "K", [(2, 0)], 4, True, "bbox"),
            ("hurt", "K", [(2, 1)], 4, False, "bbox"),
            ("stun", "K", [(2, 2)], 4, True, "bbox"),
            ("death", "K", [(2, 3)], 4, False, "bbox"),
        ]),
    "archer": dict(
        height=225, ref=("enemies/archer.png", 4, 3, [(2, 0)]),
        sheets={"K": ("enemies/archer.png", 4, 3)},
        anims=[
            ("walk", "K", row(0), 8, True, "body"),
            ("attack", "K", row(1), 8, False, "body", [1.5, 2.6, 0.7, 1.5]),
            ("idle", "K", [(2, 0)], 4, True, "body"),
            ("hurt", "K", [(2, 1)], 4, False, "body"),
            ("stun", "K", [(2, 2)], 4, True, "body"),
            ("death", "K", [(2, 3)], 4, False, "body"),
        ]),
    "shaman": dict(
        height=220, ref=("enemies/shaman.png", 4, 3, [(2, 0)]),
        sheets={"K": ("enemies/shaman.png", 4, 3)},
        anims=[
            ("walk", "K", row(0), 6, True, "body"),
            ("attack", "K", row(1), 7, False, "body", [1.6, 2.2, 2.0, 1.2]),
            ("idle", "K", [(2, 0)], 4, True, "body"),
            ("hurt", "K", [(2, 1)], 4, False, "body"),
            ("teleport", "K", [(2, 2)], 4, False, "body"),
            ("death", "K", [(2, 3)], 4, False, "body"),
        ]),
    "zhest": dict(
        height=275, ref=("enemies/zhest_A.png", 4, 3, row(0)),
        sheets={"A": ("enemies/zhest_A.png", 4, 3), "B": ("enemies/zhest_B.png", 4, 3, ("A", [0], [2]))},
        anims=[
            ("idle", "A", row(0), 7, True, "body"),
            ("walk", "A", row(1), 10, True, "body"),
            ("attack", "A", row(2), 12, False, "body", [2.6, 0.7, 0.9, 1.6]),
            ("leap", "B", row(0), 10, False, "body", [2.2, 1.0, 1.0, 1.8]),
            ("summon", "B", row(1), 6, False, "body", [1.2, 1.2, 1.6, 1.0]),
            ("hurt", "B", [(2, 0)], 4, False, "body"),
            ("stun", "B", [(2, 1)], 4, True, "body"),
            ("death", "B", [(2, 2), (2, 3)], 3, False, "body", [1.5, 2]),
        ]),
    "shoyyn": dict(
        height=430, ref=("enemies/boss2_A.png", 4, 3, row(0)),
        sheets={"A": ("enemies/boss2_A.png", 4, 3), "B": ("enemies/boss2_B.png", 4, 3, ("A", [0], [2]))},
        anims=[
            ("idle", "A", row(0), 5, True, "body"),
            ("walk", "A", row(1), 6, True, "body"),
            ("smash", "A", row(2), 8, False, "body", [2.2, 2.2, 0.6, 2.6]),
            ("sweep", "B", row(0), 9, False, "body", [2.4, 0.6, 1.2, 1.8]),
            ("stomp", "B", row(1), 8, False, "body", [2.2, 1.6, 1.0, 2.4]),
            ("roar", "B", [(2, 0)], 2, False, "body"),
            ("hurt", "B", [(2, 1)], 4, False, "body"),
            ("stun", "B", [(2, 2)], 4, True, "body"),
            ("death", "B", [(2, 2), (2, 3)], 2, False, "bbox", [1, 3]),
        ]),
}


def glow_strip(strip):
    """Маска бирюзовых орнаментов → мягкое свечение (аддитивный слой поверх спрайта)."""
    a = np.asarray(strip.convert("RGBA")).astype(np.float32) / 255
    rgb, al = a[..., :3], a[..., 3]
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1e-3)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    teal = (g > 0.5) & (b > 0.45) & (r < 0.55) & (sat > 0.35) & (al > 0.5)
    m = Image.fromarray((teal * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(5))
    m = m.point(lambda v: min(255, int(v * 2.2)))
    out = Image.new("RGBA", strip.size, (90, 255, 225, 0))
    out.putalpha(m)
    return out


def hair_anchors(strip, n, fw, ax, ay, whole=False):
    """Точка на затылке в каждом кадре: лицо (кожа) с чёрными волосами над ним."""
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
            sc = area * 0.2 + hair[max(0, y0 - 30):y0 + 6, max(0, x0 - 20):x1 + 5].sum()
            if sc > score:
                best, score = (x0, y0, x1, sl[0].stop), sc
        if best is not None:
            x0, y0, x1, y1 = best
            last = (round(float(x0 - 14 - ax), 1), round(float(y0 + (y1 - y0) * 0.12 - ay), 1))
        res.append(last)
    return res


def build_character(name):
    cfg = CHARACTERS[name]
    for spec in cfg["sheets"].values():
        if not exists(spec[0]):
            print(f"  {name}: нет листа {spec[0]} — пропуск")
            return
    rel, cols, rows, cells = cfg["ref"]
    scale = cfg["height"] / measure(rel, cols, rows, cells)
    meta = P.build_character(name, cfg["sheets"], scale, cfg["anims"])
    out_dir = os.path.join(ASSETS, "sprites", name)
    fw, fh = meta["frame_w"], meta["frame_h"]
    if cfg.get("crumble"):
        from enemies import crumble  # noqa
        strip = Image.open(os.path.join(out_dir, "crumble.png"))
        frames = crumble(strip.crop((0, 0, fw, fh)), seed=11, frames=10, ground=int(meta["anchor_y"]))
        P.add_strip(name, meta, "death", frames, 12, False)
    if cfg.get("glow"):
        for anim in meta["anims"]:
            strip = Image.open(os.path.join(out_dir, f"{anim}.png"))
            glow_strip(strip).save(os.path.join(out_dir, f"glow_{anim}.png"), optimize=True)
        P.write_spriteframes(os.path.join(out_dir, f"{name}_glow_frames.tres"), f"res://assets/sprites/{name}", meta, prefix="glow_")
    if cfg.get("hair"):
        lines = ["extends RefCounted", "## Сгенерировано tools/build_assets.py: точка крепления ленты (затылок) в каждом кадре,",
                 "## относительно опорной точки спрайта (ноги).", "", "const HAIR := {"]
        for anim, info in meta["anims"].items():
            strip = Image.open(os.path.join(out_dir, f"{anim}.png"))
            pts = hair_anchors(strip, info["frames"], fw, meta["anchor_x"], meta["anchor_y"], whole=(anim == "roll"))
            lines.append(f'\t"{anim}": [' + ", ".join(f"Vector2({x}, {y})" for x, y in pts) + "],")
        lines.append("}")
        path = os.path.join(ROOT, "scripts", "data", "hero_anchors.gd")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
    print(f"  {name}: кадр {fw}x{fh}, масштаб {scale:.3f}, анимаций {len(meta['anims'])}")


# ======================================================================= мир
def save(img, rel):
    return P.save_asset(img, rel)


def hazed(img, color, k):
    """Дымка воздушной перспективы: смешать цвет с тёплым тоном, сохранив прозрачность."""
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    a[..., :3] = a[..., :3] * (1 - k) + np.array(color, np.float32) * k
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def tileable_ground(img, crop_top):
    g = P.clean_alpha(P.key_magenta(img)).crop((0, crop_top, img.width, img.height))
    ga = np.asarray(g).astype(np.float32)
    blend = 220
    w = ga.shape[1] - blend
    tile = ga[:, :w].copy()
    k = np.linspace(0, 1, blend)[None, :, None]
    tile[:, :blend] = ga[:, w:] * (1 - k) + ga[:, :blend] * k
    return Image.fromarray(tile.clip(0, 255).astype(np.uint8), "RGBA")


def build_world():
    src = lambda p: Image.open(os.path.join(SRC, p))
    # небо: с запасом по ширине — камера на скорости отъезжает
    sky = src("bg/sky.png").convert("RGB").crop((0, 60, 1536, 924)).resize((1500, 844), Image.LANCZOS)
    save(sky, "bg/sky_day.jpg")
    if exists("bg/sky_night.png"):
        night = src("bg/sky_night.png").convert("RGB").crop((0, 60, 1536, 924)).resize((1500, 844), Image.LANCZOS)
        save(night, "bg/sky_night.jpg")
    ground = tileable_ground(src("bg/ground.png"), 580)
    ground = ground.resize((int(ground.width * 0.62), int(ground.height * 0.62)), Image.LANCZOS)
    save(ground, "bg/ground.png")
    far = ground.resize((ground.width // 2, ground.height // 2), Image.LANCZOS)
    save(hazed(far, (240, 165, 105), 0.42), "bg/ground_far.png")
    save(hazed(far, (90, 70, 130), 0.5), "bg/ground_far_night.png")

    def objs(rel, scale, prefix, far_scale=None):
        if not exists(rel):
            return 0
        rgba = P.clean_alpha(P.key_magenta(src(rel)))
        items = P.extract_objects(rgba, min_area=4000, merge=4)
        for i, o in enumerate(items):
            im = o["img"]
            im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
            save(im, f"bg/{prefix}_{i}.png")
            if far_scale:
                save(hazed(im, (240, 170, 110), 0.26), f"bg/{prefix}_far_{i}.png")
                save(hazed(im, (95, 75, 140), 0.45), f"bg/{prefix}_night_{i}.png")
        return len(items)

    n = {
        "ruins": objs("bg/ruins.png", 0.5, "ruins", far_scale=True),
        "stones": objs("bg/stones.png", 0.42, "stone"),
        "grass": objs("bg/grass.png", 0.3, "grass"),
        "kurgan": objs("bg/kurgan_props.png", 0.45, "kurgan"),
    }
    # юрта: кадр 16:9 из листа 3:2
    yurt = src("bg/yurt_bg.png").convert("RGB").crop((0, 80, 1536, 944)).resize((1280, 720), Image.LANCZOS)
    save(yurt, "bg/yurt.jpg")
    # огонь очага: 8 кадров на чёрном → альфа по яркости
    fire = P.key_black(src("fx/fire.png"))
    fw, fh = fire.width // 4, fire.height // 2
    frames = []
    for r in range(2):
        for c in range(4):
            fr = fire.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
            frames.append(fr.resize((fw // 2, fh // 2), Image.LANCZOS))
    strip = Image.new("RGBA", (frames[0].width * 8, frames[0].height))
    for i, f in enumerate(frames):
        strip.paste(f, (i * f.width, 0))
    save(strip, "fx/fire_strip.png")
    print("  мир:", n, "огонь", frames[0].size)


# ======================================================================= интерфейс
def build_ui():
    src = lambda p: Image.open(os.path.join(SRC, p))
    hud = P.clean_alpha(P.key_magenta(src("ui/hud.png")))
    bb = hud.getbbox()
    hud = hud.crop(bb)
    arr = np.array(hud)
    lum = arr[..., :3].astype(np.int32).sum(-1) / 3
    dark = (arr[..., 3] > 200) & (lum < 70)
    # тонкий тёмный контур рамки связывает окна в одну область — отрезаем его эрозией
    lab, _ = ndimage.label(ndimage.binary_erosion(dark, iterations=4))
    # окна полос: самые большие тёмные области в верхней половине; ромбы — внизу
    regions = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        m = lab[sl] == i + 1
        if m.sum() < 1500:
            continue
        full = ndimage.binary_dilation(lab == i + 1, iterations=6) & dark
        ys_, xs_ = np.nonzero(full)
        sl = (slice(ys_.min(), ys_.max() + 1), slice(xs_.min(), xs_.max() + 1))
        regions.append((int(m.sum()), sl, i + 1, full))
    regions.sort(key=lambda r: -r[0])
    bars = sorted([r for r in regions if (r[1][1].stop - r[1][1].start) > 3 * (r[1][0].stop - r[1][0].start)][:2],
                  key=lambda r: r[1][0].start)
    diamonds = sorted([r for r in regions if abs((r[1][1].stop - r[1][1].start) - (r[1][0].stop - r[1][0].start)) < 30
                       and r[1][0].start > hud.height * 0.5][:3], key=lambda r: r[1][1].start)
    scale = 0.42
    layout = {"scale": scale, "size": [int(hud.width * scale), int(hud.height * scale)]}
    names = ["hp", "st"]
    colors = [((255, 92, 70), (150, 20, 25)), ((120, 255, 230), (20, 130, 125))]
    frame = arr.copy()
    for (area, sl, idx, full), nm, (c1, c2) in zip(bars, names, colors):
        m = ndimage.binary_dilation(full, iterations=2) & (arr[..., 3] > 0) & (lum < 110)
        frame[m, 3] = 0   # прорезаем окно в рамке — полоска будет видна под ней
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        sub = m[y0 - 2:y1 + 2, x0 - 2:x1 + 2]
        h, w = sub.shape
        grad = np.zeros((h, w, 4), np.float32)
        t = np.linspace(0, 1, h)[:, None]
        for ch in range(3):
            grad[..., ch] = c1[ch] * (1 - t) + c2[ch] * t
        grad[..., :3] += (np.exp(-((np.linspace(0, 1, h) - 0.22) ** 2) / 0.01)[:, None, None] * 60)  # блик
        grad[..., 3] = sub * 255
        fill = Image.fromarray(grad.clip(0, 255).astype(np.uint8), "RGBA")
        fill = fill.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
        save(fill, f"ui/bar_{nm}.png")
        back = np.zeros((h, w, 4), np.uint8)
        back[..., :3] = (22, 14, 12)
        back[..., 3] = sub * 235
        save(Image.fromarray(back, "RGBA").resize(fill.size, Image.LANCZOS), f"ui/bar_{nm}_back.png")
        layout[nm] = [int((x0 - 2) * scale), int((y0 - 2) * scale)]
    layout["slots"] = []
    for area, sl, idx, full in diamonds:
        cy, cx = (sl[0].start + sl[0].stop) / 2, (sl[1].start + sl[1].stop) / 2
        layout["slots"].append([int(cx * scale), int(cy * scale), int((sl[1].stop - sl[1].start) * scale)])
    fimg = Image.fromarray(frame, "RGBA")
    save(fimg.resize(tuple(layout["size"]), Image.LANCZOS), "ui/hud_frame.png")
    # иконки: сетка 4x3 — Дары (бог × слот), асык, тумар, сердце
    icons = P.clean_alpha(P.key_magenta(src("ui/icons.png")))
    gods = ["tengri", "umai", "ot_ana"]
    extra = ["asyk", "tumar", "heart"]

    def cell_object(img, box):
        """Главный объект внутри ячейки сетки (свечения соседей отрезаются рамкой ячейки)."""
        sub = img.crop(box)
        arr2 = np.array(sub)
        lab3, n3 = ndimage.label(arr2[..., 3] > 25, structure=np.ones((3, 3)))
        if n3 == 0:
            return None
        sizes = ndimage.sum(arr2[..., 3] > 25, lab3, range(1, n3 + 1))
        keep = np.isin(lab3, [i + 1 for i, v in enumerate(sizes) if v > sizes.max() * 0.08])
        arr2[..., 3] = np.where(keep, arr2[..., 3], 0)
        im = Image.fromarray(arr2, "RGBA")
        return im.crop(im.getbbox())

    cw, ch = icons.width / 4, icons.height / 3
    for r in range(3):
        for c in range(4):
            im = cell_object(icons, (int(c * cw), int(r * ch), int((c + 1) * cw), int((r + 1) * ch)))
            if im is None:
                continue
            im.thumbnail((128, 128), Image.LANCZOS)
            save(im, f"ui/icons/{gods[r]}_{c}.png" if c < 3 else f"ui/icons/{extra[r]}.png")
    # медальоны богов: три в ряд, режем по третям
    gimg = P.clean_alpha(P.key_magenta(src("ui/gods.png")))
    for i in range(3):
        im = cell_object(gimg, (int(i * gimg.width / 3), 0, int((i + 1) * gimg.width / 3), gimg.height))
        im.thumbnail((220, 220), Image.LANCZOS)
        save(im, f"ui/gods/{gods[i]}.png")
    # панель меню (9-slice)
    panel = P.clean_alpha(P.key_magenta(src("ui/panel.png")))
    panel = panel.crop(panel.getbbox())
    panel = panel.resize((panel.width // 2, panel.height // 2), Image.LANCZOS)
    save(panel, "ui/panel.png")
    layout["panel_margin"] = 64
    import json
    with open(os.path.join(ASSETS, "ui", "hud_layout.json"), "w") as f:
        json.dump(layout, f, indent=1)
    write_hud_layout_gd(layout)
    print("  интерфейс:", layout)


def write_hud_layout_gd(layout):
    lines = ["extends RefCounted", "## Сгенерировано tools/build_assets.py: где на рамке HUD окна полос и ромбы Даров.", ""]
    lines.append(f"const SIZE := Vector2({layout['size'][0]}, {layout['size'][1]})")
    lines.append(f"const HP_POS := Vector2({layout['hp'][0]}, {layout['hp'][1]})")
    lines.append(f"const ST_POS := Vector2({layout['st'][0]}, {layout['st'][1]})")
    lines.append("const SLOTS := [" + ", ".join(f"Vector3({x}, {y}, {s})" for x, y, s in layout["slots"]) + "]")
    with open(os.path.join(ROOT, "scripts", "data", "hud_layout.gd"), "w") as f:
        f.write("\n".join(lines) + "\n")


# ======================================================================= эффекты
def radial(size, stops):
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.sqrt((xx - size / 2 + 0.5) ** 2 + (yy - size / 2 + 0.5) ** 2) / (size / 2)
    out = np.zeros((size, size, 4), np.float32)
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        m = (d >= t0) & (d <= t1)
        k = ((d - t0) / max(1e-6, t1 - t0))[..., None]
        out[m] = (np.array(c0) * (1 - k) + np.array(c1) * k)[m]
    out[d > stops[-1][0]] = stops[-1][1]
    return Image.fromarray(out.clip(0, 255).astype(np.uint8), "RGBA")


def build_fx():
    save(radial(128, [(0, (255, 255, 255, 255)), (0.5, (255, 255, 255, 110)), (1, (255, 255, 255, 0))]), "fx/soft.png")
    save(radial(64, [(0, (236, 196, 146, 230)), (0.6, (208, 152, 104, 115)), (1, (190, 130, 90, 0))]), "fx/puff.png")
    save(radial(64, [(0, (255, 240, 210, 216)), (0.7, (255, 220, 170, 128)), (0.9, (255, 230, 190, 150)), (1, (255, 220, 170, 0))]), "fx/bokeh.png")
    save(radial(512, [(0, (255, 240, 190, 140)), (0.35, (255, 190, 110, 50)), (1, (255, 150, 60, 0))]), "fx/sun_glow.png")
    save(radial(96, [(0, (60, 25, 10, 140)), (0.7, (60, 25, 10, 60)), (1, (60, 25, 10, 0))]).resize((192, 40), Image.LANCZOS), "fx/shadow.png")
    # виньетка
    w, h = 640, 360
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 * 0.9 + ((yy - h * 0.55) / (h / 2)) ** 2 * 0.6)
    a = np.clip((d - 0.55) / 0.75, 0, 1) ** 1.4 * 150
    vig = np.zeros((h, w, 4), np.uint8)
    vig[..., 0], vig[..., 1], vig[..., 2], vig[..., 3] = 45, 10, 0, a.astype(np.uint8)
    save(Image.fromarray(vig, "RGBA"), "fx/vignette.png")
    # луч солнца: клин, гаснущий к концу
    L, Wd = 1024, 96
    ray = np.zeros((Wd, L, 4), np.float32)
    xs = np.linspace(0, 1, L)[None, :]
    ys = np.abs(np.linspace(-1, 1, Wd))[:, None]
    inside = ys <= xs * 1.0 + 0.02
    soft = np.clip(1 - ys / np.maximum(xs, 0.02), 0, 1)
    ray[..., :3] = (255, 225, 165)
    ray[..., 3] = inside * soft * (1 - xs) ** 1.3 * 255
    save(Image.fromarray(ray.clip(0, 255).astype(np.uint8), "RGBA"), "fx/ray.png")
    # искра-штрих
    sp = np.zeros((8, 64, 4), np.float32)
    sp[..., :3] = 255
    sp[..., 3] = (np.linspace(0, 1, 64)[None, :] ** 1.5) * (1 - np.abs(np.linspace(-1, 1, 8))[:, None]) * 255
    save(Image.fromarray(sp.astype(np.uint8), "RGBA"), "fx/spark.png")
    # пух ковыля
    fl = Image.new("RGBA", (32, 32))
    d = ImageDraw.Draw(fl)
    d.line([(16, 30), (16, 13)], fill=(255, 238, 205, 240), width=1)
    for i in range(14):
        an = -math.pi / 2 + (i / 13 - 0.5) * 1.6
        d.line([(16, 13), (16 + math.cos(an) * 11, 13 + math.sin(an) * 11)], fill=(255, 238, 205, 240), width=1)
    save(fl, "fx/fluff.png")
    # перекати-поле
    tw = Image.new("RGBA", (192, 192))
    d = ImageDraw.Draw(tw)
    rnd = random.Random(5)
    for i in range(110):
        a1 = rnd.uniform(0, 6.3)
        a2 = a1 + rnd.uniform(-1.5, 1.5)
        r1, r2 = rnd.uniform(20, 88), rnd.uniform(20, 88)
        p0 = (96 + math.cos(a1) * r1, 96 + math.sin(a1) * r1)
        p2 = (96 + math.cos(a2) * r2, 96 + math.sin(a2) * r2)
        p1 = (96 + rnd.uniform(-50, 50), 96 + rnd.uniform(-50, 50))
        pts = [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in np.linspace(0, 1, 12)]
        col = (rnd.randint(120, 170), rnd.randint(80, 115), rnd.randint(40, 65), 245)
        d.line(pts, fill=col, width=rnd.choice([2, 2, 3]))
    save(tw, "fx/tumble.png")
    # стрела аруака: древко, оперение, светящийся наконечник
    ar = Image.new("RGBA", (120, 20))
    d = ImageDraw.Draw(ar)
    d.line([(8, 10), (100, 10)], fill=(110, 80, 50, 255), width=3)
    d.polygon([(100, 4), (118, 10), (100, 16)], fill=(170, 230, 255, 255))
    d.polygon([(2, 3), (18, 10), (2, 17), (10, 10)], fill=(200, 210, 230, 255))
    ar = Image.alpha_composite(ar.filter(ImageFilter.GaussianBlur(3)).point(lambda v: v), ar)
    save(ar, "fx/arrow.png")
    # шар бақсы
    save(radial(96, [(0, (255, 235, 255, 255)), (0.3, (210, 110, 255, 235)), (0.7, (140, 40, 220, 110)), (1, (90, 20, 160, 0))]), "fx/orb.png")
    # ударная волна по земле (полумесяц огня)
    sw = Image.new("RGBA", (200, 120))
    d = ImageDraw.Draw(sw)
    for i, (col, wdt) in enumerate([((255, 110, 30, 150), 26), ((255, 190, 90, 220), 12), ((255, 245, 210, 255), 5)]):
        d.arc([20, 10, 180, 230], 200, 340, fill=col, width=wdt)
    sw = sw.filter(ImageFilter.GaussianBlur(1.5))
    save(sw, "fx/shockwave.png")
    # знак «неблокируемо» (красный ромб с !)
    wn = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(wn)
    d.polygon([(32, 2), (62, 32), (32, 62), (2, 32)], fill=(200, 30, 20, 235), outline=(255, 220, 140, 255))
    d.rectangle([29, 14, 35, 38], fill=(255, 245, 225, 255))
    d.rectangle([29, 44, 35, 50], fill=(255, 245, 225, 255))
    save(wn, "fx/warning.png")
    # значок «!» над врагом в замахе: белый, цвет (жёлтый — блокируй, красный — только кувырок) задаётся в игре
    al = Image.new("RGBA", (336, 336))
    d = ImageDraw.Draw(al)
    c, r = 168, 152
    d.polygon([(c, c - r), (c + r, c), (c, c + r), (c - r, c)], fill=(20, 10, 6, 255))
    r2 = r - 28
    d.polygon([(c, c - r2), (c + r2, c), (c, c + r2), (c - r2, c)], fill=(255, 255, 255, 255))
    d.rounded_rectangle([c - 22, c - 88, c + 22, c + 28], radius=16, fill=(25, 12, 8, 255))
    d.ellipse([c - 24, c + 48, c + 24, c + 96], fill=(25, 12, 8, 255))
    al = al.resize((84, 84), Image.LANCZOS)
    big = Image.new("RGBA", (104, 104))
    big.paste(al, (10, 10))
    # тёмная тень вокруг — значок читается и на ярком закатном небе
    halo = Image.new("RGBA", big.size, (10, 4, 2, 0))
    halo.putalpha(big.split()[3].filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(5)).point(lambda v: int(v * 0.8)))
    save(Image.alpha_composite(halo, big), "fx/alert.png")
    # каменная крошка
    ch = Image.new("RGBA", (16, 16))
    d = ImageDraw.Draw(ch)
    d.polygon([(2, 6), (8, 1), (15, 5), (13, 13), (5, 15)], fill=(138, 109, 82, 255), outline=(58, 42, 30, 255))
    save(ch, "fx/chip.png")
    print("  эффекты: готово")


def build_icon():
    hero = Image.open(os.path.join(ASSETS, "sprites", "batyr", "idle.png"))
    import json
    meta = json.load(open(os.path.join(ASSETS, "sprites", "batyr", "meta.json")))
    fw = meta["frame_w"]
    f = hero.crop((0, 0, fw, meta["frame_h"]))
    bb = f.getbbox()
    head = f.crop((bb[0], bb[1], bb[2], bb[1] + (bb[2] - bb[0])))
    icon = Image.new("RGBA", (256, 256), (40, 22, 16, 255))
    d = ImageDraw.Draw(icon)
    d.rounded_rectangle([4, 4, 252, 252], 40, outline=(217, 178, 90, 255), width=8, fill=(58, 30, 20, 255))
    head.thumbnail((210, 210), Image.LANCZOS)
    icon.alpha_composite(head, ((256 - head.width) // 2, (256 - head.height) // 2 + 10))
    icon.save(os.path.join(ROOT, "icon.png"))


def main():
    want = set(sys.argv[1:])
    print("Персонажи:")
    for name in CHARACTERS:
        if not want or name in want:
            build_character(name)
    if not want or "world" in want:
        print("Мир:")
        build_world()
    if not want or "ui" in want:
        print("Интерфейс:")
        build_ui()
    if not want or "fx" in want:
        print("Эффекты:")
        build_fx()
        build_icon()


if __name__ == "__main__":
    main()
