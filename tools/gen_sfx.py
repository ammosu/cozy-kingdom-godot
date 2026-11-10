#!/usr/bin/env python3
"""程序化合成揮劍與命中音效（不靠外部素材）：python3 tools/gen_sfx.py → godot/assets/sfx/*.wav
whoosh = 帶通雜訊掃頻；hit_soft = 打到人的悶響；hit_heavy = 第三擊低頻衝擊；hit_hard = 打到牆的金屬聲。
每種多做幾個變體，遊戲裡隨機挑再微調音高，連打才不會單調。"""
import math, os, random, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "godot", "assets", "sfx")


def save(name, x, peak_db=-3.0, fade_out=True):
    m = max(abs(v) for v in x) or 1.0
    g = 10 ** (peak_db / 20) / m
    fade = int(SR * 0.004) if fade_out else 1
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes(b"".join(struct.pack("<h", int(v * g * (min(1.0, (len(x) - i) / fade) if fade_out else 1.0) * 32767)) for i, v in enumerate(x)))


def bandnoise(n, r, freq, q):
    """狀態變數濾波器：freq(t 0..1) 是中心頻率，輸出帶通"""
    lo = bp = 0.0; out = []
    for i in range(n):
        f = 2 * math.sin(math.pi * min(freq(i / n), SR / 6) / SR)
        hp = r.uniform(-1, 1) - lo - bp / q
        bp += f * hp; lo += f * bp
        out.append(bp)
    return out


def whoosh(seed, dur, f0, f1, f2):
    r = random.Random(seed); n = int(SR * dur)
    sweep = lambda t: f0 * (f1 / f0) ** (t / 0.55) if t < 0.55 else f1 * (f2 / f1) ** ((t - 0.55) / 0.45)
    b = bandnoise(n, r, sweep, 2.2)
    return [v * (min(1.0, (i / n) / 0.55) ** 2.2) * (1 - max(0.0, (i / n - 0.55) / 0.45)) ** 1.6 for i, v in enumerate(b)]


def tone(n, f0, f1, tau, r=None):
    p = 0.0; out = []
    for i in range(n):
        t = i / SR
        p += 2 * math.pi * (f1 + (f0 - f1) * math.exp(-t / 0.03)) / SR
        out.append(math.sin(p) * math.exp(-t / tau))
    return out


def mix(*tr):
    n = max(len(a) for a, _ in tr); o = [0.0] * n
    for a, g in tr:
        for i, v in enumerate(a):
            o[i] += v * g
    return o


def decay(x, tau):
    return [v * math.exp(-(i / SR) / tau) for i, v in enumerate(x)]


def hit_soft(seed):
    r = random.Random(seed); n = int(SR * 0.28)
    crack = decay(bandnoise(n, r, lambda t: r.uniform(1100, 1500), 1.4), 0.018)
    body = tone(n, r.uniform(210, 250), r.uniform(85, 105), 0.07)
    click = decay([r.uniform(-1, 1) for _ in range(n)], 0.0025)
    return mix((crack, 1.0), (body, 0.75), (click, 0.35))


def hit_heavy(seed):
    r = random.Random(seed); n = int(SR * 0.6)
    crack = decay(bandnoise(n, r, lambda t: 900, 1.2), 0.03)
    body = tone(n, 170, 46, 0.17)
    rum = decay(bandnoise(n, r, lambda t: 130, 1.5), 0.13)
    return mix((crack, 0.9), (body, 1.0), (rum, 1.2))


def hit_hard(seed):
    r = random.Random(seed); n = int(SR * 0.3)
    parts = [(tone(n, f, f, tau), g) for f, tau, g in
             ((r.uniform(1750, 2050), 0.09, 0.5), (r.uniform(3000, 3300), 0.06, 0.4), (r.uniform(4500, 5100), 0.035, 0.3))]
    click = decay([r.uniform(-1, 1) for _ in range(n)], 0.003)
    thud = tone(n, 300, 130, 0.03)
    return mix(*parts, (click, 0.5), (thud, 0.5))


def rain_loop(seed, dur=8.0, overlap=1.0):
    """雨聲：高頻細雨＋中頻打在地面的沙沙聲＋隨機的水滴。頭尾交叉淡化，循環時聽不出接縫"""
    r = random.Random(seed)
    n = int(SR * (dur + overlap))
    hiss = bandnoise(n, r, lambda t: 6200, 0.7)
    body = bandnoise(n, r, lambda t: 1500, 0.6)
    x = [hiss[i] * 0.55 + body[i] * 0.9 for i in range(n)]
    for _ in range(int(dur * 16)):
        at = r.randrange(n - 900)
        f = r.uniform(1400, 3600); a = r.uniform(0.15, 0.5)
        for j in range(900):
            x[at + j] += a * math.sin(2 * math.pi * f * j / SR) * math.exp(-j / 170)
    m = int(SR * dur); ov = n - m
    return [x[i] * (i / ov) + x[m + i] * (1 - i / ov) if i < ov else x[i] for i in range(m)]


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i in range(4):
        save(f"whoosh_{i}", whoosh(10 + i, 0.2 + 0.015 * i, 480 + 40 * i, 1900 - 90 * i, 650), -9)
    for i in range(2):
        save(f"whoosh_heavy_{i}", whoosh(20 + i, 0.32 + 0.02 * i, 260, 1050 - 80 * i, 340), -7)
    for i in range(4):
        save(f"hit_soft_{i}", hit_soft(30 + i), -4)
    for i in range(2):
        save(f"hit_heavy_{i}", hit_heavy(40 + i), -2)
    for i in range(3):
        save(f"hit_hard_{i}", hit_hard(50 + i), -7)
    save("rain_loop", rain_loop(70), -12, fade_out=False)
