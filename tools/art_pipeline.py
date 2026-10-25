#!/usr/bin/env python3
"""Нарезка сгенерированных листов (art_src/) в игровые ассеты (assets/).

- снимает пурпурный (#FF00FF) хромакей с мягким краем и подавлением «засветки»;
- режет спрайт-листы по сетке, выравнивает кадры по ногам и центру корпуса;
- пишет ленты кадров PNG + ресурс SpriteFrames (.tres) для Godot.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "art_src")
ASSETS = os.path.join(ROOT, "assets")
MAGENTA = np.array([255.0, 0.0, 255.0])


# ------------------------------------------------------------------ хромакей
def key_magenta(img, lo=0.12, hi=0.80, hard=70.0):
    """RGBA с прозрачным пурпурным фоном."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    s = np.clip((np.minimum(r, b) - g) / 255.0, 0, 1)  # «пурпурность»
    alpha = np.clip((hi - s) / (hi - lo), 0, 1)
    dist = np.sqrt(((a - MAGENTA) ** 2).sum(-1))
    alpha[dist < hard] = 0
    # убрать вклад фона из цвета (despill)
    k = (1 - alpha)[..., None]
    fg = (a - k * MAGENTA) / np.maximum(alpha[..., None], 1e-3)
    fg = np.clip(fg, 0, 255)
    # на полупрозрачных пикселях дополнительно гасим пурпурный оттенок
    semi = (alpha < 0.98)[..., None]
    gray = fg.mean(-1, keepdims=True)
    mg = np.clip((np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1]) / 255.0, 0, 1)[..., None]
    fg = np.where(semi, fg * (1 - mg) + gray * mg, fg)
    out = np.dstack([fg, alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def key_black(img, gamma=0.85):
    """Для огня/свечения на чёрном: альфа = яркость, цвет = «раздутый» до полной яркости."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    m = a.max(-1)
    alpha = np.clip(m, 0, 1) ** gamma
    alpha[m < 0.04] = 0
    col = a / np.maximum(m[..., None], 1e-3)
    out = np.dstack([np.clip(col * 255, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def clean_alpha(rgba, min_area=30):
    """Убрать мелкий мусор (одиночные пиксели после кеинга)."""
    arr = np.array(rgba)
    mask = arr[..., 3] > 25
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    if n:
        sizes = ndimage.sum(mask, lab, range(1, n + 1))
        small = np.isin(lab, np.nonzero(sizes < min_area)[0] + 1)
        arr[small, 3] = 0
    return Image.fromarray(arr, "RGBA")


# ------------------------------------------------------------------ объекты
def components(rgba, thresh=25, min_area=30):
    arr = np.array(rgba)
    mask = arr[..., 3] > thresh
    lab, n = ndimage.label(mask, structure=np.ones((3, 3)))
    objs = ndimage.find_objects(lab)
    comps = []
    for i, sl in enumerate(objs):
        m = lab[sl] == i + 1
        area = int(m.sum())
        if area < min_area:
            continue
        ys, xs = np.nonzero(m)
        comps.append(dict(id=i + 1, sl=sl, area=area,
                          cx=float(xs.mean() + sl[1].start), cy=float(ys.mean() + sl[0].start)))
    return lab, comps


def extract_objects(rgba, min_area=2000, merge=12):
    """Отдельные объекты листа ассетов (камни, руины, иконки). Близкие куски сливаются."""
    arr = np.array(rgba)
    mask = arr[..., 3] > 25
    grown = ndimage.binary_dilation(mask, iterations=merge)
    lab, n = ndimage.label(grown, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        m = (lab[sl] == i + 1) & mask[sl]
        if m.sum() < min_area:
            continue
        crop = arr[sl].copy()
        crop[..., 3] = np.where(m, crop[..., 3], 0)
        im = Image.fromarray(crop, "RGBA")
        bb = im.getbbox()
        out.append(dict(img=im.crop(bb), x=sl[1].start + bb[0], y=sl[0].start + bb[1]))
    out.sort(key=lambda o: (round(o["y"] / 200), o["x"]))
    return out


# ------------------------------------------------------------------ спрайт-листы
def grid_frames(rgba, cols, rows, min_area=20):
    """Кадры по ячейкам сетки. Куски приписываются ячейке по их центру,
    поэтому заехавшие в соседнюю ячейку дуги/оружие не теряются."""
    W, H = rgba.size
    cw, ch = W / cols, H / rows
    lab, comps = components(rgba, min_area=min_area)
    arr = np.array(rgba)
    cells = {}
    for cmp in comps:
        col = min(cols - 1, int(cmp["cx"] // cw))
        row = min(rows - 1, int(cmp["cy"] // ch))
        cells.setdefault((row, col), []).append(cmp)
    frames = {}
    for (row, col), cl in cells.items():
        ids = [c["id"] for c in cl]
        m = np.isin(lab, ids)
        ys, xs = np.nonzero(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        crop = arr[y0:y1, x0:x1].copy()
        crop[..., 3] = np.where(m[y0:y1, x0:x1], crop[..., 3], 0)
        main = max(cl, key=lambda c: c["area"])
        msl = main["sl"]
        frames[(row, col)] = dict(img=Image.fromarray(crop, "RGBA"), x0=int(x0), y0=int(y0),
                                  main_bottom=int(msl[0].stop), main_top=int(msl[0].start), main_area=main["area"],
                                  main_id=main["id"], lab=lab, msl=msl)
    return frames


def body_anchor(fr, band=(0.30, 0.62)):
    """Опорная точка кадра: x — медиана массы корпуса (полоса по высоте),
    y — низ основного силуэта (ноги)."""
    lab, msl = fr["lab"], fr["msl"]
    m = lab[msl] == fr["main_id"]
    h = m.shape[0]
    b0, b1 = int(h * band[0]), max(int(h * band[0]) + 1, int(h * band[1]))
    sub = m[b0:b1]
    ys, xs = np.nonzero(sub)
    if len(xs) == 0:
        ys, xs = np.nonzero(m)
    ax = float(np.median(xs)) + msl[1].start
    ay = float(fr["main_bottom"])
    return ax, ay


def sheet_height(frames, sel=None):
    """Типичный размер персонажа на листе: корень из площади основного силуэта
    (в отличие от высоты почти не зависит от позы).
    sel — строки (int) и/или отдельные ячейки (row, col), по которым мерить."""
    return float(np.median([math.sqrt(f["main_area"]) for (r, c), f in frames.items()
                            if sel is None or r in sel or (r, c) in sel]))


def build_character(name, sheets, scale, anims, pad=8, norm_to=None):
    """sheets: {key: (path, cols, rows[, height_hint])}; anims: [(anim, key, [(row,col),...], fps, loop, anchor_mode)].

    Персонаж на разных листах нарисован в разном масштабе, поэтому каждый лист
    приводится к росту листа norm_to (по умолчанию — первого). height_hint
    позволяет сравнить похожие движения: (ref_key, ref_rows, own_rows) — рост в own_rows
    этого листа приравнивается к росту в ref_rows листа ref_key (бег к бегу, удар к удару)."""
    keyed = {}
    for k, spec in sheets.items():
        path, cols, rows = spec[:3]
        img = Image.open(os.path.join(SRC, path))
        rgba = clean_alpha(key_magenta(img))
        keyed[k] = [rgba, grid_frames(rgba, cols, rows), None]
    base = norm_to or next(iter(sheets))
    ref_h = sheet_height(keyed[base][1])
    for k, spec in sheets.items():
        if len(spec) > 3:
            rk, ref_rows, own_rows = spec[3]
            factor = sheet_height(keyed[rk][1], ref_rows) / sheet_height(keyed[k][1], own_rows)
            if rk != base:
                factor *= keyed[rk][2] / scale
            keyed[k][2] = scale * factor
        else:
            keyed[k][2] = scale * ref_h / sheet_height(keyed[k][1])
    # собираем кадры с опорными точками
    seq = []
    durs = {}
    for spec in anims:
        anim, k, cells, fps, loop, mode = spec[:6]
        if len(spec) > 6 and spec[6]:
            durs[anim] = list(spec[6])
        rgba, frames, s = keyed[k]
        items = []
        for cell in cells:
            fr = frames.get(tuple(cell))
            if fr is None:
                raise SystemExit(f"{name}: нет кадра {cell} в листе {k}")
            ax, ay = body_anchor(fr)
            if mode == "bbox":
                ax = fr["x0"] + fr["img"].width / 2
            if mode == "ground":
                ay = fr["y0"] + fr["img"].height
            items.append((fr, ax, ay, s))
        if mode == "row_x":  # общий отступ от рамки для всей строки (почти статичные позы)
            rel = float(np.mean([a - fr["x0"] for fr, a, _, _ in items]))
            items = [(fr, fr["x0"] + rel, ay, s) for fr, _, ay, s in items]
        seq.append((anim, items, fps, loop))
    # размер кадра — максимум по всем анимациям (одинаковый для всех), уже в итоговом масштабе
    left = right = up = down = 0
    for _, items, _, _ in seq:
        for fr, ax, ay, s in items:
            left = max(left, (ax - fr["x0"]) * s)
            right = max(right, (fr["x0"] + fr["img"].width - ax) * s)
            up = max(up, (ay - fr["y0"]) * s)
            down = max(down, (fr["y0"] + fr["img"].height - ay) * s)
    half = max(left, right)
    fw = int(math.ceil(2 * half + 2 * pad))
    fh = int(math.ceil(up + down + 2 * pad))
    fw += fw % 2
    fh += fh % 2
    anchor = (fw / 2, fh - down - pad)
    out_dir = os.path.join(ASSETS, "sprites", name)
    os.makedirs(out_dir, exist_ok=True)
    meta = dict(frame_w=fw, frame_h=fh, anchor_x=anchor[0], anchor_y=anchor[1], anims={})
    for anim, items, fps, loop in seq:
        strip = Image.new("RGBA", (fw * len(items), fh))
        for i, (fr, ax, ay, s) in enumerate(items):
            im = fr["img"]
            im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
            px = anchor[0] - (ax - fr["x0"]) * s + i * fw
            py = anchor[1] - (ay - fr["y0"]) * s
            strip.alpha_composite(im, (int(round(px)), int(round(py))))
        strip.save(os.path.join(out_dir, f"{anim}.png"), optimize=True)
        meta["anims"][anim] = dict(frames=len(items), fps=fps, loop=loop, durations=durs.get(anim))
    write_spriteframes(os.path.join(out_dir, f"{name}_frames.tres"), f"res://assets/sprites/{name}", meta)
    with open(os.path.join(out_dir, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def add_strip(name, meta, anim, frames, fps, loop, durations=None):
    """Добавить к персонажу анимацию из готовых кадров (например, процедурное раскалывание)."""
    fw, fh = meta["frame_w"], meta["frame_h"]
    out_dir = os.path.join(ASSETS, "sprites", name)
    strip = Image.new("RGBA", (fw * len(frames), fh))
    for i, f in enumerate(frames):
        strip.alpha_composite(f.crop((0, 0, fw, fh)), (i * fw, 0))
    strip.save(os.path.join(out_dir, f"{anim}.png"), optimize=True)
    meta["anims"][anim] = dict(frames=len(frames), fps=fps, loop=loop, durations=durations)
    write_spriteframes(os.path.join(out_dir, f"{name}_frames.tres"), f"res://assets/sprites/{name}", meta)


def write_spriteframes(path, res_dir, meta, prefix=""):
    """SpriteFrames для Godot. Длительности кадров (удержание ключевых поз) берутся из meta,
    опорная точка (ноги) — в metadata/anchor, чтобы скрипт мог выставить offset."""
    fw, fh = meta["frame_w"], meta["frame_h"]
    ext, subs, anims = [], [], []
    sid = 0
    for i, (anim, info) in enumerate(meta["anims"].items()):
        ext.append(f'[ext_resource type="Texture2D" path="{res_dir}/{prefix}{anim}.png" id="{i + 1}"]')
        fr_list = []
        durs = info.get("durations") or [1.0] * info["frames"]
        for f in range(info["frames"]):
            sid += 1
            subs.append(f'[sub_resource type="AtlasTexture" id="at_{sid}"]\natlas = ExtResource("{i + 1}")\n'
                        f"region = Rect2({f * fw}, 0, {fw}, {fh})")
            fr_list.append(f'{{\n"duration": {float(durs[f])},\n"texture": SubResource("at_{sid}")\n}}')
        anims.append('{\n"frames": [' + ", ".join(fr_list) + f'],\n"loop": {"true" if info["loop"] else "false"},\n'
                     f'"name": &"{anim}",\n"speed": {float(info["fps"])}\n}}')
    text = f'[gd_resource type="SpriteFrames" load_steps={len(ext) + len(subs) + 1} format=3]\n\n'
    text += "\n".join(ext) + "\n\n" + "\n\n".join(subs) + "\n\n[resource]\n"
    text += f'metadata/anchor = Vector2({meta["anchor_x"]}, {meta["anchor_y"]})\n'
    text += f'metadata/frame_size = Vector2({fw}, {fh})\n'
    text += "animations = [" + ", ".join(anims) + "]\n"
    with open(path, "w") as f:
        f.write(text)


def save_asset(img, rel):
    p = os.path.join(ASSETS, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)
    return p
