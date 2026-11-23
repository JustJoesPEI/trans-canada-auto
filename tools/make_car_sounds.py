#!/usr/bin/env python3
"""Synthesizes the car sounds: engines, tyres, road, wind, knocks.

    pip install numpy scipy
    python3 tools/make_car_sounds.py            # writes sounds/cars/...
    python3 tools/make_car_sounds.py --wav      # also keeps .wav copies (for listening; not committed)

Nothing here is a recording, but it isn't a beep generator either: the engine
is modelled the way a real one makes its noise, so it comes out sounding
like one.

  * Each cylinder fires in turn, in the engine's real firing order, and
    each firing sends a pressure pulse down the exhaust: a sharp blowdown
    crack when the valve opens, then the push of the piston. How long the
    valve is open is a crank angle, so at low revs the pulses are long and
    thumpy and at high revs short and hard, just as in a real engine.
  * No two firings are alike. Every one is a little stronger or weaker
    than the last (more so at idle and off the throttle), and the revs
    wander slightly, which is most of what makes an engine sound alive.
  * A cross-plane V8 sends four uneven pulses down each bank's pipe; that
    unevenness is the V8 burble. The pickup's banks meet in a Y-pipe, the
    pony car's run separately to two tailpipes.
  * The pipes are acoustic tubes: the pulses bounce off the open end and
    ring at the pipe's own pitches (a delay line with losses), then go
    through the muffler's chambers and out of the tailpipe.
  * Under it all: intake roar that rises with load and revs, valvetrain
    tick, a touch of saturation, and the ground reflection and a little
    air, so the sound sits outdoors instead of in a vacuum.

The engine is rendered as looping clips at a ladder of steady revs, both on
the throttle ("on") and coasting ("off"). The game (CarAudio) plays the two
clips either side of the engine's revs, pitches them to match exactly and
blends between them, which is how racing games handle real recordings too.

Everything else is one-shots or loops built the same way: tyre squeal from
wandering stick-slip tones, road roar and wind from shaped noise, knocks and
bumps from a body's ringing modes struck with a crunch.

Output is Ogg Vorbis (small enough for the web build). Clips are seeded, so
rebuilding gives the same files.
"""

import argparse
import os
import shutil
import subprocess
import sys

import numpy as np
from scipy import signal

FS = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "sounds", "cars")

# --------------------------------------------------------------------------------------------
# The engines
# --------------------------------------------------------------------------------------------


def v8_cross_plane(order, bank_of):
    """Firing angles (crank degrees in the 720 cycle) and bank for each firing."""
    return [(i * 90.0, bank_of[c]) for i, c in enumerate(order)]


