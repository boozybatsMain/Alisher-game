#!/usr/bin/env python3
"""Процедурные звуки и музыка игры (numpy + scipy), без внешних сэмплов.

Звуки: assets/sfx/*.wav. Музыка: assets/music/*.wav — домбра (струна Карплуса–Стронга),
кобыз (смычковая пила с вибрато), дауылпаз (рамочный барабан), тёплый бурдон.
"""
import math
import os
import wave

import numpy as np
from scipy import signal

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SR = 44100
RNG = np.random.default_rng(7)


def write(path, x, sr=SR):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.89
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def t_(dur, sr=SR):
    return np.arange(int(dur * sr)) / sr


def env(n, a=0.005, d=0.3, sr=SR, curve=4.0):
    t = np.arange(n) / sr
    e = np.minimum(1.0, t / max(a, 1e-4)) * np.exp(-np.maximum(0, t - a) * curve / max(d, 1e-4))
    return e


def noise(n):
    return RNG.uniform(-1, 1, n)


def lp(x, f, sr=SR, order=2):
    b, a = signal.butter(order, min(f / (sr / 2), 0.99), "low")
    return signal.lfilter(b, a, x)


def hp(x, f, sr=SR, order=2):
    b, a = signal.butter(order, min(f / (sr / 2), 0.99), "high")
    return signal.lfilter(b, a, x)


def bp(x, f0, f1, sr=SR, order=2):
    b, a = signal.butter(order, [max(f0, 20) / (sr / 2), min(f1 / (sr / 2), 0.99)], "band")
    return signal.lfilter(b, a, x)


def sweep_bp(x, f_start, f_end, q=3.0, sr=SR, block=256):
    """Полосовой фильтр с плавающей частотой (свист рассекаемого воздуха)."""
    out = np.zeros_like(x)
    n = len(x)
    zi = None
    for i in range(0, n, block):
        k = i / max(1, n - 1)
        f = f_start * (f_end / f_start) ** k
        bw = f / q
        b, a = signal.butter(2, [max(30, f - bw) / (sr / 2), min(f + bw, sr / 2 * 0.98) / (sr / 2)], "band")
        if zi is None or len(zi) != max(len(a), len(b)) - 1:
            zi = signal.lfilter_zi(b, a) * 0
        out[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return out


def tone(freq, dur, kind="sine", sr=SR, pitch_env=None):
    n = int(dur * sr)
    f = np.full(n, float(freq)) if pitch_env is None else freq * pitch_env(np.arange(n) / sr)
    ph = 2 * np.pi * np.cumsum(f) / sr
    if kind == "sine":
        return np.sin(ph)
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if kind == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1.0) - 1) - 1
    if kind == "square":
        return np.sign(np.sin(ph))
    raise ValueError(kind)


def pad(x, dur, sr=SR):
    n = int(dur * sr)
    out = np.zeros(max(n, len(x)))
    out[:len(x)] += x
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def at(x, delay, sr=SR):
    return np.concatenate([np.zeros(int(delay * sr)), x])


def clang(freqs, dur, decay=4.0, sr=SR):
    """Металлический звон: неинтегральные обертона с разным затуханием."""
    t = t_(dur, sr)
    out = np.zeros_like(t)
    for i, f in enumerate(freqs):
        out += np.sin(2 * np.pi * f * t + RNG.uniform(0, 6)) * np.exp(-t * decay * (1 + i * 0.35)) / (1 + i * 0.4)
    return out


def pluck(freq, dur, sr=SR, bright=0.5, decay=0.996):
    """Струна Карплуса–Стронга — звук домбры."""
    n = int(dur * sr)
    period = max(2, int(sr / freq))
    buf = lp(noise(period), 1500 + bright * 5000, sr) if period > 8 else noise(period)
    out = np.zeros(n)
    b = buf.copy()
    idx = 0
    for i in range(n):
        out[i] = b[idx]
        nxt = (idx + 1) % period
        b[idx] = decay * 0.5 * (b[idx] + b[nxt])
        idx = nxt
    # корпус домбры: лёгкий резонанс
    out = out + 0.35 * bp(out, 180, 420, sr)
    return out * env(n, 0.002, dur, sr, curve=2.2)


