"""Общие утилиты для процедурной генерации спрайтов (PIL).

Всё рисуется с суперсэмплингом (SS) и потом уменьшается — так получаются
сглаженные края без ручного антиалиасинга.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageChops

SS = 3
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "assets")

OUTLINE = (18, 12, 16, 255)


def c(rgb, a=255):
    return (int(rgb[0]), int(rgb[1]), int(rgb[2]), int(a))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def shade(rgb, k):
    """k < 1 — темнее, k > 1 — светлее."""
    if k <= 1:
        return tuple(max(0, int(v * k)) for v in rgb[:3])
    return tuple(min(255, int(v + (255 - v) * (k - 1))) for v in rgb[:3])


def rot(p, ang_deg, center=(0, 0)):
    a = math.radians(ang_deg)
    x, y = p[0] - center[0], p[1] - center[1]
    return (center[0] + x * math.cos(a) - y * math.sin(a), center[1] + x * math.sin(a) + y * math.cos(a))


def limb_dir(ang_deg, length):
    """Угол конечности: 0 — вниз, плюс — вперёд (+x)."""
    a = math.radians(ang_deg)
    return (math.sin(a) * length, math.cos(a) * length)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def lerp_pt(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def capsule(a, b, ra, rb, n=10):
    ax, ay = a
    bx, by = b
    ang = math.atan2(by - ay, bx - ax)
    pts = []
    for i in range(n + 1):
        t = ang - math.pi / 2 + math.pi * i / n
        pts.append((bx + rb * math.cos(t), by + rb * math.sin(t)))
    for i in range(n + 1):
        t = ang + math.pi / 2 + math.pi * i / n
        pts.append((ax + ra * math.cos(t), ay + ra * math.sin(t)))
    return pts


def ellipse_pts(cx, cy, rx, ry, ang=0, n=36, a0=0, a1=360):
    pts = []
    for i in range(n + 1):
        t = math.radians(a0 + (a1 - a0) * i / n)
        p = (rx * math.cos(t), ry * math.sin(t))
        p = rot(p, ang)
        pts.append((cx + p[0], cy + p[1]))
    return pts


def bezier(p0, p1, p2, n=16):
    pts = []
    for i in range(n + 1):
        t = i / n
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


class Layer:
    """Холст в «логических» пикселях; внутри — в SS раз больше."""

    def __init__(self, w, h, ss=SS):
        self.w, self.h, self.ss = w, h, ss
        self.img = Image.new("RGBA", (int(w * ss), int(h * ss)), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def P(self, pts):
        s = self.ss
        return [(x * s, y * s) for x, y in pts]

    def poly(self, pts, fill=None, outline=None, width=1.0):
        if len(pts) < 3:
            return
        self.d.polygon(self.P(pts), fill=fill)
        if outline is not None:
            pp = self.P(pts)
            self.d.line(pp + [pp[0]], fill=outline, width=max(1, int(width * self.ss)), joint="curve")

    def circle(self, cxy, r, fill=None, outline=None, width=1.0):
        s = self.ss
        x, y = cxy
        box = [(x - r) * s, (y - r) * s, (x + r) * s, (y + r) * s]
        self.d.ellipse(box, fill=fill, outline=outline, width=max(1, int(width * s)) if outline else 0)

    def ellipse(self, cx, cy, rx, ry, fill=None, outline=None, width=1.0, ang=0):
        self.poly(ellipse_pts(cx, cy, rx, ry, ang, n=48), fill, outline, width)

    def line(self, pts, fill, width=1.0):
        if len(pts) < 2:
            return
        self.d.line(self.P(pts), fill=fill, width=max(1, int(width * self.ss)), joint="curve")
        # скруглённые концы
        r = width / 2
        if width * self.ss >= 3:
            for p in (pts[0], pts[-1]):
                self.circle(p, r * 0.95, fill=fill)

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1.0):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, outline, width)

    def result(self):
        return self.img.resize((int(self.w), int(self.h)), Image.LANCZOS)


def silhouette_outline(img, color=OUTLINE, grow=3):
    """Тёмный контур по силуэту (как в рисованных играх)."""
    a = img.split()[3]
    a2 = a.point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(grow))
    base = Image.new("RGBA", img.size, color[:3] + (0,))
    base.putalpha(a2)
    return Image.alpha_composite(base, img)


def glow(img, radius, strength=1.0):
    """Мягкое свечение: размытая копия, сложенная с оригиналом."""
    blurred = img.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        r, g, b, a = blurred.split()
        a = a.point(lambda v: min(255, int(v * strength)))
        blurred = Image.merge("RGBA", (r, g, b, a))
    return Image.alpha_composite(blurred, img)


def additive(base, top):
    """Аддитивное наложение RGBA top на base (для огня/свечения)."""
    br, bg, bb, ba = base.split()
    tr, tg, tb, ta = top.split()
    k = ta.point(lambda v: v / 255.0 * 255)
    r = ImageChops.add(br, ImageChops.multiply(tr, k))
    g = ImageChops.add(bg, ImageChops.multiply(tg, k))
    b = ImageChops.add(bb, ImageChops.multiply(tb, k))
    a = ImageChops.lighter(ba, ta)
    return Image.merge("RGBA", (r, g, b, a))


def save(img, rel):
    path = os.path.join(ASSETS, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


def strip(frames):
    w, h = frames[0].size
    out = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.paste(f, (i * w, 0))
    return out


# ---------------------------------------------------------------- орнамент
def ram_horn_paths(cx, cy, size, ang=0.0, turns=1.15, mirror_only=None):
    """Казахский орнамент «қошқар мүйіз» — пара бараньих рогов.

    Возвращает список полилиний (каждая — список точек).
    """
    s = size
    paths = []
    sides = (-1, 1) if mirror_only is None else (mirror_only,)
    for side in sides:
        center = (0.42 * s * side, -0.5 * s)
        pts = []
        start = math.atan2(0.32 * s, -0.42 * s * side)  # направление на основание
        n = 28
        for i in range(n + 1):
            t = i / n
            r = 0.36 * s * (1 - 0.82 * t)
            th = start + side * t * turns * 2 * math.pi
            pts.append((center[0] + r * math.cos(th), center[1] + r * math.sin(th)))
        pts.insert(0, (0, -0.12 * s))
        paths.append(pts)
    paths.append([(0, 0.35 * s), (0, -0.12 * s)])
    out = []
    for p in paths:
        out.append([add((cx, cy), rot(q, ang)) for q in p])
    return out


def draw_ram_horn(layer, cx, cy, size, color, width, ang=0.0, turns=1.15):
    for p in ram_horn_paths(cx, cy, size, ang, turns):
        layer.line(p, color, width)


def diamond(cx, cy, rx, ry):
    return [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]


def stepped_diamond(cx, cy, r, steps=3):
    """Ступенчатый ромб — типичный элемент сырмака/текемета."""
    pts = []
    st = r / steps
    # верх -> право
    for i in range(steps):
        pts += [(cx + i * st, cy - r + i * st), (cx + (i + 1) * st, cy - r + i * st)]
    for i in range(steps):
        pts += [(cx + r - i * st, cy + i * st), (cx + r - i * st, cy + (i + 1) * st)]
    for i in range(steps):
        pts += [(cx - i * st, cy + r - i * st), (cx - (i + 1) * st, cy + r - i * st)]
    for i in range(steps):
        pts += [(cx - r + i * st, cy - i * st), (cx - r + i * st, cy - (i + 1) * st)]
    return pts


def noise_speckle(layer, x0, y0, x1, y1, count, colors, rmin, rmax, seed):
    rnd = random.Random(seed)
    for _ in range(count):
        x = rnd.uniform(x0, x1)
        y = rnd.uniform(y0, y1)
        r = rnd.uniform(rmin, rmax)
        layer.circle((x, y), r, fill=rnd.choice(colors))


def vertical_gradient(w, h, stops):
    """stops: [(t, (r,g,b)), ...]"""
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                k = (t - stops[i][0]) / max(1e-6, stops[i + 1][0] - stops[i][0])
                col = mix(stops[i][1], stops[i + 1][1], k)
                break
        else:
            col = stops[-1][1]
        for x in range(w):
            px[x, y] = (col[0], col[1], col[2], 255)
    return img


def radial(size, inner, outer, power=1.6):
    """Круглый градиент от inner (центр) к outer (край), RGBA."""
    import numpy as np

    h = w = size
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.sqrt((xx - w / 2 + 0.5) ** 2 + (yy - h / 2 + 0.5) ** 2) / (w / 2)
    t = np.clip(d, 0, 1) ** (1 / power)
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for i in range(4):
        arr[..., i] = inner[i] + (outer[i] - inner[i]) * t
    return Image.fromarray(arr.clip(0, 255).astype("uint8"), "RGBA")
