#!/usr/bin/env python3
"""Renders a short test drive with the car sounds, so they can be heard
without opening the game:

    python3 tools/preview_car_sounds.py                 # all three cars, into the temp folder
    python3 tools/preview_car_sounds.py --car pony_gt --out drive.mp3

Key on, idle, a blip of the throttle, full throttle from a standstill up
through the gears, lift off (pops, where the car has them), a hard corner
with the tyres squealing, a curb, then a knock into something. It blends
the clips the same way the game's CarAudio does (the two clips either side
of the revs, pitched to match, crossfaded; on and off throttle crossfaded
by the throttle), so what you hear here is what the game plays, minus the
3D placement as the camera swings round.

Needs ffmpeg and the files from tools/make_car_sounds.py.
"""

import argparse
import os
import subprocess
import tempfile

import numpy as np

FS = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SND = os.path.join(ROOT, "sounds", "cars")
BLOCK = 256

# Just what the preview needs from CarModels: idle, redline, gearing, and
# roughly how hard it pulls (N at the wheels in first per unit throttle,
# mass, drag), to make a believable rev trace.
CARS = {
    "pony_gt": {"ratios": [3.6, 2.4, 1.75, 1.36, 1.12, 1.0], "final": 3.55, "wheel": 0.33,
                "mass": 1480, "torque": 470, "drag": 0.38, "idle": 850, "redline": 7000, "pop": 1.0},
    "civique": {"ratios": [3.3, 1.95, 1.36, 1.03, 0.8], "final": 4.1, "wheel": 0.31,
                "mass": 1350, "torque": 170, "drag": 0.42, "idle": 800, "redline": 6600, "pop": 0.0},
    "halfton": {"ratios": [4.2, 2.8, 2.05, 1.6, 1.3], "final": 3.73, "wheel": 0.38,
                "mass": 2150, "torque": 500, "drag": 0.75, "idle": 700, "redline": 5800, "pop": 0.25},
}


