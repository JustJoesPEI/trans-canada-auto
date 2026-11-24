"""Follows an engine's revs through a recording, from the pitch of its firing.

Used by tools/make_recorded_engines.py. The engine's firing frequency is the
one whose whole harmonic series (1x, 2x, 3x...) stands out from the noise;
a dynamic-programming pass then picks the smoothest path through time, so
a gear change or a gust of wind can't make the track jump an octave.

    track(x, sr, fmin, fmax) -> (times, firing_hz, strength)
"""

import numpy as np
from scipy import signal


def track(x, sr, fmin, fmax, hop=0.025, win=0.2, harmonics=6, max_step=0.06):
    nwin = int(win * sr)
    nfft = 1 << int(np.ceil(np.log2(nwin * 4)))
    f, t, Z = signal.stft(x, sr, window="hann", nperseg=nwin, noverlap=nwin - int(hop * sr), nfft=nfft,
                          boundary=None, padded=False)
    mag = np.log(np.abs(Z) + 1e-9)
    # Flatten the broad spectral shape so loud noise bands don't win.
    env = np.apply_along_axis(lambda c: signal.medfilt(c, 31), 0, mag)
    mag = np.maximum(mag - env, 0.0)
    cands = np.exp(np.arange(np.log(fmin), np.log(fmax), 0.004))
    score = np.zeros((len(cands), mag.shape[1]))
    df = f[1] - f[0]
    for k in range(1, harmonics + 1):
        fi = cands * k / df
        ok = fi < len(f) - 2
        i0 = np.floor(fi[ok]).astype(int)
        a = fi[ok] - i0
        v = mag[i0] * (1 - a)[:, None] + mag[i0 + 1] * a[:, None]
        score[ok] += v / (1 + 0.15 * (k - 1))
    # Penalize half-pitch candidates whose odd harmonics are empty.
    half = np.zeros_like(score)
    for k in (1, 3, 5):
        fi = cands * (k - 0.5) / df
        ok = fi < len(f) - 2
        i0 = np.floor(fi[ok]).astype(int)
        half[ok] += mag[i0]
    score -= 0.5 * half
    # Viterbi: reward score, penalize pitch jumps (log-frequency distance).
    steps = int(np.ceil(np.log(1 + max_step) / 0.004))
    n, m = score.shape
    acc = score[:, 0].copy()
    back = np.zeros((n, m), dtype=np.int32)
    offs = np.arange(-steps, steps + 1)
    pen = 0.6 * np.abs(offs) / steps
    for j in range(1, m):
        best = np.full(n, -1e18)
        arg = np.zeros(n, dtype=np.int32)
        for o, p in zip(offs, pen):
            src = np.clip(np.arange(n) - o, 0, n - 1)
            v = acc[src] - p
            better = v > best
            best[better] = v[better]
            arg[better] = src[better]
        acc = best + score[:, j]
        back[:, j] = arg
    path = np.zeros(m, dtype=int)
    path[-1] = int(np.argmax(acc))
    for j in range(m - 1, 0, -1):
        path[j - 1] = back[path[j], j]
    hz = cands[path]
    strength = score[path, np.arange(m)]
    return t, signal.medfilt(hz, 5), strength