ENGINES = {
    # Dunmore Pony GT: a 5 litre cross-plane V8, lumpy cam, true dual exhaust
    # with light mufflers. Ford-style firing order 1-8-4-3-6-5-7-2, cylinders
    # 1-4 on the right bank, 5-8 on the left.
    "pony_gt": {
        "firings": v8_cross_plane([1, 8, 4, 3, 6, 5, 7, 2],
                                  {1: 0, 2: 0, 3: 0, 4: 0, 5: 1, 6: 1, 7: 1, 8: 1}),
        "banks": [
            {"header": 0.85, "pipe": 2.7, "tail_delay": 0.0},
            {"header": 0.95, "pipe": 2.75, "tail_delay": 0.00045},
        ],
        "merge": False,
        "reflect": -0.48, "pipe_damp": 0.4,
        "muffler": [(85.0, 1.6, 5.0), (220.0, 2.0, 2.5), (700.0, 1.5, -3.0)],
        "lowpass": 2600.0, "bark": 0.55, "flow": 0.55,
        "spread": 0.07, "idle_spread": 0.22, "lope": 0.035,
        "intake_hz": 520.0, "intake": 0.22, "mech": 0.05,
        "drive": 2.2, "loudness": 1.0,
        "idle": 850.0, "redline": 7000.0,
        "rpms": [850, 1150, 1550, 2050, 2700, 3500, 4500, 5700, 7200],
        "pop": 1.0,
    },
    # Hanaka Civique: a 1.8 litre inline four, firing 1-3-4-2 every 180
    # degrees, a 4-2-1 header into one pipe and a proper muffler. Most of
    # its character is intake and valvetrain; it gets raspy up top.
    "civique": {
        "firings": [(0.0, 0), (180.0, 0), (360.0, 0), (540.0, 0)],
        "banks": [{"header": 0.62, "pipe": 3.3, "tail_delay": 0.0}],
        "merge": False,
        "reflect": -0.45, "pipe_damp": 0.5,
        "muffler": [(120.0, 1.4, 2.5), (380.0, 2.5, 2.0), (1150.0, 2.0, 3.5)],
        "lowpass": 1900.0, "bark": 0.42, "flow": 0.4,
        "spread": 0.05, "idle_spread": 0.1, "lope": 0.008,
        "intake_hz": 950.0, "intake": 0.42, "mech": 0.13,
        "drive": 1.6, "loudness": 0.62,
        "idle": 800.0, "redline": 6600.0,
        "rpms": [800, 1100, 1500, 2000, 2650, 3450, 4450, 5600, 6900],
        "pop": 0.0,
    },
    # Halfton pickup: a big lazy small-block V8 (GM-style order 1-8-4-3-6-5-7-2,
    # odd cylinders left), banks joined in a Y-pipe with unequal headers,
    # into one heavy muffler. Deep and soft, still a little lumpy.
    "halfton": {
        "firings": v8_cross_plane([1, 8, 4, 3, 6, 5, 7, 2],
                                  {1: 0, 3: 0, 5: 0, 7: 0, 2: 1, 4: 1, 6: 1, 8: 1}),
        "banks": [
            {"header": 0.7, "pipe": 3.6, "tail_delay": 0.0},
            {"header": 1.35, "pipe": 3.6, "tail_delay": 0.0},
        ],
        "merge": True,
        "reflect": -0.45, "pipe_damp": 0.55,
        "muffler": [(70.0, 1.3, 5.0), (160.0, 1.8, 3.0), (500.0, 1.5, -4.0)],
        "lowpass": 1250.0, "bark": 0.35, "flow": 0.35,
        "spread": 0.06, "idle_spread": 0.14, "lope": 0.015,
        "intake_hz": 420.0, "intake": 0.2, "mech": 0.06,
        "drive": 1.8, "loudness": 0.85,
        "idle": 700.0, "redline": 5800.0,
        "rpms": [700, 950, 1300, 1750, 2300, 3000, 3900, 5000, 6000],
        "pop": 0.25,
    },
}

C_HOT = 520.0  # speed of sound in hot exhaust gas, m/s

# --------------------------------------------------------------------------------------------
# Filters
# --------------------------------------------------------------------------------------------


def biquad(kind, f0, q=0.707, gain_db=0.0):
    """RBJ cookbook biquad as (b, a)."""
    w = 2 * np.pi * f0 / FS
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / (2 * q)
    A = 10 ** (gain_db / 40)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    else:
        raise ValueError(kind)
    b, a = np.array(b), np.array(a)
    return b / a[0], a / a[0]


def filt(x, kind, f0, q=0.707, gain_db=0.0):
    b, a = biquad(kind, f0, q, gain_db)
    return signal.lfilter(b, a, x)


def tube(x, length, reflect, damp):
    """An open-ended pipe: the pulse runs to the end and back, partly reflected
    (inverted, at an open end), losing its top end each trip."""
    d = max(2, int(round(2 * length / C_HOT * FS)))
    p = damp  # one-pole lowpass in the loop
    b = np.array([1.0, -p])
    a = np.zeros(d + 1)
    a[0], a[1] = 1.0, -p
    a[d] -= reflect * (1 - p)
    return signal.lfilter(b, a, x)


def frac_delay(x, seconds):
    if seconds <= 0:
        return x
    n = seconds * FS
    i = int(n)
    f = n - i
    y = np.zeros_like(x)
    y[i:] += x[: len(x) - i] * (1 - f)
    y[i + 1:] += x[: len(x) - i - 1] * f
    return y


