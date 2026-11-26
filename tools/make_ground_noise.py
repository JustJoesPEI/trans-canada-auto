#!/usr/bin/env python3
"""Makes textures/ground/noise.png: four tiling value-noise fbm patterns,
one per channel, that the ground shader (shaders/terrain_ground.gdshader)
reads instead of working the same broad noise out per pixel.

The shader's d_fbm (shaders/include/detail.gdshaderinc) is three octaves
of smoothed value noise (weights 0.5, 0.3, 0.2); a lawn pixel used to
work out about six of them, a dozen hashes each. This is the same kind of
noise, made once: 32 lattice cells across the 256-pixel square (8 pixels
a cell, so the GPU's filtering is as smooth as the shader's own), octaves
at 2x and 4x so it tiles, a different seed per channel. The shader reads
it at `p / 32.0` for d_fbm(p).

    python3 tools/make_ground_noise.py

Imported lossless with mipmaps (textures/ground/noise.png.import): block
compression keeps one colour line per 4x4 block, which bands four
unrelated channels; at 256 px it's 341 KB with its mipmaps.
"""
import os
import numpy as np
from PIL import Image

SIZE = 256
CELLS = 32
OCTAVES = ((1, 0.5), (2, 0.3), (4, 0.2))


def value_noise(cells: int, rng: np.random.Generator) -> np.ndarray:
    lattice = rng.random((cells, cells))
    t = (np.arange(SIZE) + 0.5) / SIZE * cells
    i0 = np.floor(t).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    u = f * f * (3.0 - 2.0 * f)
    # rows (y) then columns (x)
    a = lattice[np.ix_(i0, i0)]
    b = lattice[np.ix_(i0, i1)]
    c = lattice[np.ix_(i1, i0)]
    d = lattice[np.ix_(i1, i1)]
    ux = u[None, :]
    uy = u[:, None]
    return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy


def fbm(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    out = np.zeros((SIZE, SIZE))
    for mul, w in OCTAVES:
        out += value_noise(CELLS * mul, rng) * w
    return out


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    dest = os.path.join(here, "..", "textures", "ground", "noise.png")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    chans = [fbm(seed) for seed in (11, 23, 37, 53)]
    img = np.stack(chans, axis=-1)
    Image.fromarray(np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8), "RGBA").save(dest)
    print("wrote", os.path.normpath(dest))


if __name__ == "__main__":
    main()