def load(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(FS), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<i2").astype(np.float64) / 32768.0


class Loop:
    def __init__(self, data, rng):
        self.data = data
        self.pos = rng.uniform(0, len(data))

    def block(self, pitch, n):
        idx = self.pos + np.arange(n) * pitch
        self.pos = (self.pos + n * pitch) % len(self.data)
        i = np.floor(idx).astype(int)
        f = idx - i
        L = len(self.data)
        return self.data[i % L] * (1 - f) + self.data[(i + 1) % L] * f


def drive_script(car, rng):
    """Per block: rpm, throttle, speed (m/s), skid, and one-shot events."""
    c = CARS[car]
    dt = BLOCK / FS
    t = 0.0
    out = []
    events = []
    v = 0.0
    gear = 1
    shift = 0.0
    rpm = c["idle"]

    def step(throttle, brake=0.0, skid=0.0, steer_drag=0.0):
        nonlocal v, gear, shift, rpm, t
        ratio = c["ratios"][gear - 1] * c["final"]
        eng = v / c["wheel"] * 60 / (2 * np.pi) * ratio
        shift = max(0.0, shift - dt)
        if shift <= 0 and eng > c["redline"] * 0.94 and gear < len(c["ratios"]):
            gear += 1
            shift = 0.2
            events.append((t, "shift"))
        elif gear > 1 and eng < c["redline"] * 0.45 * (1 if throttle > 0.5 else 0.8):
            lower = v / c["wheel"] * 60 / (2 * np.pi) * c["ratios"][gear - 2] * c["final"]
            if lower < c["redline"] * 0.88:
                gear -= 1
                shift = 0.12
        target = max(eng, c["idle"] + 1800 * throttle) if v < 3 else max(eng, c["idle"])
        target = min(target, c["redline"] + 200)
        rpm += (target - rpm) * min(1, dt / (0.05 if target > rpm else 0.09))
        push = 0.0 if shift > 0 else throttle * c["torque"] * ratio * 0.86 / c["wheel"]
        f = push - c["drag"] * v * v - 14 * v - brake * 11000 * np.sign(v) - steer_drag * v * 60
        v = max(0.0, v + f / c["mass"] * dt)
        th = 0.15 if shift > 0 else throttle
        out.append((rpm, th, v, skid))
        t += dt

    def hold(seconds, *a, **k):
        for _ in range(int(seconds / dt)):
            step(*a, **k)

    events.append((0.0, "start"))
    hold(2.6, 0.0)  # key on and settle
    hold(1.2, 0.0)
    for _ in range(2):  # blip blip
        for i in range(int(0.25 / dt)):
            step(0.0 if i < 2 else 0.0)
            out[-1] = (min(c["redline"] * 0.55, c["idle"] + (c["redline"] * 0.55 - c["idle"]) * min(1, i * dt / 0.18)), 1.0, 0.0, 0.0)
        events.append((t, "lift"))
        for i in range(int(0.6 / dt)):
            step(0.0)
            r = c["idle"] + (c["redline"] * 0.55 - c["idle"]) * np.exp(-i * dt / 0.18)
            rpm = r
            out[-1] = (r, 0.0, 0.0, 0.0)
    hold(0.8, 0.0)
    # launch with a little wheelspin
    for i in range(int(9.0 / dt)):
        spin = max(0.0, 1 - i * dt / 0.9) * (0.8 if car == "pony_gt" else 0.35)
        step(1.0, skid=spin)
        if v * 3.6 > 150:
            break
    events.append((t, "lift"))
    hold(2.5, 0.0)
    # brake hard into a corner and lean on the tyres
    hold(1.0, 0.0, brake=0.7, skid=0.25)
    for i in range(int(2.2 / dt)):
        step(0.55, skid=0.55 + 0.35 * np.sin(i * dt * 2.3), steer_drag=0.25)
    hold(1.2, 0.8)
    events.append((t, "bump"))
    hold(1.5, 0.6)
    events.append((t, "lift"))
    hold(0.6, 0.0)
    events.append((t, "knock"))
    for _ in range(int(0.1 / dt)):
        step(0.0, brake=1.0)
    v = 0.0
    hold(2.2, 0.0)
    events.append((t, "stop"))
    hold(1.2, 0.0)
    return out, events


def render(car, seed=1):
    rng = np.random.default_rng(seed)
    c = CARS[car]
    d = os.path.join(SND, car)
    rpms = sorted(int(f[3:-4]) for f in os.listdir(d) if f.startswith("on_") and f.endswith(".ogg"))
    on = [Loop(load(os.path.join(d, f"on_{r}.ogg")), rng) for r in rpms]
    off = [Loop(load(os.path.join(d, f"off_{r}.ogg")), rng) for r in rpms]
    sh = os.path.join(SND, "shared")
    squeal = Loop(load(os.path.join(sh, "tyre_squeal.ogg")), rng)
    road = Loop(load(os.path.join(sh, "road.ogg")), rng)
    wind = Loop(load(os.path.join(sh, "wind.ogg")), rng)
    script, events = drive_script(car, rng)
    n = len(script) * BLOCK
    mix = np.zeros(n + 2 * FS)
    lr = np.log(rpms)
    ld = 0.0
    sk = 0.0
    engine_on = 0.0
    start_t = 0.0
    stop_t = next(t for t, ev in events if ev == "stop")
    for k, (rpm, th, v, skid) in enumerate(script):
        t = k * BLOCK / FS
        # engine gain: comes in as the key-on clip reaches idle, out at key-off
        if t >= stop_t:
            engine_on = max(0.0, engine_on - BLOCK / FS / 0.08)
        elif t > start_t + 2.1:
            engine_on = min(1.0, engine_on + BLOCK / FS / 0.35)
        ld += (th - ld) * min(1, BLOCK / FS / 0.07)
        sk += (skid - sk) * min(1, BLOCK / FS / 0.08)
        x = np.clip(np.interp(np.log(rpm), lr, np.arange(len(rpms))), 0, len(rpms) - 1)
        i0 = int(min(np.floor(x), len(rpms) - 2))
        f = x - i0
        w = {i0: np.cos(f * np.pi / 2), i0 + 1: np.sin(f * np.pi / 2)}
        g_on, g_off = np.sin(ld * np.pi / 2), np.cos(ld * np.pi / 2)
        blk = np.zeros(BLOCK)
        for i, wi in w.items():
            p = rpm / rpms[i]
            blk += on[i].block(p, BLOCK) * wi * g_on + off[i].block(p, BLOCK) * wi * g_off
        blk *= engine_on
        sp = min(1.0, v / 30.0)
        blk += road.block(0.7 + 0.6 * sp, BLOCK) * (sp ** 1.2) * 0.35
        ws = min(1.4, v / 45.0)
        blk += wind.block(0.8 + 0.4 * ws, BLOCK) * ws * ws * 0.22
        if sk > 0.02:
            blk += squeal.block(0.92 + 0.15 * sk, BLOCK) * min(1, sk) * 0.45
        else:
            squeal.block(1.0, BLOCK)
        mix[k * BLOCK:(k + 1) * BLOCK] += blk

    def shot(name, t, gain=1.0):
        y = load(name)
        i = int(t * FS)
        mix[i:i + len(y)] += y[: len(mix) - i] * gain

    for t, ev in events:
        if ev == "start":
            shot(os.path.join(d, "start.ogg"), t)
        elif ev == "stop":
            shot(os.path.join(d, "stop.ogg"), t)
        elif ev in ("lift", "shift") and rng.random() < c["pop"] * (0.7 if ev == "lift" else 0.35):
            shot(os.path.join(d, f"pop_{rng.integers(4)}.ogg"), t + rng.uniform(0.05, 0.15), 0.8)
        elif ev == "bump":
            shot(os.path.join(sh, f"bump_{rng.integers(3)}.ogg"), t, 0.7)
        elif ev == "knock":
            shot(os.path.join(sh, f"knock_heavy_{rng.integers(3)}.ogg"), t, 0.9)
    return mix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--car")
    ap.add_argument("--out", help="output file (.mp3 or .wav); default preview_<car>.mp3 in the temp folder")
    args = ap.parse_args()
    cars = [args.car] if args.car else list(CARS)
    for car in cars:
        mix = render(car)
        mix = mix / (np.max(np.abs(mix)) + 1e-9) * 0.89
        out = args.out or os.path.join(tempfile.gettempdir(), f"preview_{car}.mp3")
        pcm = (mix * 32767).astype("<i2").tobytes()
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(FS), "-ac", "1", "-i", "-",
                        "-b:a", "192k", out], input=pcm, check=True)
        print(out)


if __name__ == "__main__":
    main()