def drum(dur=0.6, f0=110, f1=55, sr=SR, slap=0.4):
    """Дауылпаз — рамочный барабан: тон с падающей высотой + шлепок по коже."""
    t = t_(dur, sr)
    body = np.sin(2 * np.pi * np.cumsum(f1 + (f0 - f1) * np.exp(-t * 30)) / sr) * np.exp(-t * 7)
    skin = bp(noise(len(t)), 600, 3000, sr) * np.exp(-t * 40) * slap
    return body + skin


def save_sfx(name, x):
    write(os.path.join(ROOT, "assets", "sfx", name + ".wav"), x)


# ============================================================== звуки
def make_sfx():
    n = noise
    # свист сабли
    for name, dur, f0, f1, amp in [("swing", 0.22, 900, 3200, 1.0), ("swing_heavy", 0.36, 500, 2400, 1.0), ("swing_enemy", 0.42, 300, 1400, 1.0)]:
        x = sweep_bp(n(int(dur * SR)), f0, f1, q=2.5) * np.sin(np.linspace(0, np.pi, int(dur * SR))) ** 1.5
        if name == "swing_enemy":
            x = mix(x, lp(n(int(dur * SR)), 300) * np.sin(np.linspace(0, np.pi, int(dur * SR))) * 0.8)
        save_sfx(name, x * amp)
    # удары по врагу
    hit = mix(lp(n(int(0.18 * SR)), 2500) * env(int(0.18 * SR), 0.001, 0.08),
              tone(140, 0.2, "sine", pitch_env=lambda t: 1 + 1.5 * np.exp(-t * 40)) * env(int(0.2 * SR), 0.001, 0.12) * 1.2)
    save_sfx("hit", hit)
    heavy = mix(lp(n(int(0.35 * SR)), 1800) * env(int(0.35 * SR), 0.001, 0.15),
                tone(80, 0.45, "sine", pitch_env=lambda t: 1 + 2 * np.exp(-t * 25)) * env(int(0.45 * SR), 0.001, 0.3) * 1.6,
                clang([640, 1012, 1530], 0.4, 9) * 0.25)
    save_sfx("hit_heavy", heavy)
    # блок и идеальный блок
    save_sfx("block", mix(clang([420, 731, 1105, 1640], 0.5, 8), lp(n(int(0.1 * SR)), 3000) * env(int(0.1 * SR), 0.001, 0.04)))
    parry = mix(clang([1320, 1980, 2640, 3960], 1.0, 3.2) * 0.9, clang([660, 990], 0.8, 4) * 0.6,
                sweep_bp(n(int(0.5 * SR)), 2000, 8000, 4) * env(int(0.5 * SR), 0.001, 0.25) * 0.5)
    save_sfx("parry", parry)
    # кувырок, рывок
    save_sfx("roll", mix(lp(n(int(0.32 * SR)), 900) * np.sin(np.linspace(0, np.pi, int(0.32 * SR))), at(lp(n(int(0.08 * SR)), 600) * env(int(0.08 * SR), 0.001, 0.05), 0.24)))
    save_sfx("dash", sweep_bp(n(int(0.35 * SR)), 400, 5000, 2) * np.sin(np.linspace(0, np.pi, int(0.35 * SR))) ** 0.7)
    save_sfx("dash_enemy", sweep_bp(n(int(0.4 * SR)), 1800, 300, 2) * np.sin(np.linspace(0, np.pi, int(0.4 * SR))))
    # урон и смерть героя
    hurt = mix(lp(n(int(0.25 * SR)), 1200) * env(int(0.25 * SR), 0.001, 0.1),
               tone(220, 0.3, "saw", pitch_env=lambda t: 1 - 0.4 * t) * env(int(0.3 * SR), 0.005, 0.15) * 0.3)
    save_sfx("hurt", lp(hurt, 2500))
    death = mix(tone(160, 1.4, "saw", pitch_env=lambda t: 1 - 0.45 * t) * env(int(1.4 * SR), 0.01, 1.0) * 0.4,
                lp(n(int(1.0 * SR)), 400) * env(int(1.0 * SR), 0.001, 0.6))
    save_sfx("death", lp(death, 1800))
    revive = mix(*[at(clang([f, f * 1.5, f * 2], 1.2, 2.5) * 0.5, i * 0.09) for i, f in enumerate([523, 659, 784, 1046])])
    save_sfx("revive", revive)
    # молния Тенгри
    tn = int(1.4 * SR)
    crack = hp(n(tn), 1500) * np.exp(-t_(1.4) * 18)
    rumble = lp(np.cumsum(n(tn)) * 0.02, 180) * env(tn, 0.05, 1.2, curve=3)
    save_sfx("thunder", mix(crack * 0.9, rumble * 2.0))
    # тяжёлые удары о землю, прыжки
    slam = mix(drum(0.8, 90, 38, slap=0.8) * 1.4, lp(n(int(0.6 * SR)), 700) * env(int(0.6 * SR), 0.001, 0.4), clang([210, 340], 0.6, 7) * 0.2)
    save_sfx("slam", slam)
    save_sfx("leap", sweep_bp(n(int(0.45 * SR)), 300, 1500, 2) * np.sin(np.linspace(0, np.pi, int(0.45 * SR))))
    # рёв боссов
    rt = t_(1.6)
    growl_f = 70 * (1 + 0.25 * np.sin(2 * np.pi * 0.7 * rt)) * (1 + 0.04 * np.sin(2 * np.pi * 23 * rt))
    growl = np.sin(2 * np.pi * np.cumsum(growl_f) / SR) + 0.6 * (2 * ((np.cumsum(growl_f * 2) / SR) % 1) - 1)
    roar = mix(lp(growl, 900) * env(len(rt), 0.15, 1.4, curve=2), bp(n(len(rt)), 300, 1600) * env(len(rt), 0.1, 1.3, curve=2) * 0.7)
    save_sfx("boss_roar", roar)
    bd = mix(roar * 0.8, at(drum(1.2, 70, 30, slap=1.0) * 1.5, 0.3), at(lp(n(int(1.5 * SR)), 500) * env(int(1.5 * SR), 0.01, 1.2), 0.3))
    save_sfx("boss_death", bd)
    # снаряды, магия
    save_sfx("shoot_arrow", mix(clang([180, 260], 0.25, 14) * 0.7, sweep_bp(n(int(0.3 * SR)), 2500, 900, 3) * env(int(0.3 * SR), 0.005, 0.2)))
    ot = t_(0.6)
    save_sfx("shoot_orb", mix(np.sin(2 * np.pi * np.cumsum(300 + 500 * np.exp(-ot * 6) + 40 * np.sin(2 * np.pi * 9 * ot)) / SR) * env(len(ot), 0.01, 0.4),
                              bp(n(len(ot)), 800, 2600) * env(len(ot), 0.01, 0.3) * 0.4))
    save_sfx("shoot_shockwave", mix(drum(0.9, 60, 30, slap=0.6) * 1.2, lp(n(int(0.9 * SR)), 350) * env(int(0.9 * SR), 0.01, 0.7)))
    st = t_(1.3)
    summon = np.sin(2 * np.pi * np.cumsum(220 * (1 + 0.5 * st) * (1 + 0.03 * np.sin(2 * np.pi * 6 * st))) / SR) * env(len(st), 0.2, 1.1, curve=2)
    save_sfx("summon", mix(summon, np.sin(2 * np.pi * np.cumsum(331 * (1 + 0.5 * st)) / SR) * env(len(st), 0.2, 1.1, curve=2) * 0.6,
                           bp(n(len(st)), 500, 2000) * env(len(st), 0.3, 1.0) * 0.3))
    save_sfx("teleport", mix(sweep_bp(n(int(0.6 * SR)), 3000, 300, 4) * env(int(0.6 * SR), 0.01, 0.5),
                             tone(880, 0.5, "sine", pitch_env=lambda t: 1 - 0.8 * t) * env(int(0.5 * SR), 0.01, 0.4) * 0.5))
    save_sfx("wind_wall", sweep_bp(n(int(1.2 * SR)), 200, 900, 2) * env(int(1.2 * SR), 0.3, 1.0, curve=2))
    # смерти врагов
    save_sfx("death_balbal", mix(*[at(mix(clang([300 + i * 70, 520 + i * 90], 0.3, 12) * 0.4, lp(n(int(0.15 * SR)), 2000) * env(int(0.15 * SR), 0.001, 0.08)), i * 0.07) for i in range(6)],
                                 lp(n(int(0.9 * SR)), 600) * env(int(0.9 * SR), 0.01, 0.6)))
    save_sfx("death_spirit", mix(sweep_bp(n(int(1.0 * SR)), 2500, 400, 5) * env(int(1.0 * SR), 0.02, 0.8),
                                 tone(660, 0.9, "sine", pitch_env=lambda t: 1 - 0.6 * t) * env(int(0.9 * SR), 0.01, 0.7) * 0.5))
    wt = t_(0.7)
    save_sfx("death_wolf", lp(np.sin(2 * np.pi * np.cumsum(420 * (1 - 0.5 * wt) * (1 + 0.05 * np.sin(2 * np.pi * 30 * wt))) / SR) * env(len(wt), 0.01, 0.5), 3000))
    save_sfx("death_archer", mix(*[at(clang([900 + i * 120, 1400 + i * 200], 0.18, 20) * 0.5, i * 0.06) for i in range(7)]))
    save_sfx("death_shaman", mix(sweep_bp(n(int(1.1 * SR)), 300, 3000, 3) * env(int(1.1 * SR), 0.02, 0.9), clang([220, 330, 495], 1.0, 3) * 0.4))
    # асык, интерфейс
    save_sfx("asyk", mix(clang([2100, 3150], 0.12, 30), at(clang([2800, 4200], 0.1, 30) * 0.6, 0.04)))
    save_sfx("ui_click", mix(clang([1400, 2100], 0.08, 40), lp(n(int(0.02 * SR)), 4000) * 0.3 * env(int(0.02 * SR), 0.001, 0.01)))
    save_sfx("ui_hover", clang([2400], 0.05, 60) * 0.5)
    save_sfx("alert", mix(clang([1568, 2350], 0.22, 14) * 0.9, at(clang([2093, 3136], 0.2, 16) * 0.7, 0.07),
                          bp(n(int(0.05 * SR)), 3000, 8000) * env(int(0.05 * SR), 0.001, 0.02) * 0.3))
    save_sfx("buy", mix(*[at(clang([f, f * 2.01], 0.5, 6) * 0.6, i * 0.06) for i, f in enumerate([880, 1175, 1568])]))
    save_sfx("gift_open", mix(*[at(clang([f, f * 1.5, f * 2], 1.6, 2) * 0.5, i * 0.12) for i, f in enumerate([392, 494, 587, 784])]))
    save_sfx("gift_take", mix(*[at(clang([f, f * 2], 0.9, 3.5) * 0.6, i * 0.05) for i, f in enumerate([784, 988, 1175, 1568])],
                              sweep_bp(n(int(0.6 * SR)), 1500, 6000, 4) * env(int(0.6 * SR), 0.01, 0.4) * 0.3))
    save_sfx("wave_start", mix(drum(0.7, 120, 50) * 1.2, at(drum(0.7, 120, 50) * 1.0, 0.22), at(drum(1.0, 100, 40, slap=0.6) * 1.4, 0.44)))
    save_sfx("wave_clear", mix(*[at(pluck(f, 1.2, bright=0.6), i * 0.1) for i, f in enumerate([293.7, 349.2, 440.0, 587.3])]))
    # юрта
    dt = t_(0.9)
    door = mix(lp(np.sin(2 * np.pi * np.cumsum(180 + 60 * np.sin(2 * np.pi * 3 * dt)) / SR) * (1 + 0.6 * n(len(dt))) * env(len(dt), 0.05, 0.7), 1200) * 0.5,
               at(lp(n(int(0.2 * SR)), 500) * env(int(0.2 * SR), 0.001, 0.1), 0.65))
    save_sfx("door", door)
    save_sfx("chest", mix(lp(n(int(0.25 * SR)), 900) * env(int(0.25 * SR), 0.001, 0.15), at(clang([700, 1100], 0.4, 8) * 0.5, 0.15),
                          at(clang([1050, 1600], 0.3, 10) * 0.3, 0.3)))
    save_sfx("fire_whoosh", mix(lp(n(int(1.0 * SR)), 1200) * env(int(1.0 * SR), 0.15, 0.8, curve=2),
                                hp(n(int(1.0 * SR)), 3000) * (RNG.uniform(0, 1, int(1.0 * SR)) > 0.997) * 2.0))
    strum = mix(*[at(pluck(f, 1.6, bright=0.7), i * 0.03) for i, f in enumerate([146.8, 220.0])],
                *[at(pluck(f, 1.4, bright=0.6), 0.35 + i * 0.25) for i, f in enumerate([293.7, 349.2, 392.0, 440.0])])
    save_sfx("dombra", strum)
    print("sfx:", len(os.listdir(os.path.join(ROOT, "assets", "sfx"))))


