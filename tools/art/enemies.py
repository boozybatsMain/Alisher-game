"""Враги: каменный воин-балбал, дух степи и мини-босс Жезтырнак."""
import math
import random

import numpy as np
from PIL import Image, ImageFilter

from common import (Layer, add, bezier, c, capsule, draw_ram_horn, ellipse_pts, glow, lerp_pt,
                    limb_dir, rot, shade, silhouette_outline, SS)

# =============================================================== БАЛБАЛ
BW, BH, BCX, BGROUND = 256, 256, 128, 246
STONE = (158, 136, 112)
STONE_LT = (194, 174, 146)
STONE_DK = (104, 88, 72)
CRACK = (70, 56, 46)
EYE = (255, 120, 40)

BAL_DEFAULT = dict(dx=0, dy=0, lean=0, lleg=8, rleg=-8, arm=18, elbow=30, mace=70, eye=0.0, smear=None)


def balbal_render(pose, return_layer=False):
    p = dict(BAL_DEFAULT)
    p.update(pose)
    B = Layer(BW, BH)
    G = Layer(BW, BH)
    root = (BCX + p["dx"], BGROUND - 42 + p["dy"])
    t = p["lean"]
    up = limb_dir(180 - t, 1)
    fw = (math.cos(math.radians(t)), math.sin(math.radians(t)))

    def L(lx, ly):
        return (root[0] + fw[0] * lx + up[0] * ly, root[1] + fw[1] * lx + up[1] * ly)

    # ноги-тумбы
    for side, ang, k in (("b", p["rleg"], 0.72), ("f", p["lleg"], 1.0)):
        hip = add(root, (-8 if side == "b" else 8, 0))
        foot = add(hip, limb_dir(ang, 34))
        B.poly(capsule(hip, foot, 13, 11), c(shade(STONE, k)), c(shade(STONE_DK, k * 0.8)), 1.2)
        B.poly([add(foot, (-13, -4)), add(foot, (17, -4)), add(foot, (18, 8)), add(foot, (-13, 8))],
               c(shade(STONE_DK, k)), c(shade(CRACK, k)), 1)
        B.line([add(hip, (-8, 14)), add(hip, (6, 16))], c(shade(CRACK, k)), 0.9)

    # корпус
    body = [L(*q) for q in [(-27, -4), (25, -4), (29, 28), (27, 60), (17, 74), (-18, 74), (-29, 60), (-31, 28)]]
    B.poly(body, c(STONE), c(STONE_DK), 1.4)
    B.poly([L(*q) for q in [(-27, -4), (-12, -4), (-14, 40), (-12, 72), (-18, 74), (-29, 60), (-31, 28)]],
           c(shade(STONE, 0.86)))
    B.poly([L(*q) for q in [(12, 70), (24, 56), (26, 30), (22, 6), (18, 8), (20, 40), (8, 70)]], c(STONE_LT))
    # пятна камня (в локальных координатах — не «плывут» в анимации)
    rnd = random.Random(7)
    for _ in range(26):
        lx, ly = rnd.uniform(-24, 22), rnd.uniform(2, 68)
        B.circle(L(lx, ly), rnd.uniform(0.8, 2.0), c(rnd.choice([STONE_DK, STONE_LT, shade(STONE, 0.9)])))
    # трещины
    B.line([L(-20, 60), L(-12, 48), L(-15, 36), L(-6, 26)], c(CRACK), 1.0)
    B.line([L(18, 20), L(10, 14), L(13, 4)], c(CRACK), 0.9)
    # резной пояс
    B.line([L(-30, 12), L(27, 12)], c(STONE_DK), 2.4)
    B.line([L(-30, 14), L(27, 14)], c(STONE_LT), 0.8)
    # барельеф: рука с чашей у живота (классическая поза балбала)
    B.line([L(-16, 64), L(-14, 42), L(4, 30), L(14, 30)], c(STONE_DK), 2.2)
    B.poly([L(*q) for q in [(6, 36), (22, 36), (19, 26), (9, 26)]], c(STONE_DK), c(CRACK), 0.9)
    B.line([L(5, 36), L(23, 36)], c(STONE_LT), 1.0)

    # голова со шлемом
    hc = L(4, 98)
    hp = lambda q: add(hc, rot(q, t))
    B.poly([hp(q) for q in ellipse_pts(0, 0, 21, 24, 0, 40)], c(STONE), c(STONE_DK), 1.3)
    B.poly([hp(q) for q in ellipse_pts(-6, 2, 13, 20, 0, 30)], c(shade(STONE, 0.86)))
    helm = [hp(q) for q in [(-22, -2), (-20, -14), (-10, -26), (2, -38), (12, -26), (21, -12), (22, -2), (12, -6), (-12, -6)]]
    B.poly(helm, c(STONE_DK), c(CRACK), 1.1)
    B.line([hp((-21, -3)), hp((22, -3))], c(STONE_LT), 1.2)
    # лицо (3/4): глаза, нос, усы
    eye_col = mix_col(CRACK, EYE, p["eye"])
    for ex in (12, 0):
        B.poly([hp(q) for q in ellipse_pts(ex, 3, 4.5, 2.2, -8, 16)], c(eye_col))
        if p["eye"] > 0:
            G.poly([hp(q) for q in ellipse_pts(ex, 3, 6, 3.5, -8, 16)], c(EYE, 255 * p["eye"]))
    B.line([hp((7, 0)), hp((10, 13)), hp((6, 14))], c(CRACK), 1.2)
    B.line([hp((1, 18)), hp((7, 15)), hp((14, 18))], c(CRACK), 1.5)
    B.line([hp((1, 18)), hp((-2, 24))], c(CRACK), 1.2)
    B.line([hp((14, 18)), hp((16, 24))], c(CRACK), 1.2)

    # рука с булавой
    sh = L(16, 62)
    el = add(sh, limb_dir(p["arm"], 28))
    fist = add(el, limb_dir(p["arm"] + p["elbow"], 26))
    d = (math.cos(math.radians(p["mace"])), math.sin(math.radians(p["mace"])))
    handle_end = add(fist, (d[0] * 52, d[1] * 52))
    B.line([add(fist, (-d[0] * 10, -d[1] * 10)), handle_end], c((72, 52, 40)), 5.5)
    B.line([add(fist, (-d[0] * 10, -d[1] * 10)), handle_end], c((104, 78, 58)), 2.0)
    mh = add(fist, (d[0] * 60, d[1] * 60))
    B.circle(mh, 17, c(STONE_DK), c(CRACK), 1.3)
    rnd = random.Random(3)
    for a in range(0, 360, 45):
        q = add(mh, (math.cos(math.radians(a + p["mace"])) * 17, math.sin(math.radians(a + p["mace"])) * 17))
        B.circle(q, 4.2, c(STONE_DK), c(CRACK), 1)
    B.circle(add(mh, (-4, -5)), 6, c(shade(STONE_DK, 1.25)))
    B.poly(capsule(sh, el, 12, 11), c(STONE), c(STONE_DK), 1.2)
    B.poly(capsule(el, fist, 11, 10), c(STONE), c(STONE_DK), 1.2)
    B.circle(fist, 11, c(STONE_LT), c(STONE_DK), 1.2)
    B.line([add(el, (-4, -6)), add(el, (5, 4))], c(CRACK), 0.9)

    if p["smear"]:
        a0, a1, al = p["smear"]
        S = Layer(BW, BH)
        R = 26 + 28 + 60
        pts = smear(sh, R, a0, a1, 30)
        S.poly(pts, c((255, 190, 120), 110 * al))
        S.poly(smear(sh, R, a0, a1, 10), c((255, 235, 200), 200 * al))
        B.img.alpha_composite(S.img.filter(ImageFilter.GaussianBlur(1.5 * SS)))

    if return_layer:
        return B, G
    base = B.result()
    base = silhouette_outline(base)
    g = G.result()
    if p["eye"] > 0:
        base = Image.alpha_composite(base, glow(g, 2.5, 1.5))
    return base


