#!/usr/bin/env python3
"""Builds a car's engine sounds from real recordings instead of synthesis.

    pip install numpy scipy
    python3 tools/make_recorded_engines.py            # every car listed in SOURCES
    python3 tools/make_recorded_engines.py --car civique --wav

It writes the same files the synthesized engines use (sounds/cars/<car>/
on_<rpm>.ogg, off_<rpm>.ogg, start.ogg, stop.ogg), so CarAudio plays them
the same way, plus engine.json with how to pitch them.

The recordings are not in the repository: they're from the free Sonniss
#GameAudioGDC 2024 bundle (sonniss.com/gameaudiogdc), part 1 of 9, and go in
raw/sounds/ (ignored by git) under the names in SOURCES:

  pony_gt/corvette_onboard_intake_hotlap.wav   Bryan Gold, 1967 Corvette Convertible
                                               Work-Up: "OnBoard-Group F Intake MIC,
                                               Start Hot Lap 03"
  pony_gt/corvette_false_start.wav             same library: "OnBoard-Group B ENGINE
                                               MIC, False Start"
  civique/q2_onboard_exhaust_revs.wav          Dramatic Cat, Audi Q2: "ONBOARD Driving
                                               Sequence With Revs Up And Down EXHAUST RIGHT"
  civique/q2_onboard_exhaust_start_idle_stop.wav  same library: "ONBOARD Turn On Start
                                               Long Idle Stop Shutoff EXHAUST CENTER"

What the repository keeps are the loops cut from them. The bundle's licence
allows using and changing the sounds in games (no credit needed, though the
game gives it); it doesn't allow selling them as they come.

How a recording becomes a ladder of steady loops:

  1. The engine's revs are followed through the whole recording from the
     pitch of its firing (tools/rpm_track.py).
  2. For each rung of the ladder, every moment the engine was near those
     revs is collected: rising revs for the on-throttle loop, falling revs
     for the off-throttle loop.
  3. Each moment is resampled so its revs hold exactly steady at the rung
     (a ramp from 2,900 to 3,100 rpm comes out as a steady 3,000), then the
     pieces are joined with short crossfades and folded into a seamless loop.

Real recordings rarely cover every rev an engine in the game can reach. A
rung with nothing near it borrows the closest material and stretches it,
and if the recording's whole range is narrower than the game car's,
engine.json's pitch_exponent squeezes the game's revs onto it (so the
sound rises smoothly all the way up rather than sweeping and snapping back).
"""

import argparse
import json
import os
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rpm_track  # noqa: E402

FS = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RAW = os.path.join(ROOT, "raw", "sounds")
OUT = os.path.join(ROOT, "sounds", "cars")

# Each car: its recordings, how pitch turns into revs, and which stretches
# are what. Times are seconds into the recording.
#   order      revs per minute per hertz of the tracked line (60 for the
#              crank's own rate, 30 for a four's firing)
#   track      the tracked line's search range, Hz, and how many harmonics
#   drive      [start, end] of the recording to cut the rev ladder from
#   idle       [start, end] of steady idle
#   raw_rungs  [start, end, rpm] stretches of steady revs to use as recorded
#              for any rung within 30% of them (resampled to fit)
#   idle_rpm   the idle's revs, when the tracker can't be trusted there; the
#              idle loop is then the recording itself, untouched
#   start      how to build key-on; stop: the key-off stretch
#   level_db   how loud the on-throttle loops are overall (RMS), matching the
#              synthesized engines they replaced so the mix stays as it was
SOURCES = {
    "civique": {
        "drive_file": "civique/q2_onboard_exhaust_revs.wav",
        "idle_file": "civique/q2_onboard_exhaust_start_idle_stop.wav",
        "order": 30.0, "track": [20.0, 240.0, 6],
        "drive": [0.0, 133.0],
        "idle": None, # this recording's idle is a cold fast idle; the revs recording's dips are better
        "start": {"file": "civique/q2_onboard_exhaust_start_idle_stop.wav", "from": 0.35, "to": 3.2},
        "stop": {"file": "civique/q2_onboard_exhaust_start_idle_stop.wav", "from": 25.7, "to": 29.5},
        "rungs": 9, "level_db": -17.3,
    },
    "pony_gt": {
        "drive_file": "pony_gt/corvette_onboard_intake_hotlap.wav",
        "idle_file": "pony_gt/corvette_onboard_intake_hotlap.wav",
        "order": 60.0, "track": [12.0, 130.0, 14],
        "drive": [55.0, 350.0],
        "idle": [352.0, 378.0],
        # The tracker can't follow this quiet idle reliably (the lope smears
        # it); its firing sits at 60-63 Hz, about 900 rpm, so it's given here
        # and the idle is used as recorded.
        "idle_rpm": 900.0,
        # The cold fast idle after it starts, about 1,100 rpm (its harmonics
        # sit 18.5 Hz apart): real engine for a rung the driving never visits.
        "raw_rungs": [[16.0, 50.0, 1110.0]],
        "crank": {"file": "pony_gt/corvette_false_start.wav", "from": 0.45, "to": 1.75},
        "stop": {"file": "pony_gt/corvette_onboard_intake_hotlap.wav", "from": 377.0, "to": 383.0},
        "rungs": 9, "level_db": -11.5,
    },
}