# ============================================================== музыка
MSR = 32000


def note(n):
    """MIDI → Гц."""
    return 440.0 * 2 ** ((n - 69) / 12)


def track(bpm, bars, layers):
    beat = 60.0 / bpm
    total = bars * 4 * beat
    out = np.zeros(int(total * MSR) + MSR * 2)
    for fn in layers:
        fn(out, beat, total)
    # хвост закольцовываем, чтобы петля была бесшовной
    n = int(total * MSR)
    tail = out[n:]
    out = out[:n]
    out[:len(tail)] += tail
    return out


def put(out, x, t):
    i = int(t * MSR)
    j = min(len(out), i + len(x))
    if i < len(out):
        out[i:j] += x[:j - i]


def drone(root_midi, amp=0.18, dark=600):
    def f(out, beat, total):
        tt = np.arange(len(out)) / MSR
        x = np.zeros_like(tt)
        for k, m in enumerate([root_midi, root_midi + 7, root_midi - 12]):
            fr = note(m) * (1 + 0.002 * np.sin(2 * np.pi * (0.1 + 0.05 * k) * tt))
            x += (2 * ((np.cumsum(fr) / MSR) % 1) - 1) * (0.6 if k else 1.0)
        x = lp(x, dark, MSR) * (0.75 + 0.25 * np.sin(2 * np.pi * tt / (beat * 8)))
        out += x * amp
    return f


