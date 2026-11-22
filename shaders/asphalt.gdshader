// Asphalt for every street. Weathered grey with aggregate grain, darker
// repair patches, hairline cracks, polished wheel paths, oil drips down the
// middle of each lane and road grime along the gutters.
//   UV   = metres * 0.25 (world position)
//   UV2  x = metres from the right-hand curb, or -1 in a junction box
//        y = the street's half width (negative on one-way streets)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.3, 0.3, 0.31);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float px = length(fwidth(p)); // metres per pixel here
	float fine_ok = 1.0 - smoothstep(0.02, 0.08, px);

	// Big soft blotches of older and newer surface.
	float big = d_fbm(p * 0.07);
	vec3 c = base_color * (0.8 + 0.35 * big);
	// Aggregate: light and dark stones in the binder, faded out at a distance.
	float grain = d_noise(p * 45.0);
	c *= mix(1.0, 0.86 + 0.28 * grain, fine_ok * 0.7);
	float rough = 0.93;
	float h = 0.0;

	// Repair patches: a few rectangles of darker, newer asphalt.
	vec2 cell = floor(p / 7.0);
	float pick = d_hash(cell + 3.7);
	if (pick < 0.1) {
		vec2 q = fract(p / 7.0);
		vec2 lo = vec2(0.1, 0.15) + 0.2 * vec2(d_hash(cell + 1.1), d_hash(cell + 2.3));
		vec2 hi = lo + vec2(0.15, 0.12) + 0.2 * vec2(d_hash(cell + 4.1), d_hash(cell + 5.9));
		vec2 e = min(q - lo, hi - q) * 7.0;
		float inside = step(0.0, min(e.x, e.y));
		float seam = inside * (1.0 - smoothstep(0.0, 0.06, min(e.x, e.y)));
		c = mix(c, c * 0.8, inside);
		c *= 1.0 - seam * 0.5;
		h -= seam * 0.6;
	}

	// Hairline cracks: thin ridges of a noise field, only in some areas.
	float crack_area = smoothstep(0.55, 0.75, d_noise(p * 0.11 + 40.0));
	float cn = abs(d_noise(p * 0.9) - 0.5) + abs(d_noise(p * 2.1 + 9.0) - 0.5) * 0.35;
	float crack = crack_area * (1.0 - smoothstep(0.0, 0.012 + px * 0.6, cn)) * fine_ok;
	c *= 1.0 - crack * 0.4;
	h -= crack;

	// Where across the street are we?
	float across = UV2.x;
	float hw = abs(UV2.y);
	if (across >= 0.0 && hw > 0.5) {
		float w = hw * 2.0;
		float dc = min(across, w - across); // metres from the nearest curb
		// The travel lane's centre, measured from each curb: wide streets
		// have a parking lane against the curb first.
		float lane = clamp(hw - 1.9, 1.7, 4.4);
		// Wheel paths: smoother and a touch darker where the tyres run.
		float wp = exp(-pow((dc - (lane - 0.82)) / 0.32, 2.0)) + exp(-pow((dc - (lane + 0.82)) / 0.32, 2.0));
		c *= 1.0 - 0.1 * wp;
		rough -= 0.16 * wp;
		// Oil drips down the middle of the lane.
		float drip = exp(-pow((dc - lane) / 0.35, 2.0)) * smoothstep(0.45, 0.85, d_fbm(p * vec2(0.9, 0.9) + 11.0));
		c *= 1.0 - 0.22 * drip;
		rough -= 0.25 * drip;
		// Gutter: grit and dust along the curb, with a seam at the curb itself.
		float gutter = 1.0 - smoothstep(0.05, 0.55, dc);
		float grit = d_fbm(p * 1.3 + 3.0);
		c = mix(c, d_lin(vec3(0.42, 0.39, 0.34)) * (0.7 + 0.5 * grit), gutter * 0.55);
		c *= 1.0 - (1.0 - smoothstep(0.0, 0.06, dc)) * 0.35;
	} else if (across < 0.0) {
		// Junction box: turning traffic polishes it unevenly.
		float wear = d_fbm(p * 0.25 + 7.0);
		rough -= 0.12 * smoothstep(0.4, 0.8, wear);
		c *= 1.0 - 0.08 * smoothstep(0.4, 0.8, wear);
	}

	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	if (gfx_detail > 0.5 && fine_ok > 0.0) {
		float grain_h = (grain - 0.5) * 0.25 * fine_ok;
		NORMAL = d_bump(NORMAL, VERTEX, h * 0.01 + grain_h * 0.004, 1.0);
	}
}