# ------------------------------------------------------------------------------------------


def load(path, sr):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<f4").astype(np.float64)


class Recording:
    """A recording at 2x the output rate (for clean resampling) with its rev track."""

    def __init__(self, path, cfg):
        self.x = load(path, FS * 2)
        lo, hi, harm = cfg["track"]
        small = load(path, 4000)
        t, hz, st = rpm_track.track(small, 4000, lo, hi, harmonics=harm, max_step=0.04)
        rpm = hz * cfg["order"]
        # A light smoothing: follow the revs, keep each firing's own wobble.
        rpm = signal.savgol_filter(rpm, 9, 2)
        self.t, self.rpm, self.strength = t, rpm, st
        self.slope = np.gradient(np.log(rpm), t)  # fractional change per second
        self.dur = len(self.x) / (FS * 2)

    def rpm_at(self, times):
        return np.interp(times, self.t, self.rpm)


def flatten(rec, a, b, target, rpm_curve=None):
    """The stretch [a, b] seconds, resampled so its revs hold at target (or follow rpm_curve)."""
    sr2 = FS * 2
    i0, i1 = int(a * sr2), int(b * sr2)
    ts = np.arange(i0, i1) / sr2
    r = rec.rpm_at(ts)
    phase = np.concatenate([[0.0], np.cumsum(r[:-1] / sr2)])  # rev-seconds since a
    if rpm_curve is None:
        n_out = int(phase[-1] / target * FS)
        want = np.arange(n_out) * target / FS
    else:
        # rpm_curve: per output sample (at FS)
        want = np.cumsum(rpm_curve) / FS
        want = want[want < phase[-1]]
    src = np.interp(want, phase, np.arange(i0, i1))
    j = np.floor(src).astype(int)
    f = src - j
    j = np.clip(j, 0, len(rec.x) - 2)
    y = rec.x[j] * (1 - f) + rec.x[j + 1] * f
    # (taken from the 2x-rate copy, so no decimation filter is needed for the
    # small ratios involved; a gentle lowpass guards the top octave)
    b_, a_ = signal.butter(6, 19000 / (FS / 2))
    return signal.filtfilt(b_, a_, y) if len(y) > 30 else y


def runs(mask, t, min_len):
    """Contiguous stretches of True in mask, as [start, end] times, at least min_len long."""
    out = []
    i = 0
    n = len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            if t[j - 1] - t[i] >= min_len:
                out.append((t[i], t[j - 1]))
            i = j
        else:
            i += 1
    return out