def kobyz(melody, amp=0.22):
    """Кобыз: смычковый звук — пила с вибрато через резонанс корпуса. melody: [(доля, MIDI, длительность в долях)]."""
    def f(out, beat, total):
        for b0, m, d in melody:
            dur = d * beat
            tt = np.arange(int(dur * MSR)) / MSR
            vib = 1 + 0.008 * np.sin(2 * np.pi * 5.5 * tt) * np.minimum(1, tt / 0.3)
            ph = np.cumsum(note(m) * vib) / MSR
            x = 2 * (ph % 1) - 1
            x = bp(x, 250, 2400, MSR) + 0.4 * bp(x, 600, 900, MSR)
            e = np.minimum(1, tt / 0.12) * np.minimum(1, (dur - tt) / 0.2)
            put(out, x * e * amp, b0 * beat)
    return f


def dombra(pattern, amp=0.35, bright=0.55):
    def f(out, beat, total):
        for b0, m in pattern:
            x = pluck(note(m), 1.2, sr=MSR, bright=bright, decay=0.994)
            put(out, x * amp, b0 * beat)
    return f


def drums(pattern, amp=0.6, f0=120, f1=50):
    def f(out, beat, total):
        for b0, accent in pattern:
            put(out, drum(0.5, f0, f1, sr=MSR, slap=0.3 + 0.5 * accent) * amp * (0.6 + 0.4 * accent), b0 * beat)
    return f