def smooth_noise(rng, n, rate_hz, order=2):
    """Slowly wandering noise, unit-ish std."""
    w = rng.standard_normal(n)
    sos = signal.butter(order, rate_hz / (FS / 2), output="sos")
    y = signal.sosfilt(sos, w)
    return y / (np.std(y) + 1e-12)


def pink(rng, n):
    w = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / FS)
    f[0] = f[1]
    y = np.fft.irfft(w / np.sqrt(f), n)
    return y / np.std(y)


def outdoors(x, rng, wet=0.06):
    """The ground reflection a metre or so away and a little air around it."""
    ir_len = int(0.18 * FS)
    ir = np.zeros(ir_len)
    ir[0] = 1.0
    g = int(0.0037 * FS)
    ir[g] += 0.42
    ir[g + 1] += 0.12
    t = np.arange(ir_len) / FS
    tail = rng.standard_normal(ir_len) * np.exp(-t / 0.045)
    tail[: int(0.006 * FS)] = 0
    tail = filt(tail, "lp", 3500)
    ir += tail * wet
    return signal.fftconvolve(x, ir)[: len(x)]


def saturate(x, drive):
    m = np.max(np.abs(x)) + 1e-12
    return np.tanh(drive * x / m) / np.tanh(drive) * m


def loopify(x, n, fade):
    """x has n + fade samples; fold the overhang onto the start so it loops."""
    out = x[:n].copy()
    t = np.linspace(0, np.pi / 2, fade)
    out[:fade] = x[:fade] * np.sin(t) + x[n:n + fade] * np.cos(t)
    return out


# --------------------------------------------------------------------------------------------
# Engine
# --------------------------------------------------------------------------------------------