def join(pieces, length, xfade=0.04):
    """Joins pieces with equal-power crossfades until length seconds plus a loop overhang."""
    xf = int(xfade * FS)
    need = int(length * FS)
    out = np.zeros(0)
    k = 0
    while len(out) < need + int(0.3 * FS) and pieces:
        p = pieces[k % len(pieces)]
        k += 1
        if len(p) < 2 * xf + 10:
            continue
        if len(out) == 0:
            out = p.copy()
            continue
        w = np.linspace(0, np.pi / 2, xf)
        mixed = out[-xf:] * np.cos(w) + p[:xf] * np.sin(w)
        out = np.concatenate([out[:-xf], mixed, p[xf:]])
        if k > 400:
            break
    return out


def loopify(x, n, fade):
    out = x[:n].copy()
    t = np.linspace(0, np.pi / 2, fade)
    out[:fade] = x[:fade] * np.sin(t) + x[n:n + fade] * np.cos(t)
    return out


def ladder_clip(rec, window, target, load, seconds=2.4, idle_window=None):
    """A steady loop at target rec-rpm: on (rising) or off (falling) throttle."""
    a, b = window
    m = (rec.t >= a) & (rec.t <= b) & (rec.strength > np.percentile(rec.strength, 15))
    if load == "on":
        lm = rec.slope > 0.04
    elif load == "off":
        lm = rec.slope < -0.04
    else:
        lm = np.ones_like(m)
    pieces = []
    total = 0.0
    def amount(fs):
        return sum(e - s for s, e in fs)

    for tol in (0.05, 0.08, 0.12, 0.18, 0.26, 0.4, 0.6):
        near = np.abs(np.log(rec.rpm / target)) < np.log(1 + tol)
        found = runs(m & near & lm, rec.t, 0.12)
        # Not enough on the right side of the throttle this close: steady
        # stretches next, then anything this close, before reaching further.
        if load != "any" and amount(found) < 1.2:
            found += runs(m & near & (np.abs(rec.slope) <= 0.04), rec.t, 0.2)
        if load != "any" and amount(found) < 1.2 and tol >= 0.08:
            found += runs(m & near, rec.t, 0.12)
        found = sorted(set(found), key=lambda r: -(r[1] - r[0]))
        total = amount(found)
        if total >= 1.6 or (total >= 1.0 and tol >= 0.12):
            break
    for s, e in found:
        pieces.append(flatten(rec, s, e, target))
    if idle_window is not None and not pieces:
        pieces.append(flatten(rec, idle_window[0], idle_window[1], target))
    y = join(pieces, seconds)
    n = int(seconds * FS)
    fade = int(0.25 * FS)
    if len(y) < n + fade:
        y = np.concatenate([y, y])[: n + fade] if len(y) > fade else np.zeros(n + fade)
    return loopify(y, n, fade), tol, total


def rms_db(y):
    return 20 * np.log10(np.sqrt(np.mean(y ** 2)) + 1e-12)