def shaker(per_beat=2, amp=0.06, bars=8):
    def f(out, beat, total):
        n = int(total / beat * per_beat)
        for i in range(n):
            x = hp(RNG.uniform(-1, 1, int(0.06 * MSR)), 5000, MSR) * env(int(0.06 * MSR), 0.002, 0.03, MSR)
            put(out, x * amp * (1.0 if i % per_beat == 0 else 0.6), i * beat / per_beat)
    return f


def crackle(amp=0.05):
    def f(out, beat, total):
        m = RNG.uniform(0, 1, len(out)) > 0.9993
        out += hp(m * RNG.uniform(-1, 1, len(out)), 2000, MSR) * amp * 6
        out += lp(RNG.uniform(-1, 1, len(out)), 400, MSR) * amp * 0.4
    return f


def ostinato(scale, bars, per_bar, start=0, seed=1):
    r = np.random.default_rng(seed)
    pat = []
    for b in range(bars):
        for k in range(per_bar):
            pos = b * 4 + k * 4.0 / per_bar
            deg = [0, 2, 1, 3, 2, 4, 3, 1][(k + b) % 8] if k % 2 == 0 else r.integers(0, len(scale))
            pat.append((pos, scale[int(deg) % len(scale)] + start))
    return pat


def make_music():
    d_minor_penta = [50, 53, 55, 57, 60, 62, 65]          # D F G A C D F
    a_minor_penta = [45, 48, 50, 52, 55, 57, 60]
    tracks = {}
    # юрта: спокойная домбра у очага
    yurt_pat = [(b * 4 + k, d_minor_penta[[0, 3, 2, 4, 1, 3, 5, 2][int(b * 4 + k) % 8]]) for b in range(8) for k in (0, 1.5, 2, 3)]
    tracks["yurt"] = track(76, 8, [drone(38, 0.12, 400), dombra(yurt_pat, 0.32, 0.4), crackle(0.04),
                                   kobyz([(8, 62, 6), (16, 60, 4), (20, 57, 4), (24, 62, 7)], 0.12)])
    tracks["calm"] = track(70, 8, [drone(38, 0.12, 380), dombra(yurt_pat[::2], 0.3, 0.35), crackle(0.02)])
    # бой днём: быстрая домбра, барабан, кобыз
    day_drums = [(b * 4 + k, 1.0 if k in (0, 2) else 0.4) for b in range(8) for k in (0, 1, 1.5, 2, 3, 3.5)]
    day_mel = [(0, 62, 2), (2, 65, 2), (4, 67, 3), (7, 65, 1), (8, 62, 4), (12, 60, 2), (14, 62, 2), (16, 69, 3), (19, 67, 1), (20, 65, 2),
               (22, 67, 2), (24, 62, 6), (30, 60, 2)]
    tracks["battle_day"] = track(132, 8, [drone(38, 0.12, 700), dombra(ostinato(d_minor_penta, 8, 8, 0, 3), 0.28, 0.7),
                                          drums(day_drums, 0.55), shaker(2, 0.05), kobyz(day_mel, 0.16)])
    night_drums = [(b * 4 + k, 1.0 if k == 0 else 0.5) for b in range(8) for k in (0, 1.5, 2.5, 3)]
    night_mel = [(0, 57, 4), (4, 60, 2), (6, 59, 2), (8, 57, 6), (16, 64, 3), (19, 62, 1), (20, 60, 4), (24, 57, 8)]
    tracks["battle_night"] = track(118, 8, [drone(33, 0.16, 500), dombra(ostinato(a_minor_penta, 8, 8, 0, 5), 0.24, 0.5),
                                            drums(night_drums, 0.6, 100, 42), kobyz(night_mel, 0.2)])
    boss_drums = [(b * 4 + k, 1.0 if k in (0, 1, 2, 3) else 0.5) for b in range(8) for k in (0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5)]
    boss_mel = [(0, 50, 2), (2, 53, 2), (4, 51, 4), (8, 50, 2), (10, 55, 2), (12, 53, 4), (16, 57, 3), (19, 55, 1), (20, 53, 4), (24, 50, 8)]
    tracks["boss"] = track(140, 8, [drone(26, 0.22, 450), dombra(ostinato([38, 41, 43, 44, 45, 48], 8, 8, 0, 9), 0.26, 0.8),
                                    drums(boss_drums, 0.5, 90, 38), kobyz(boss_mel, 0.24), shaker(4, 0.04)])
    vic = [(i * 0.5, m) for i, m in enumerate([62, 65, 67, 69, 72, 74, 77, 74, 72, 69, 74])]
    tracks["victory"] = track(100, 4, [drone(38, 0.1, 900), dombra(vic + [(8 + i * 0.5, m) for i, m in enumerate([62, 69, 74, 77])], 0.35, 0.8),
                                       kobyz([(6, 74, 6), (12, 77, 4)], 0.14), drums([(0, 1.0), (2, 0.6), (4, 1.0), (8, 1.0), (12, 1.0)], 0.4)])
    tracks["defeat"] = track(60, 3, [drone(33, 0.14, 350), kobyz([(0, 57, 3), (3, 55, 3), (6, 52, 5)], 0.22),
                                     dombra([(0, 45), (3, 43), (6, 40)], 0.3, 0.3)])
    for name, x in tracks.items():
        write(os.path.join(ROOT, "assets", "music", name + ".wav"), x, MSR)
    print("music:", list(tracks))


if __name__ == "__main__":
    make_sfx()
    make_music()