def firing_events(cfg, rpm_curve, rng):
    """Times (s), banks and cylinder slots of every firing, following the rpm curve."""
    crank = np.cumsum(rpm_curve / 60.0 * 360.0 / FS)  # degrees
    start = rng.uniform(0, 720)
    crank = crank + start
    events = []
    cycles = int(crank[-1] // 720) + 2
    for cyc in range(int(start // 720), cycles):
        for slot, (ang, bank) in enumerate(cfg["firings"]):
            a = cyc * 720.0 + ang
            if a < crank[0] or a > crank[-1]:
                continue
            idx = np.searchsorted(crank, a)
            if idx <= 0:
                continue
            # interpolate a sub-sample time
            c0, c1 = crank[idx - 1], crank[idx]
            tf = (idx - 1 + (a - c0) / max(c1 - c0, 1e-9)) / FS
            events.append((tf, bank, slot))
    events.sort()
    return events


def add_pulse(buf, t0, rpm, blow, hump, decay_scale=1.0):
    """One exhaust pulse: the blowdown crack and the piston's push."""
    valve = 235.0 / (6.0 * max(rpm, 150.0))  # seconds the exhaust valve is open
    tau_d = np.clip(0.11 * valve, 0.0006, 0.0045) * decay_scale
    tau_r = 0.00012
    length = valve + 5 * tau_d
    i0 = int(np.floor(t0 * FS))
    n = int(length * FS) + 2
    i1 = min(len(buf), i0 + n)
    if i1 <= i0 or i0 < 0:
        return
    t = (np.arange(i0, i1) / FS) - t0
    t = np.maximum(t, 0.0)
    p = blow * (np.exp(-t / tau_d) - np.exp(-t / tau_r))
    ph = np.clip(t / valve, 0, 1)
    p += hump * np.sin(np.pi * ph) ** 2 * (1 - ph) * 1.6
    buf[i0:i1] += p


def render_engine(cfg, rpm_curve, load_curve, seed, pops=None, pulse_gain=1.0):
    """The engine's sound for a given rpm and load over time (arrays, one per sample)."""
    rng = np.random.default_rng(seed)
    n = len(rpm_curve)
    redline = cfg["redline"]
    idle = cfg["idle"]
    # The revs never sit perfectly still: a slow wander, plus cam lope at idle.
    near_idle = np.clip(1.0 - (rpm_curve - idle) / (idle * 1.2), 0, 1)
    wander = smooth_noise(rng, n, 1.5) * (0.0025 + cfg["lope"] * near_idle)
    rpm_live = rpm_curve * (1 + wander)
    events = firing_events(cfg, rpm_live, rng)

    nb = len(cfg["banks"])
    pulses = [np.zeros(n) for _ in range(nb)]
    ticks = np.zeros(n)
    env = np.zeros(n)
    prev_amp = 1.0
    for tf, bank, slot in events:
        i = min(int(tf * FS), n - 1)
        rpm = rpm_live[i]
        load = load_curve[i]
        rfrac = np.clip((rpm - idle) / (redline - idle), 0, 1)
        idle_ness = np.clip(1.0 - rfrac * 3, 0, 1)
        spread = cfg["spread"] + (cfg["idle_spread"] - cfg["spread"]) * max(idle_ness, 1 - load) * 0.8
        # Cycle-to-cycle variation, a little correlated with the last firing.
        amp = 0.7 * prev_amp + 0.3 * (1 + spread * rng.standard_normal() * 1.8)
        amp = max(0.25, amp)
        prev_amp = amp
        lf = 0.3 + 0.7 * load
        blow = pulse_gain * amp * lf * (0.75 + 0.5 * rfrac)
        hump = pulse_gain * amp * (0.5 + 0.3 * load)
        # Combustion never lights at exactly the same crank angle, and never
        # burns at exactly the same speed: about a degree either way.
        jitter = rng.normal(0, 0.9) / (6.0 * max(rpm, 150.0))
        add_pulse(pulses[bank], tf + jitter, rpm, blow, hump, decay_scale=rng.uniform(0.8, 1.2))
        # valvetrain tick, a bit after the firing
        tk = tf + 0.25 * 60.0 / max(rpm, 150) * 0.5
        j = int(tk * FS)
        if 0 <= j < n:
            ticks[j] += rng.uniform(0.6, 1.0)
        if 0 <= i < n:
            env[i] += amp * (0.3 + load)

    if pops:
        for tf, strength in pops:
            i = min(int(tf * FS), n - 1)
            bank = rng.integers(nb)
            add_pulse(pulses[bank], tf, rpm_live[i], strength * 2.2, strength * 0.2, decay_scale=0.35)

    # Each bank down its pipe. The gas rushing out with each pulse is
    # turbulent: a hiss and rasp riding on the pulses, which is most of what
    # you hear above a few hundred hertz in a real exhaust.
    outs = []
    for b, bank in enumerate(cfg["banks"]):
        x = pulses[b]
        flow = np.maximum(x, 0.0)
        flow = signal.lfilter([0.15], [1, -0.85], flow)
        turb = filt(filt(pink(rng, n), "hp", 300, 0.6), "lp", 2800, 0.6)
        x = x + turb * flow * cfg["flow"] * 1.0
        x = tube(x, bank["header"], -0.3, 0.25)
        if not cfg["merge"]:
            x = tube(x, bank["pipe"], cfg["reflect"], cfg["pipe_damp"])
        outs.append(frac_delay(x, bank["tail_delay"]))
    if cfg["merge"]:
        y = tube(sum(outs), cfg["banks"][0]["pipe"], cfg["reflect"], cfg["pipe_damp"])
    else:
        y = sum(outs)

    # The muffler's chambers, then out of the tailpipe.
    for f0, q, g in cfg["muffler"]:
        y = filt(y, "peak", f0, q, g)
    y = filt(y, "lp", cfg["lowpass"], 0.6)
    y = filt(y, "lp", cfg["lowpass"] * 1.8, 0.5)
    # Out of the tailpipe the low end radiates weakly (a small pipe end is a
    # poor woofer), which is what gives an exhaust its bark.
    b1, a1 = signal.butter(1, 250.0 / (FS / 2), "high")
    rad = signal.lfilter(b1, a1, y) * 1.6
    y = (1 - cfg["bark"]) * y + cfg["bark"] * rad
    y = filt(y, "hp", 28.0, 0.7)

    # Intake roar, breathing with the firings, louder with load and revs.
    rfrac_all = np.clip((rpm_curve - idle) / (redline - idle), 0, 1)
    env_s = signal.lfilter([0.02], [1, -0.98], env)
    env_s /= (np.max(env_s) + 1e-9)
    noise = rng.standard_normal(n)
    ih = cfg["intake_hz"] * (0.75 + 0.6 * rfrac_all.mean())
    intake = filt(noise, "bp", ih, 1.2) + 0.5 * filt(noise, "bp", ih * 2.3, 2.0)
    intake *= (0.3 + env_s) * (0.15 + 0.85 * load_curve) * (0.25 + rfrac_all ** 1.3)
    y_rms = np.sqrt(np.mean(y ** 2)) + 1e-9

    # Valvetrain and injector tick.
    tk = signal.lfilter([1.0], [1, -0.93], ticks)
    mech = filt(rng.standard_normal(n) * tk, "hp", 2800, 0.7)
    mech += filt(rng.standard_normal(n) * signal.lfilter([1.0], [1, -0.995], ticks) * 0.08, "bp", 1700, 1.5)

    y = y + intake * cfg["intake"] * y_rms * 2.0 + mech * cfg["mech"] * y_rms * 3.0
    y = saturate(y, cfg["drive"] * (0.6 + 0.4 * float(np.mean(load_curve))))
    # A breath of air around it.
    y += pink(rng, n) * y_rms * 0.006
    y = outdoors(y, rng)
    return y


def engine_loop(cfg, rpm, load, seed, seconds=2.6):
    fade = int(0.3 * FS)
    pre = int(0.4 * FS)
    n = int(seconds * FS)
    total = pre + n + fade
    rpm_curve = np.full(total, float(rpm))
    load_curve = np.full(total, float(load))
    y = render_engine(cfg, rpm_curve, load_curve, seed)[pre:]
    return loopify(y, n, fade)


def starter(cfg, seed):
    """Key on: the starter cranks, it catches, flares and settles to idle."""
    rng = np.random.default_rng(seed)
    crank_s = 0.75 + rng.uniform(-0.1, 0.15)
    total = int((crank_s + 1.9) * FS)
    t = np.arange(total) / FS
    idle = cfg["idle"]
    tc = t - crank_s
    rpm = np.where(tc < 0, 0.0,
                   idle + idle * 0.9 * np.exp(-np.maximum(tc - 0.18, 0) / 0.35) * np.clip(tc / 0.18, 0, 1))
    load = np.where(tc < 0, 0.0, 0.25 * np.exp(-np.maximum(tc, 0) / 0.4))
    rpm_eng = np.maximum(rpm, 200.0)
    eng = render_engine(cfg, rpm_eng, load, seed + 1)
    gate = np.clip((tc + 0.02) / 0.04, 0, 1)
    eng *= gate

    # The starter: a geared whine with the crank heaving against compression.
    n_crank = int((crank_s + 0.1) * FS)
    cyl = len(cfg["firings"])
    crank_rpm = 230.0 * (1 + 0.05 * smooth_noise(rng, n_crank, 3))
    comp_hz = crank_rpm / 60.0 * cyl / 2
    ph = np.cumsum(comp_hz / FS)
    heave = 0.55 + 0.45 * np.cos(2 * np.pi * ph)  # slows on each compression stroke
    whine_hz = 330.0 * (0.85 + 0.25 * heave) * (0.7 + 0.3 * np.clip(np.arange(n_crank) / (0.12 * FS), 0, 1))
    wph = np.cumsum(whine_hz / FS) * 2 * np.pi
    whine = (np.sin(wph) + 0.5 * np.sin(2 * wph + 0.3) + 0.3 * np.sin(3 * wph + 1.1)) * heave
    grind = filt(rng.standard_normal(n_crank), "bp", 1400, 1.0) * heave * 0.6
    chug = filt(rng.standard_normal(n_crank), "lp", 180) * (1 - heave) * 1.8
    st = whine * 0.35 + grind + chug
    st *= np.clip(np.arange(n_crank) / (0.02 * FS), 0, 1)
    st[-int(0.1 * FS):] *= np.linspace(1, 0, int(0.1 * FS))
    st = outdoors(st, rng, 0.08)
    ref = np.sqrt(np.mean(eng[int(crank_s * FS):] ** 2)) + 1e-9
    out = eng.copy()
    out[:n_crank] += st / (np.sqrt(np.mean(st ** 2)) + 1e-9) * ref * 0.45
    return out


def shutdown(cfg, seed):
    """Key off: the revs fall away and it shudders to a stop."""
    total = int(0.9 * FS)
    t = np.arange(total) / FS
    rpm = cfg["idle"] * np.maximum(1 - t / 0.55, 0) ** 0.7
    rpm = np.maximum(rpm, 180.0)
    load = np.zeros(total)
    y = render_engine(cfg, rpm, load, seed, pulse_gain=1.0)
    y *= np.clip(1 - (t - 0.35) / 0.35, 0, 1) ** 1.5
    return y


def pop_shot(cfg, seed):
    """Overrun pops: unburnt fuel lighting off in the hot exhaust."""
    rng = np.random.default_rng(seed)
    total = int(0.7 * FS)
    rpm = np.full(total, cfg["redline"] * rng.uniform(0.45, 0.7))
    load = np.zeros(total)
    k = rng.integers(1, 4)
    times = np.sort(rng.uniform(0.01, 0.28, k))
    pops = [(tt, rng.uniform(0.7, 1.4)) for tt in times]
    return render_engine(cfg, rpm, load, seed, pops=pops, pulse_gain=0.0)


# --------------------------------------------------------------------------------------------
# Tyres, road, wind, knocks
# --------------------------------------------------------------------------------------------


def tyre_squeal(seed, seconds=4.0):
    """Rubber stick-slipping across the road: a few tones that wander and stutter."""
    rng = np.random.default_rng(seed)
    fade = int(0.35 * FS)
    n = int(seconds * FS)
    total = n + fade
    y = np.zeros(total)
    for base, amp in ((860.0, 1.0), (1120.0, 0.75), (1530.0, 0.5), (690.0, 0.35)):
        drift = smooth_noise(rng, total, 1.2) * base * 0.06
        flutter = smooth_noise(rng, total, 35.0) * base * 0.012
        f = base + drift + flutter
        ph = np.cumsum(f / FS) * 2 * np.pi
        tone = np.sin(ph) + 0.25 * np.sin(2 * ph + 0.7) + 0.08 * np.sin(3 * ph + 2.1)
        stutter = np.clip(0.55 + 0.6 * smooth_noise(rng, total, 9.0), 0, 1.4)
        stutter *= np.clip(0.7 + 0.4 * smooth_noise(rng, total, 0.8), 0.2, 1.3)
        y += tone * stutter * amp
    hiss = filt(rng.standard_normal(total), "bp", 3200, 0.8)
    hiss *= np.clip(0.6 + 0.5 * smooth_noise(rng, total, 12), 0, 1.5)
    y = y / np.std(y) + hiss / np.std(hiss) * 0.28
    y = saturate(y, 1.4)
    y = outdoors(y, rng, 0.1)
    return loopify(y, n, fade)


def road_roar(seed, seconds=4.0):
    """Tyres rolling on asphalt: a low rumble with the road's grain in it."""
    rng = np.random.default_rng(seed)
    fade = int(0.35 * FS)
    n = int(seconds * FS)
    total = n + fade
    x = pink(rng, total)
    x = filt(x, "lp", 650, 0.6)
    x = filt(x, "hp", 45, 0.7)
    x = filt(x, "peak", 120, 1.0, 4.0)
    grain = filt(rng.standard_normal(total), "bp", 900, 0.7) * 0.25
    grain *= np.clip(0.6 + 0.4 * smooth_noise(rng, total, 25), 0, 2)
    texture = 1 + 0.18 * smooth_noise(rng, total, 4.0)
    y = (x / np.std(x) + grain / (np.std(grain) + 1e-9) * 0.2) * texture
    y = outdoors(y, rng, 0.05)
    return loopify(y, n, fade)


def wind(seed, seconds=5.0):
    """Air rushing past the body, gusting a little."""
    rng = np.random.default_rng(seed)
    fade = int(0.4 * FS)
    n = int(seconds * FS)
    total = n + fade
    x = pink(rng, total)
    x = filt(x, "bp", 520, 0.5) + 0.35 * filt(x, "bp", 1900, 0.9)
    gust = np.clip(1 + 0.3 * smooth_noise(rng, total, 0.6) + 0.1 * smooth_noise(rng, total, 5), 0.3, 2)
    # a faint whistle round the mirrors, coming up with the gusts
    whistle = filt(rng.standard_normal(total), "bp", 1450, 18)
    whistle *= np.clip(gust - 0.8, 0, 1)
    y = x * gust + whistle / (np.std(whistle) + 1e-9) * 0.08
    return loopify(y / np.std(y), n, fade)


def knock(seed, heavy):
    """A car body struck: a thump, a crunch, and the panels ringing."""
    rng = np.random.default_rng(seed)
    dur = 1.4 if heavy else 0.6
    n = int(dur * FS)
    t = np.arange(n) / FS
    # thump: the whole body taking the hit
    f0 = rng.uniform(55, 80) if heavy else rng.uniform(85, 130)
    thump = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.8 * np.exp(-t / 0.02))) / FS) * np.exp(-t / (0.12 if heavy else 0.05))
    # the panels: inharmonic modes, the low ones lasting longest
    modes = np.zeros(n)
    for _ in range(26 if heavy else 14):
        f = np.exp(rng.uniform(np.log(140), np.log(5200)))
        dec = rng.uniform(0.04, 0.5) * (300 / f) ** 0.4 * (1.3 if heavy else 0.6)
        modes += rng.uniform(0.2, 1.0) * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.3)) * np.exp(-t / dec)
    modes /= np.std(modes[: int(0.1 * FS)]) + 1e-9
    # the crunch: crumpling sheet and plastic, a burst of crackles
    crack = np.zeros(n)
    k = 90 if heavy else 25
    span = 0.14 if heavy else 0.05
    ts = rng.exponential(span / 3, k)
    for tt in ts[ts < span * 2]:
        i = int(tt * FS)
        crack[i] += rng.uniform(-1, 1) * np.exp(-tt / span)
    crack = filt(signal.lfilter([1.0], [1, -0.6], crack), "hp", 900)
    crunch = filt(rng.standard_normal(n), "bp", 2200, 0.7) * np.exp(-t / (0.06 if heavy else 0.02))
    y = thump * 1.4 + modes * 0.35 * np.exp(-t / 0.3) + crack * 6 + crunch * 0.6
    if heavy:
        # something loose rattling after
        rat = np.zeros(n)
        for tt in np.cumsum(rng.uniform(0.02, 0.09, 12)) + 0.08:
            if tt < dur - 0.05:
                rat[int(tt * FS)] += rng.uniform(0.3, 1) * np.exp(-tt / 0.3)
        rat = filt(signal.lfilter([1.0], [1, -0.9], rat), "bp", 3000, 2)
        y += rat * 2.5
    y = saturate(y, 1.6)
    y = outdoors(y, rng, 0.12)
    y *= np.clip((dur - t) / 0.05, 0, 1)
    return y


