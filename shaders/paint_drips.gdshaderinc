// Drips on fresh paint (docs/design.md section 3: "fresh splats run a
// little for the first 20 s, done in the shader"). Shared by the world
// splats (paint_splat.gdshader) and the paint on cars and people
// (paint_overlay.gdshader). Nothing is updated per splat while it runs:
// each splat carries the time it landed, and `paint_now` (a global shader
// uniform PaintSplats sets once a frame) says how old it is.
//
// p: the point in the splat's own space, in splat radii, x across and y
// down the surface (downhill). seed: 0..1, different for each splat.
// age: seconds since it landed. room: 0..1, how far it may run (0 on the
// flat, or where the surface ends just under it).
// Returns how much drip paint covers p (0..1).

global uniform float paint_now;

// s: how long drips run (design: 20 s).
const float DRIP_TIME = 20.0;
// Splat radii: how far the longest drip gets below the splat's middle.
const float DRIP_LEN = 1.2;

// 0..1 along the run: quick at first, slowing, still at DRIP_TIME.
float drip_run(float age) {
	float t = clamp(age / DRIP_TIME, 0.0, 1.0);
	return 1.0 - (1.0 - t) * (1.0 - t);
}

float drip_hash(float n) {
	return fract(sin(n * 78.233 + 12.9898) * 43758.5453);
}

float drips(vec2 p, float seed, float age, float room) {
	if (room <= 0.0 || age <= 0.0) {
		return 0.0;
	}
	float run = drip_run(age) * room;
	float aa = max(fwidth(p.x), 0.002) * 1.2;
	float m = 0.0;
	// Three runs from the lower half of the splat, of different lengths.
	for (int k = 0; k < 3; k++) {
		float h = drip_hash(seed * 17.0 + float(k) * 3.1);
		float x = (h - 0.5) * 1.1;
		float w = 0.05 + 0.05 * drip_hash(h * 9.7);
		float len = run * DRIP_LEN * mix(0.35, 1.0, drip_hash(h * 5.3));
		float y0 = 0.2;
		float y1 = 0.4 + len;
		// A strand thinning as it goes, and a bead at its end.
		float along = clamp((p.y - y0) / max(y1 - y0, 0.001), 0.0, 1.0);
		float half_w = w * mix(1.0, 0.65, along);
		float strand = (1.0 - smoothstep(half_w - aa, half_w + aa, abs(p.x - x)))
			* step(y0, p.y) * (1.0 - smoothstep(y1 - aa, y1 + aa, p.y));
		float bead = 1.0 - smoothstep(w * 1.3 - aa, w * 1.3 + aa, length(p - vec2(x, y1)));
		m = max(m, max(strand, bead * step(0.02, len)));
	}
	return m;
}