def mix_col(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def smear(center, R, a_from, a_to, thick, n=28):
    outer, inner = [], []
    for i in range(n + 1):
        t = i / n
        a = math.radians(a_from + (a_to - a_from) * t)
        th = thick * (t ** 1.3)
        outer.append((center[0] + R * math.cos(a), center[1] + R * math.sin(a)))
        inner.append((center[0] + (R - th) * math.cos(a), center[1] + (R - th) * math.sin(a)))
    return outer + inner[::-1]


def balbal_anims():
    A = {}
    A["idle"] = [balbal_render(dict(lean=1.5 * math.sin(2 * math.pi * i / 4), mace=70 + 2 * math.sin(2 * math.pi * i / 4)))
                 for i in range(4)]
    walk = []
    for i in range(8):
        ph = 2 * math.pi * i / 8
        walk.append(balbal_render(dict(lean=5 * math.sin(ph), lleg=18 * math.sin(ph), rleg=-18 * math.sin(ph),
                                       dy=-3 * abs(math.cos(ph)), arm=18 + 6 * math.sin(ph), mace=70 + 5 * math.sin(ph))))
    A["walk"] = walk
    A["attack"] = [balbal_render(x) for x in [
        dict(lean=-3, arm=60, elbow=30, mace=-10, eye=0.3),
        dict(lean=-6, arm=130, elbow=20, mace=-110, eye=0.7),
        dict(lean=-9, arm=168, elbow=10, mace=-150, eye=1.0, dy=-2),
        dict(lean=-11, arm=172, elbow=8, mace=-158, eye=1.0, dy=-3),
        dict(lean=12, arm=70, elbow=0, mace=20, eye=1.0, smear=(-160, 20, 1.0), lleg=20, rleg=-14),
        dict(lean=16, arm=48, elbow=0, mace=72, eye=0.8, dy=4, smear=(-40, 72, 0.5), lleg=22, rleg=-16),
        dict(lean=8, arm=32, elbow=16, mace=74, eye=0.4, dy=2),
        dict(lean=2, arm=22, elbow=26, mace=72, eye=0.1),
    ]]
    A["hurt"] = [balbal_render(dict(lean=-10, dx=-3, arm=10, mace=80)), balbal_render(dict(lean=-5, dx=-1, arm=14, mace=76))]
    A["stun"] = [balbal_render(dict(lean=-8 + 3 * math.sin(i * math.pi / 2), arm=4, elbow=10, mace=95, dx=-2)) for i in range(4)]
    A["death"] = crumble(balbal_render(dict(lean=-6, arm=10, mace=85)), seed=11, frames=9, ground=BGROUND)
    return A


def crumble(img, seed, frames, ground, pieces=26):
    """Раскалывание статуи на куски: вороной-разбиение альфа-маски."""
    arr = np.array(img)
    h, w = arr.shape[:2]
    alpha = arr[..., 3] > 20
    ys, xs = np.nonzero(alpha)
    rnd = np.random.default_rng(seed)
    idx = rnd.choice(len(xs), size=pieces, replace=False)
    seeds = np.stack([xs[idx], ys[idx]], axis=1).astype(np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    d = (xx[None] - seeds[:, 0, None, None]) ** 2 + (yy[None] - seeds[:, 1, None, None]) ** 2
    lab = np.argmin(d, axis=0)
    parts = []
    for k in range(pieces):
        m = (lab == k) & alpha
        if m.sum() < 5:
            continue
        ys_k, xs_k = np.nonzero(m)
        x0, x1, y0, y1 = xs_k.min(), xs_k.max() + 1, ys_k.min(), ys_k.max() + 1
        sub = arr[y0:y1, x0:x1].copy()
        sub[..., 3] = np.where(m[y0:y1, x0:x1], sub[..., 3], 0)
        # тёмная кромка скола
        part = Image.fromarray(sub, "RGBA")
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        vx = (cx - w / 2) * 0.06 + rnd.uniform(-2.5, 2.5)
        vy = rnd.uniform(-5, -1)
        spin = rnd.uniform(-25, 25)
        parts.append((part, cx, cy, vx, vy, spin, y1 - y0))
    out = []
    for f in range(frames):
        canvas = Image.new("RGBA", (w, h))
        t = f
        for part, cx, cy, vx, vy, spin, ph in parts:
            x = cx + vx * t * 1.6
            y = cy + vy * t * 1.6 + 1.6 * t * t * 1.4
            if y > ground - ph * 0.3:
                y = ground - ph * 0.3
            im = part.rotate(spin * t * 0.6, Image.BICUBIC, expand=True)
            alpha_k = 1.0 if f < frames - 3 else (frames - f) / 4
            if alpha_k < 1:
                a = im.split()[3].point(lambda v: int(v * alpha_k))
                im.putalpha(a)
            canvas.alpha_composite(im, (int(x - im.width / 2), int(y - im.height / 2)))
        out.append(canvas)
    return out


# =============================================================== ДУХ СТЕПИ
SW, SH, SCX = 192, 192, 96
GHOST = (206, 226, 255)
GHOST_DK = (120, 140, 200)
HOOD = (24, 26, 52)


def spirit_render(ph=0.0, lean=0.0, stretch=1.0, arms=0.0, eye=(255, 236, 150), fade=1.0, expand=1.0, dy=0.0):
    B = Layer(SW, SH)
    cx, cy = SCX, 74 + dy
    # хвост — волнистая лента назад-вниз
    tail_l, tail_r = [], []
    n = 22
    for i in range(n + 1):
        t = i / n
        x = cx - 6 - t * 70 * stretch * expand
        y = cy + 28 + t * 62 + math.sin(ph + t * 5.5) * 9 * t
        wdt = (24 * (1 - t) ** 1.2 + 1.5) * expand
        tail_l.append((x, y - wdt))
        tail_r.append((x, y + wdt))
    body_pts = tail_l + tail_r[::-1]
    body_l = Layer(SW, SH)
    body_l.poly(body_pts, c(GHOST_DK, 170 * fade))
    # туловище-капюшон
    hood = []
    for a in range(0, 361, 10):
        r = 27 * expand
        hood.append(add((cx, cy), rot((r * math.cos(math.radians(a)) * 0.95, r * math.sin(math.radians(a)) * 1.15), lean)))
    body_l.poly(hood, c(GHOST, 215 * fade))
    body_l.poly([add((cx, cy), rot(q, lean)) for q in [(-26, 6), (18, 18), (0, 40), (-30, 30)]], c(GHOST, 200 * fade))
    # руки-когти
    for side, k in ((-1, 0.7), (1, 1.0)):
        sh = add((cx, cy), rot((4 + side * 4, 16), lean))
        reach = 26 + 22 * arms
        hand = add(sh, rot((reach, 6 - 10 * arms + side * 4), lean))
        mid = lerp_pt(sh, hand, 0.5)
        mid = (mid[0], mid[1] + 8 - arms * 10)
        arm = bezier(sh, mid, hand, 10)
        body_l.line(arm, c(shade(GHOST, k), 200 * fade), 5 * expand)
        for j in (-1, 0, 1):
            tip = add(hand, rot((10, j * 5), lean - 10 * arms))
            body_l.line([hand, tip], c(shade(GHOST, k * 1.05), 220 * fade), 2)
    soft = body_l.img.filter(ImageFilter.GaussianBlur(2.2 * SS))
    B.img.alpha_composite(soft)
    B.img.alpha_composite(body_l.img.filter(ImageFilter.GaussianBlur(0.6 * SS)))
    # тёмное «лицо» под капюшоном и глаза
    face_c = add((cx, cy), rot((8, -2), lean))
    B.poly([add(face_c, rot(q, lean)) for q in ellipse_pts(0, 0, 13 * expand, 16 * expand, 0, 30)], c(HOOD, 235 * fade))
    G = Layer(SW, SH)
    for ex in (6, -4):
        e = add(face_c, rot((ex, -2), lean))
        G.ellipse(e[0], e[1], 3.2, 2.0, fill=c(eye, 255 * fade))
        B.ellipse(e[0], e[1], 2.2, 1.4, fill=c((255, 255, 255), 255 * fade))
    # бледный орнамент на груди
    oc = add((cx, cy), rot((-2, 14), lean))
    draw_ram_horn(B, oc[0], oc[1], 11, c((150, 170, 230), 160 * fade), 1.2, lean)
    base = B.result()
    g = G.result()
    base = Image.alpha_composite(base, glow(g, 3, 1.6))
    return base


def spirit_anims():
    A = {}
    A["float"] = [spirit_render(ph=2 * math.pi * i / 6, dy=2.5 * math.sin(2 * math.pi * i / 6)) for i in range(6)]
    red = (255, 80, 60)
    A["attack"] = [
        spirit_render(ph=0.0, lean=-14, arms=0.6, eye=red, dy=-3),
        spirit_render(ph=0.8, lean=-20, arms=1.0, eye=red, dy=-5),
        spirit_render(ph=1.6, lean=16, stretch=1.6, arms=1.0, eye=red, dy=2),
        spirit_render(ph=2.4, lean=18, stretch=1.7, arms=0.9, eye=red, dy=3),
        spirit_render(ph=3.2, lean=6, stretch=1.2, arms=0.3, eye=red),
        spirit_render(ph=4.0, lean=0, arms=0.0),
    ]
    A["hurt"] = [spirit_render(ph=1.0, lean=-18, fade=0.75), spirit_render(ph=1.5, lean=-10, fade=0.9)]
    A["stun"] = [spirit_render(ph=i, lean=-12 + 4 * math.sin(i * 1.5), fade=0.8, dy=4) for i in range(4)]
    A["death"] = [spirit_render(ph=i * 0.7, lean=-10, expand=1.0 + i * 0.12, fade=max(0.0, 1 - i / 6.5)) for i in range(7)]
    return A


# =============================================================== ЖЕЗТЫРНАК
ZW, ZH, ZCX, ZGROUND = 320, 320, 160, 306
ROBE = (118, 26, 38)
ROBE_DK = (62, 14, 24)
ROBE_LT = (156, 44, 52)
ZSKIN = (196, 196, 178)
ZSKIN_SH = (150, 152, 140)
ZHAIR = (16, 16, 26)
COPPER = (214, 124, 60)
COPPER_LT = (255, 190, 120)
ZGOLD = (214, 164, 80)

Z_DEFAULT = dict(dx=0, dy=0, lean=6, head=-4, fsh=20, fel=30, bsh=-16, bel=30, sway=0.0, hair=0.0,
                 eye=0.6, smear=None, crouch=0.0, claw=0.0, orb=0.0, hem_lift=0.0)


def zhest_render(pose):
    p = dict(Z_DEFAULT)
    p.update(pose)
    B = Layer(ZW, ZH)
    G = Layer(ZW, ZH)
    waist = (ZCX + p["dx"], ZGROUND - 104 + p["dy"] + p["crouch"])
    t = p["lean"]
    up = limb_dir(180 - t, 1)
    fw = (math.cos(math.radians(t)), math.sin(math.radians(t)))

    def L(lx, ly):
        return (waist[0] + fw[0] * lx + up[0] * ly, waist[1] + fw[1] * lx + up[1] * ly)

    neck = L(3, 70)
    hc = add(neck, limb_dir(180 - (t + p["head"]), 20))
    hp = lambda q: add(hc, rot(q, t + p["head"]))

    # волосы — длинные, развеваются за спиной
    hair = [hp((-6, -20)), hp((6, -21)), hp((14, -12))]
    for i in range(12):
        k = i / 11
        x = -16 - 70 * k - 10 * math.sin(p["hair"] + k * 3)
        y = -10 + 120 * k + 12 * math.sin(p["hair"] * 0.7 + k * 4)
        hair.append(hp((x, y)) if False else add(hc, (x, y)))
    for i in range(12):
        k = 1 - i / 11
        x = -6 - 46 * k - 8 * math.sin(p["hair"] + 1 + k * 3)
        y = 10 + 100 * k + 8 * math.sin(p["hair"] * 0.7 + 1 + k * 4)
        hair.append(add(hc, (x, y)))
    B.poly(hair, c(ZHAIR), c((4, 4, 8)), 1)
    for i in range(4):
        k0 = 0.2 + i * 0.18
        s = bezier(add(hc, (-10, 0)), add(hc, (-40 - i * 8, 40 + i * 10 + 10 * math.sin(p["hair"] + i))),
                   add(hc, (-50 - i * 10 - 8 * math.sin(p["hair"] + i), 90 + i * 8)), 10)
        B.line(s, c((44, 44, 64)), 1)

    def arm(side, dark):
        k = 0.7 if dark else 1.0
        sh = L(-4 if dark else 4, 62)
        el = add(sh, limb_dir(p[side + "sh"], 34))
        hand = add(el, limb_dir(p[side + "sh"] + p[side + "el"], 32))
        B.poly(capsule(sh, el, 7.5, 6), c(shade(ROBE, k)), c(shade(ROBE_DK, k)), 1)
        B.poly(capsule(el, hand, 5.5, 4.2), c(shade(ZSKIN, k)), c(shade(ZSKIN_SH, k * 0.6)), 0.9)
        # рукав-раструб
        cuff = lerp_pt(el, hand, 0.15)
        B.poly(capsule(el, cuff, 9, 10), c(shade(ROBE_LT, k)), c(shade(ROBE_DK, k)), 0.9)
        B.circle(hand, 5, c(shade(ZSKIN, k)), c(shade(ZSKIN_SH, 0.5)), 0.9)
        # медные когти
        fang = math.degrees(math.atan2(hand[1] - el[1], hand[0] - el[0]))
        for j in range(4):
            a = fang + (-18 + j * 12) * (1 + p["claw"] * 0.6)
            ln = 30 + j % 2 * 4
            base = add(hand, (math.cos(math.radians(a)) * 3, math.sin(math.radians(a)) * 3))
            tip = add(hand, (math.cos(math.radians(a)) * ln, math.sin(math.radians(a)) * ln))
            mid = lerp_pt(base, tip, 0.55)
            n = (-math.sin(math.radians(a)), math.cos(math.radians(a)))
            mid = add(mid, (n[0] * 3, n[1] * 3))
            pts = bezier(base, mid, tip, 8)
            B.line(pts, c(shade(COPPER, k)), 2.6)
            B.line(pts[2:], c(shade(COPPER_LT, k)), 0.9)
            if not dark:
                G.line(pts, c(COPPER, 110), 2.4)
        return hand

    arm("b", True)

    # мантия — колокол от талии до земли с рваным подолом
    hem_y = ZGROUND - 2 - p["hem_lift"]
    sw = p["sway"]
    robe = [L(-15, 4), L(16, 4)]
    n = 14
    for i in range(n + 1):
        k = i / n
        x = waist[0] + 46 - k * 96 + sw * (1 - abs(k - 0.5) * 2) * 8 + sw * 6
        y = hem_y - (6 if i % 2 else 0) - abs(math.sin(i * 1.7)) * 4
        robe.append((x, y))
    B.poly(robe, c(ROBE), c(ROBE_DK), 1.2)
    # складки и тень
    for k in (0.25, 0.5, 0.75):
        top = lerp_pt(L(-15, 4), L(16, 4), k)
        bot = (waist[0] + 46 - (1 - k) * 96 + sw * 6, hem_y - 4)
        B.line([top, lerp_pt(top, bot, 0.5), bot], c(ROBE_DK), 1.4)
    B.poly([L(-15, 4), L(-4, 4), (waist[0] - 22 + sw * 6, hem_y - 3), (waist[0] - 50 + sw * 6, hem_y - 3)],
           c(shade(ROBE, 0.75)))
    # золотая кайма с орнаментом
    hem = [(waist[0] + 46 - k * 96 + sw * 6, hem_y - 12) for k in (0, 1)]
    B.line(hem, c(ZGOLD), 2.4)
    for i in range(5):
        x = waist[0] + 34 - i * 20 + sw * 6
        draw_ram_horn(B, x, hem_y - 24, 11, c(ZGOLD), 1.3)

    # торс
    torso = [L(*q) for q in [(-15, 0), (15, 0), (16, 24), (14, 50), (9, 66), (-8, 68), (-16, 56), (-17, 26)]]
    B.poly(torso, c(ROBE), c(ROBE_DK), 1.2)
    B.poly([L(*q) for q in [(-4, 0), (10, 0), (11, 48), (2, 64), (-4, 50)]], c(ROBE_DK))
    B.line([L(-12, 4), L(14, 4)], c(ZGOLD), 3)
    B.line([L(-7, 66), L(9, 64)], c(COPPER), 2.4)
    # медальон
    B.circle(L(4, 44), 4.5, c(COPPER), c(shade(COPPER, 0.5)), 0.8)

    # голова
    B.poly(capsule(L(3, 66), hp((0, 10)), 4.5, 4.5), c(ZSKIN_SH))
    face = [hp(q) for q in [(-12, -14), (2, -20), (12, -12), (15, -2), (18, 4), (14, 8), (13, 14), (6, 22), (-4, 18), (-12, 6)]]
    B.poly(face, c(ZSKIN), c(shade(ZSKIN, 0.45)), 1)
    B.poly([hp(q) for q in [(-12, -14), (-2, -12), (-4, 10), (-4, 18), (-12, 6)]], c(ZSKIN_SH))
    # глаза и рот
    ecol = (255, int(160 + 60 * p["eye"]), 60)
    B.poly([hp(q) for q in [(5, -4), (12, -5), (10, -1), (5, -1)]], c((30, 10, 10)))
    G.poly([hp(q) for q in ellipse_pts(8.5, -3, 5, 2.5, -8, 12)], c(ecol, 120 + 135 * p["eye"]))
    B.ellipse(*hp((9, -3)), 1.6, 1.1, fill=c(ecol))
    B.line([hp((7, 13)), hp((13, 12))], c((90, 20, 30)), 1.4)
    B.line([hp((4, -9)), hp((13, -8))], c(ZHAIR), 1.4)
    # головной убор — тёмный платок и медные подвески
    scarf = [hp(q) for q in [(-14, -10), (-10, -21), (4, -24), (14, -15), (6, -15), (-4, -12), (-8, 4), (-16, 10)]]
    B.poly(scarf, c(ZHAIR), c((4, 4, 8)), 1)
    for k in range(3):
        q = hp((-2 + k * 6, -17 + k))
        B.line([q, add(q, (0, 7))], c(COPPER), 1)
        B.circle(add(q, (0, 8)), 1.4, c(COPPER_LT))

    hand_f = arm("f", False)
    if p["orb"] > 0:
        oc = L(10, 120)
        O = Layer(ZW, ZH)
        O.circle(oc, 20 * p["orb"], c((190, 70, 255), 160))
        O.circle(oc, 9 * p["orb"], c((255, 220, 255), 230))
        G.img.alpha_composite(O.img)
    if p["smear"]:
        a0, a1, al, cen = p["smear"]
        S = Layer(ZW, ZH)
        sc = L(*cen)
        S.poly(smear(sc, 92, a0, a1, 34), c((255, 120, 70), 120 * al))
        S.poly(smear(sc, 92, a0, a1, 12), c((255, 220, 170), 210 * al))
        G.img.alpha_composite(S.img.filter(ImageFilter.GaussianBlur(1.4 * SS)))

    base = B.result()
    base = silhouette_outline(base)
    g = G.result()
    return Image.alpha_composite(base, glow(g, 3, 1.4))


def zhest_anims():
    A = {}
    A["idle"] = [zhest_render(dict(sway=math.sin(2 * math.pi * i / 6), hair=2 * math.pi * i / 6,
                                   fsh=20 + 3 * math.sin(2 * math.pi * i / 6), claw=0.3 + 0.3 * math.sin(2 * math.pi * i / 6)))
                 for i in range(6)]
    A["walk"] = [zhest_render(dict(sway=1.6 * math.sin(2 * math.pi * i / 8), hair=2 * math.pi * i / 8, lean=12,
                                   dy=-3 * abs(math.sin(2 * math.pi * i / 8)), fsh=30 - 15 * math.sin(2 * math.pi * i / 8),
                                   bsh=-10 + 15 * math.sin(2 * math.pi * i / 8), fel=40))
                 for i in range(8)]
    A["attack"] = [zhest_render(x) for x in [
        dict(lean=-4, fsh=140, fel=40, bsh=-30, eye=0.8, claw=0.6, hair=0.3),
        dict(lean=-8, fsh=170, fel=30, bsh=-36, eye=1.0, claw=1.0, hair=0.6),
        dict(lean=-10, fsh=178, fel=26, bsh=-40, eye=1.0, claw=1.0, hair=0.9, sway=-1),
        dict(lean=20, fsh=80, fel=0, bsh=-20, eye=1.0, claw=1.0, hair=1.4, sway=1.5, smear=(-150, 30, 1.0, (4, 62))),
        dict(lean=24, fsh=40, fel=10, bsh=40, bel=10, eye=1.0, claw=0.8, hair=1.8, sway=2, smear=(-30, 50, 0.4, (4, 62))),
        dict(lean=18, fsh=30, fel=20, bsh=120, bel=0, eye=1.0, claw=1.0, hair=2.2, sway=1.5, smear=(110, -40, 1.0, (-4, 62))),
        dict(lean=10, fsh=24, fel=30, bsh=150, bel=10, eye=0.8, hair=2.6, sway=0.5, smear=(40, -80, 0.4, (-4, 62))),
        dict(lean=6, fsh=20, fel=30, bsh=-10, bel=30, eye=0.6, hair=3.0),
    ]]
    A["leap"] = [zhest_render(x) for x in [
        dict(lean=24, crouch=14, fsh=-40, fel=20, bsh=-50, eye=1.0, claw=0.8, hair=0.5),
        dict(lean=28, crouch=20, fsh=-60, fel=10, bsh=-70, eye=1.0, claw=1.0, hair=0.8),
        dict(lean=34, dy=-30, fsh=95, fel=-10, bsh=80, bel=0, eye=1.0, claw=1.0, hair=2.0, hem_lift=28, sway=-3),
        dict(lean=30, dy=-28, fsh=100, fel=-10, bsh=88, bel=0, eye=1.0, claw=1.0, hair=2.6, hem_lift=26, sway=-3),
        dict(lean=30, crouch=22, fsh=60, fel=10, bsh=50, eye=1.0, claw=0.7, hair=3.2, sway=2),
        dict(lean=14, crouch=8, fsh=30, fel=30, bsh=-10, eye=0.8, hair=3.8, sway=1),
    ]]
    A["summon"] = [zhest_render(dict(lean=-6, fsh=150 + 6 * math.sin(i), fel=-20, bsh=140, bel=-20,
                                     orb=min(1.0, 0.3 + i * 0.2), eye=1.0, hair=i * 0.6, sway=math.sin(i)))
                   for i in range(6)]
    A["hurt"] = [zhest_render(dict(lean=-14, head=-12, dx=-4, fsh=-20, bsh=-40, eye=1.0, hair=1)),
                 zhest_render(dict(lean=-8, head=-6, dx=-2, fsh=0, bsh=-30, eye=0.9, hair=1.4))]
    A["stun"] = [zhest_render(dict(lean=-10 + 3 * math.sin(i * 1.6), head=-10, fsh=-10, bsh=-30, eye=0.3, hair=i, crouch=6))
                 for i in range(4)]
    death = []
    for i in range(8):
        k = i / 7
        im = zhest_render(dict(lean=-10 + 40 * k, head=10 * k, crouch=40 * k, fsh=10, bsh=-10, eye=1 - k, hair=i * 0.5,
                               sway=-2 * k))
        if k > 0.45:
            a = im.split()[3].point(lambda v, kk=k: int(v * (1 - (kk - 0.45) / 0.55)))
            im.putalpha(a)
        death.append(im)
    A["death"] = death
    return A