def bump(seed):
    """A wheel hitting a curb or landing: a dull thud through the suspension."""
    rng = np.random.default_rng(seed)
    n = int(0.45 * FS)
    t = np.arange(n) / FS
    f0 = rng.uniform(48, 75)
    thud = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 1.2 * np.exp(-t / 0.012))) / FS) * np.exp(-t / 0.07)
    clunk = filt(rng.standard_normal(n), "bp", rng.uniform(300, 500), 1.5) * np.exp(-t / 0.03)
    rattle = filt(rng.standard_normal(n), "hp", 2500) * np.exp(-t / 0.015) * 0.3
    y = thud + clunk * 0.5 + rattle
    y = outdoors(y, rng, 0.08)
    y *= np.clip((0.45 - t) / 0.05, 0, 1)
    return y


# --------------------------------------------------------------------------------------------
# Writing
# --------------------------------------------------------------------------------------------


def write(path, y, peak_ref, keep_wav):
    y = y / peak_ref
    y = np.clip(y, -0.999, 0.999)
    pcm = (y * 32767).astype("<i2")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wav = path[:-4] + ".wav"
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(FS)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", path],
                   check=True)
    if not keep_wav:
        os.remove(wav)


def rms_db(y):
    return 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)


def level_ladder(cfg, clips):
    """Even out the loudness from one rung of the rev ladder to the next.

    A pipe resonance can make one clip a few dB louder than its neighbours;
    in the game the clips are blended while pitched to the same revs, and a
    lump like that would swell and fade as you drive through it. Real
    engines get louder smoothly with revs, so each clip is pulled most of
    the way onto a smooth line, and coasting sits a set distance below
    pulling (closer at idle, further at high revs).
    """
    rpms = np.array(cfg["rpms"], float)
    x = np.log(rpms)
    on = np.array([rms_db(clips[f"on_{r}"]) for r in cfg["rpms"]])
    k, c = np.polyfit(x, on, 1)
    fit = k * x + c
    rfrac = np.clip((rpms - cfg["idle"]) / (cfg["redline"] - cfg["idle"]), 0, 1)
    for i, r in enumerate(cfg["rpms"]):
        clips[f"on_{r}"] *= 10 ** ((fit[i] - on[i]) * 0.8 / 20)
        target_off = fit[i] - (7.0 + 6.0 * rfrac[i])
        clips[f"off_{r}"] *= 10 ** ((target_off - rms_db(clips[f"off_{r}"])) / 20)
    # The key-on clip ends at idle and the key-off clip starts there:
    # match them to the idle clip they hand over to.
    idle_db = rms_db(clips[f"off_{cfg['rpms'][0]}"])
    st = clips["start"]
    st *= 10 ** ((idle_db - rms_db(st[-int(0.4 * FS):])) / 20)
    sp = clips["stop"]
    sp *= 10 ** ((idle_db - rms_db(sp[: int(0.15 * FS)])) / 20)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wav", action="store_true", help="keep .wav copies next to the .ogg files")
    ap.add_argument("--car", help="only this car")
    args = ap.parse_args()
    if not shutil.which("ffmpeg"):
        sys.exit("needs ffmpeg (for the Ogg Vorbis encode)")

    for car, cfg in ENGINES.items():
        if args.car and car != args.car:
            continue
        print(car)
        clips = {}
        for i, r in enumerate(cfg["rpms"]):
            clips[f"on_{r}"] = engine_loop(cfg, r, 1.0, 1000 + i)
            clips[f"off_{r}"] = engine_loop(cfg, r, 0.0, 2000 + i)
        clips["start"] = starter(cfg, 31)
        clips["stop"] = shutdown(cfg, 41)
        for k in range(4):
            clips[f"pop_{k}"] = pop_shot(cfg, 50 + k)
        level_ladder(cfg, clips)
        # One level for the whole car, so loud stays loud and idle stays idle.
        peak = max(np.max(np.abs(v)) for k, v in clips.items() if k.startswith("on_")) / (0.9 * cfg["loudness"])
        for name, y in clips.items():
            write(os.path.join(OUT, car, name + ".ogg"), y, peak, args.wav)

    if not args.car:
        print("shared")
        shared = {
            "tyre_squeal": (tyre_squeal(7), 0.6),
            "road": (road_roar(8), 0.5),
            "wind": (wind(9), 0.5),
        }
        for k in range(3):
            shared[f"knock_light_{k}"] = (knock(60 + k, False), 0.8)
            shared[f"knock_heavy_{k}"] = (knock(70 + k, True), 0.95)
            shared[f"bump_{k}"] = (bump(80 + k), 0.8)
        for name, (y, level) in shared.items():
            write(os.path.join(OUT, "shared", name + ".ogg"), y, np.max(np.abs(y)) / level, args.wav)
    print("done")


if __name__ == "__main__":
    main()
