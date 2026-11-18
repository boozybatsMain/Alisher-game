#!/usr/bin/env python3
"""Синтез сэмплов домбры (модуль E, Хаб «Тамыр»).

Karplus-Strong щипковой струны + яркая атака (шум щипка через гребёнку «точки щипка»)
+ деревянный корпус (несколько резонансных биквадов) + лёгкий «жужжащий» призвук.
Строй: нижняя струна D3, верхняя G3 (кварта). 7 положений: открытая + 6 ладов
казахского звукоряда (полутоны 0, 2, 3, 5, 7, 9, 10 от открытой).

Выход: assets/sfx/dombra/upper_0..6.wav, lower_0..6.wav — моно 44.1 кГц 16 бит, ~2.5 с.
Запуск: python3 tools/make_dombra.py   (numpy желателен, без него — медленнее, на чистом python)
"""
import math
import os
import random
import struct
import wave

SR = 44100
DUR = 2.5
SEMITONES = [0, 2, 3, 5, 7, 9, 10]
STRINGS = {"lower": 146.832, "upper": 195.998}  # D3, G3
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx", "dombra")

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None


# ------------------------------------------------------------------ общие фильтры
def biquad_coefs(kind, f0, q, gain_db=0.0):
    w0 = 2 * math.pi * f0 / SR
    alpha = math.sin(w0) / (2 * q)
    cw = math.cos(w0)
    if kind == "bp":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    else:  # hp
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    return [x / a[0] for x in b], [1.0, a[1] / a[0], a[2] / a[0]]


def biquad(x, kind, f0, q):
    b, a = biquad_coefs(kind, f0, q)
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    _, a1, a2 = a
    for i, xi in enumerate(x):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        y[i] = yi
    return y


# ------------------------------------------------------------------ Karplus-Strong
def ks_string(freq, seconds, brightness, decay_s, rnd):
    """Возвращает список сэмплов. Целая длина задержки, затем передискретизация к точной высоте."""
    n_total = int(SR * seconds) + 2
    period = SR / freq - 0.5          # усреднение даёт задержку в полсэмпла
    N = max(2, int(period))
    # потеря энергии за период так, чтобы громкость падала в e раз за decay_s
    loss = math.exp(-1.0 / (freq * decay_s))
    # возбуждение: шум, сглаженный под «яркость», и гребёнка точки щипка (ближе к подставке — ярче)
    noise = [rnd.uniform(-1, 1) for _ in range(N)]
    sm = brightness
    exc = []
    prev = 0.0
    for v in noise:
        prev = prev + sm * (v - prev)
        exc.append(prev)
    pick = max(1, int(N * 0.13))
    exc = [exc[i] - 0.6 * exc[i - pick] for i in range(N)]
    m = max(abs(v) for v in exc) or 1.0
    exc = [v / m for v in exc]
    # сколько сэмплов нужно до передискретизации
    ratio = (N + 0.5) / (period + 0.5)  # >1: сгенерированное ниже нужного — ускорим
    need = int(n_total * ratio) + N + 4
    if np is not None:
        buf = np.zeros(need)
        buf[:N] = exc
        k = N
        while k < need:
            end = min(k + N, need)
            seg = buf[k - N:end - N]
            prev = buf[k - N - 1:end - N - 1] if k - N - 1 >= 0 else np.concatenate(([0.0], buf[k - N:end - N - 1]))
            buf[k:end] = loss * 0.5 * (seg + prev) * 1.0
            # лёгкая «нелинейность» ладов: чуть ярче держится
            k = end
        t_src = np.arange(n_total) * ratio
        out = np.interp(t_src, np.arange(need), buf)
        return out.tolist()
    buf = exc + [0.0] * (need - N)
    for i in range(N, need):
        buf[i] = loss * 0.5 * (buf[i - N] + buf[i - N - 1])
    out = []
    for j in range(n_total):
        t = j * ratio
        i0 = int(t)
        f = t - i0
        out.append(buf[i0] * (1 - f) + buf[min(i0 + 1, need - 1)] * f)
    return out


def body(x):
    """Деревянный корпус: резонансы ~ 210, 420, 1150, 2700 Гц + исходный сигнал, срез сверху."""
    if np is not None:
        xa = np.array(x)
        mix = 0.55 * xa
        for f0, q, g in ((210, 6, 0.55), (420, 5, 0.45), (1150, 3.5, 0.35), (2700, 3, 0.18)):
            mix = mix + g * np.array(biquad(x, "bp", f0, q))
        mix = np.array(biquad(mix.tolist(), "lp", 6200, 0.7))
        mix = np.array(biquad(mix.tolist(), "hp", 70, 0.7))
        return mix.tolist()
    mix = [0.55 * v for v in x]
    for f0, q, g in ((210, 6, 0.55), (420, 5, 0.45), (1150, 3.5, 0.35), (2700, 3, 0.18)):
        y = biquad(x, "bp", f0, q)
        mix = [m + g * v for m, v in zip(mix, y)]
    mix = biquad(mix, "lp", 6200, 0.7)
    return biquad(mix, "hp", 70, 0.7)


def attack_click(n, rnd):
    """Короткий щелчок ногтя/медиатора по струне — яркая атака."""
    out = [0.0] * n
    L = int(SR * 0.012)
    for i in range(min(L, n)):
        env = math.exp(-i / (SR * 0.0025))
        out[i] = rnd.uniform(-1, 1) * env
    return biquad(out, "hp", 2200, 0.8)


def make_note(freq, seed):
    rnd = random.Random(seed)
    n = int(SR * DUR)
    s = ks_string(freq, DUR, brightness=0.55, decay_s=0.85 + 120.0 / freq, rnd=rnd)[:n]
    # второй слабый голос — расстроенный на +3 цента (струна «живёт»)
    s2 = ks_string(freq * 1.0017, DUR, brightness=0.35, decay_s=0.7 + 100.0 / freq, rnd=rnd)[:n]
    raw = [a + 0.35 * b for a, b in zip(s, s2)]
    sig = body(raw)
    click = attack_click(n, rnd)
    sig = [v + 0.18 * c for v, c in zip(sig, click)]
    # огибающая: мягкий вход 1.5 мс, естественный хвост и плавный уход в 0 в последние 0.3 с
    a_len = int(SR * 0.0015)
    f_len = int(SR * 0.3)
    for i in range(n):
        g = 1.0
        if i < a_len:
            g = i / a_len
        if i > n - f_len:
            g *= max(0.0, (n - i) / f_len) ** 1.5
        sig[i] *= g
    peak = max(abs(v) for v in sig) or 1.0
    return [v / peak * 0.82 for v in sig]


def write_wav(path, data):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in data)
        w.writeframes(frames)


def main():
    os.makedirs(OUT, exist_ok=True)
    seed = 1
    for name, base in STRINGS.items():
        for i, st in enumerate(SEMITONES):
            f = base * 2 ** (st / 12.0)
            data = make_note(f, seed)
            seed += 1
            path = os.path.join(OUT, "%s_%d.wav" % (name, i))
            write_wav(path, data)
            print("%-10s %7.2f Hz -> %s" % ("%s_%d" % (name, i), f, os.path.relpath(path)))


if __name__ == "__main__":
    main()