def write(path, y, keep_wav):
    y = np.clip(y, -0.999, 0.999)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    wav = path[:-4] + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(FS)
        w.writeframes((y * 32767).astype("<i2").tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", path], check=True)
    if not keep_wav:
        os.remove(wav)


def car_spec(car):
    """idle and redline from CarModels (read from the GDScript, so they can't drift apart)."""
    src = open(os.path.join(ROOT, "scripts", "vehicles", "car_models.gd")).read()
    i = src.index('"%s": {' % car)
    import re
    m = re.search(r'"idle_rpm":\s*([\d.]+),\s*"redline_rpm":\s*([\d.]+)', src[i:])
    return float(m.group(1)), float(m.group(2))


def build(car, cfg, keep_wav):
    print(car)
    idle_g, red_g = car_spec(car)
    drive = Recording(os.path.join(RAW, cfg["drive_file"]), cfg)
    win = cfg["drive"]
    dm = (drive.t >= win[0]) & (drive.t <= win[1])
    rec_hi = float(np.percentile(drive.rpm[dm], 99))
    if cfg.get("idle_rpm"):
        idle_rec = None
        rec_idle = float(cfg["idle_rpm"])
        idle_raw = load(os.path.join(RAW, cfg["idle_file"]), FS)[int(cfg["idle"][0] * FS):int(cfg["idle"][1] * FS)]
    elif cfg["idle"]:
        idle_rec = drive if cfg["idle_file"] == cfg["drive_file"] else Recording(os.path.join(RAW, cfg["idle_file"]), cfg)
        im = (idle_rec.t >= cfg["idle"][0]) & (idle_rec.t <= cfg["idle"][1])
        rec_idle = float(np.median(idle_rec.rpm[im]))
    else:
        idle_rec = None
        rec_idle = float(np.percentile(drive.rpm[dm], 2))
    # Game revs onto recording revs: rec = rec_idle * (game / idle)^e, with e
    # chosen so the redline lands a little past the top of the recording.
    e = min(1.0, np.log(rec_hi * 1.12 / rec_idle) / np.log(red_g / idle_g))
    print(f"  recording revs {rec_idle:.0f} (idle) to {rec_hi:.0f}; game {idle_g:.0f}-{red_g:.0f}; pitch exponent {e:.2f}")
    rungs = np.exp(np.linspace(np.log(idle_g), np.log(red_g * 1.03), cfg["rungs"]))
    rungs = [int(round(r / 10) * 10) for r in rungs]
    clips = {}
    kept = []
    raw_cache = {}
    for r in rungs:
        target = rec_idle * (r / idle_g) ** e
        raw = None
        if r != rungs[0]:
            for a, b, rr in cfg.get("raw_rungs", []):
                if abs(np.log(target / rr)) < np.log(1.3):
                    if (a, b) not in raw_cache:
                        raw_cache[(a, b)] = load(os.path.join(RAW, cfg["idle_file"]), FS)[int(a * FS):int(b * FS)]
                    seg = raw_cache[(a, b)]
                    raw = np.interp(np.arange(0, len(seg) - 1, target / rr), np.arange(len(seg)), seg)
        if raw is None and r != rungs[0]:
            # Is there anything close enough at all? If not, leave the rung out
            # and let the game blend across the gap.
            _, _, tot = ladder_clip(drive, win, target, "any")
            if tot < 0.3:
                print(f"  {r}: nothing near rec {target:.0f} rpm, rung left out")
                continue
        kept.append(r)
        for side in ("on", "off"):
            if raw is not None:
                n, fade = int(2.4 * FS), int(0.25 * FS)
                off = (len(raw) - n - fade) // 2 if side == "on" else 0
                y, tol, tot = loopify(raw[off:], n, fade), 0.0, len(raw) / FS
                if side == "on":
                    y = y * 10 ** (2.5 / 20)
            elif r == rungs[0] and cfg.get("idle_rpm"):
                # the idle as recorded: every lump of the cam left in
                n, fade = int(2.4 * FS), int(0.25 * FS)
                off = (len(idle_raw) - n - fade) // 2 if side == "on" else 0
                y, tol, tot = loopify(idle_raw[off:], n, fade), 0.0, len(idle_raw) / FS
                if side == "on":
                    y = y * 10 ** (2.5 / 20)
            elif r == rungs[0] and idle_rec is not None:
                y, tol, tot = ladder_clip(idle_rec, cfg["idle"], target, "any")
                if side == "on":
                    y = y * 10 ** (2.5 / 20) # a touch more throttle
            else:
                y, tol, tot = ladder_clip(drive, win, target, side)
            clips[f"{side}_{r}"] = y
            print(f"  {side}_{r}: rec {target:.0f} rpm, {tot:.1f} s of material within {tol * 100:.0f}%")

    rungs = kept

    # Key on and key off.
    if "start" in cfg:
        s = cfg["start"]
        x = load(os.path.join(RAW, s["file"]), FS)[int(s["from"] * FS):int(s["to"] * FS)]
        # Ease the tail down to the idle loop's pitch, so the hand-over doesn't jump.
        tail_rec = Recording(os.path.join(RAW, s["file"]), cfg)
        tail_rpm = float(np.median(tail_rec.rpm[(tail_rec.t > s["to"] - 0.6) & (tail_rec.t < s["to"])]))
        idle_target = rec_idle
        ratio = idle_target / tail_rpm
        n = len(x)
        glide = np.ones(n)
        g0 = int(n * 0.55)
        glide[g0:] = np.linspace(1.0, ratio, n - g0)
        # read through it at the glide's rate (slower reads are lower revs)
        src = np.cumsum(glide)
        src = src[src < n - 1]
        y = np.interp(src, np.arange(n), x)
        y[: int(0.01 * FS)] *= np.linspace(0, 1, int(0.01 * FS))
        clips["start"] = y
    elif "crank" in cfg:
        c = cfg["crank"]
        crank = load(os.path.join(RAW, c["file"]), FS)[int(c["from"] * FS):int(c["to"] * FS)]
        # It catches: idle flared up and settling, made from the idle itself.
        n_catch = int(1.5 * FS)
        tt = np.arange(n_catch) / FS
        curve = rec_idle * (1 + 0.6 * np.exp(-np.maximum(tt - 0.1, 0) / 0.28) * np.clip(tt / 0.1, 0, 1))
        # read the recorded idle faster, then slower, as the revs flare and settle
        src = np.cumsum(curve / rec_idle)
        catch = np.interp(src, np.arange(len(idle_raw)), idle_raw)
        xf = int(0.06 * FS)
        crank = crank * (10 ** ((rms_db(catch) - rms_db(crank) - 4) / 20))
        w = np.linspace(0, np.pi / 2, xf)
        y = np.concatenate([crank[:-xf], crank[-xf:] * np.cos(w) + catch[:xf] * np.sin(w), catch[xf:]])
        y[: int(0.01 * FS)] *= np.linspace(0, 1, int(0.01 * FS))
        clips["start"] = y
    s = cfg["stop"]
    st = load(os.path.join(RAW, s["file"]), FS)[int(s["from"] * FS):int(s["to"] * FS)]
    fo = int(0.3 * FS)
    st[-fo:] *= np.linspace(1, 0, fo)
    st[: int(0.02 * FS)] *= np.linspace(0, 1, int(0.02 * FS))
    clips["stop"] = st

    # Levels: even out the ladder like the synthesized one, keep coasting
    # below pulling, and sit at the same overall loudness as before.
    on = np.array([rms_db(clips[f"on_{r}"]) for r in rungs])
    xr = np.log(rungs)
    k, c0 = np.polyfit(xr, on, 1)
    fit = k * xr + c0
    for i, r in enumerate(rungs):
        clips[f"on_{r}"] *= 10 ** ((fit[i] - on[i]) * 0.6 / 20)
        off_db = rms_db(clips[f"off_{r}"])
        cap = rms_db(clips[f"on_{r}"]) - 4.0
        if off_db > cap:
            clips[f"off_{r}"] *= 10 ** ((cap - off_db) / 20)
    idle_db = rms_db(clips[f"off_{rungs[0]}"])
    for key, part in (("start", -int(0.4 * FS)), ("stop", int(0.3 * FS))):
        y = clips[key]
        seg = y[part:] if part < 0 else y[:part]
        y *= 10 ** ((idle_db - rms_db(seg)) / 20)
    gain = 10 ** ((cfg["level_db"] - rms_db(np.concatenate([clips[f"on_{r}"] for r in rungs]))) / 20)
    peak = max(np.max(np.abs(v)) for v in clips.values()) * gain
    if peak > 0.95:
        gain *= 0.95 / peak
    d = os.path.join(OUT, car)
    for f in os.listdir(d):
        if f.startswith(("on_", "off_")) and f.endswith(".ogg"):
            os.remove(os.path.join(d, f))
    for name, y in clips.items():
        write(os.path.join(d, name + ".ogg"), y * gain, keep_wav)
    with open(os.path.join(d, "engine.json"), "w") as fh:
        json.dump({"source": "recorded", "pitch_exponent": round(float(e), 3)}, fh, indent=1)
        fh.write("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--car")
    ap.add_argument("--wav", action="store_true")
    args = ap.parse_args()
    for car, cfg in SOURCES.items():
        if args.car and car != args.car:
            continue
        build(car, cfg, args.wav)


if __name__ == "__main__":
    main()
