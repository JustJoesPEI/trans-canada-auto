// Asphalt for every street. Weathered grey with aggregate grain, darker
// repair patches, hairline cracks, polished wheel paths, oil drips down the
// middle of each lane and road grime along the gutters. Near the camera,
// marks from the street-marks array (include/street_marks.gdshaderinc):
// cracking, sealed cracks, patches, oil, tyre marks and ravelling in a
// 6 m grid, manhole covers down the lanes and in junctions, storm drains
// along the gutters.
//   UV   = metres * 0.25 (world position)
//   UV2  x = metres from the right-hand curb, or -1 in a junction box
//        y = the street's half width (negative on one-way streets)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"
#include "res://shaders/include/street_marks.gdshaderinc"

// The grid the scattered marks are placed in (metres); a mark stays inside
// its cell, so a pixel only ever reads its own cell's.
const float MARK_CELL = 6.0;

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
	float rough = 0.93;
	float h = 0.0;
	// Aggregate (light and dark stones in the binder) and hairline cracks:
	// close-up detail, faded out by a few metres a pixel, so only worked
	// out where it shows.
	float grain = 0.5;
	if (fine_ok > 0.0) {
		grain = d_noise(p * 45.0);
		c *= mix(1.0, 0.86 + 0.28 * grain, fine_ok * 0.7);
		// Cracks: thin ridges of a noise field, only in some areas.
		float crack_area = smoothstep(0.55, 0.75, d_noise(p * 0.11 + 40.0));
		if (crack_area > 0.0) {
			float cn = abs(d_noise(p * 0.9) - 0.5) + abs(d_noise(p * 2.1 + 9.0) - 0.5) * 0.35;
			float crack = crack_area * (1.0 - smoothstep(0.0, 0.012 + px * 0.6, cn)) * fine_ok;
			c *= 1.0 - crack * 0.4;
			h -= crack;
		}
	}

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

	// Where across the street are we?
	float across = UV2.x;
	float hw = abs(UV2.y);

	// Marks, near only: at most two reads a pixel (a scattered mark from
	// the grid, and a manhole cover or storm drain).
	vec2 dpx = dFdx(p);
	vec2 dpy = dFdy(p);
	float dax = dFdx(across);
	float day = dFdy(across);
	// Marks are bigger than the grain, so they fade out further away.
	float mark_ok = 1.0 - smoothstep(0.05, 0.14, px);
	if (mark_ok > 0.0) {
		vec4 mark = vec4(0.5, 0.5, 0.5, 0.0);
		float mark_layer = 0.0;
		vec2 cell = floor(p / MARK_CELL);
		float r0 = d_hash(cell + 17.3);
		if (r0 < 0.42) {
			float r1 = d_hash(cell + 5.1);
			float r2 = d_hash(cell + 8.7);
			float size;
			if (r1 < 0.2) { mark_layer = 0.0; size = 3.0 + 1.5 * r2; }
			else if (r1 < 0.4) { mark_layer = 1.0; size = 3.0 + 2.0 * r2; }
			else if (r1 < 0.55) { mark_layer = 2.0; size = 1.6 + 1.4 * r2; }
			else if (r1 < 0.75) { mark_layer = 5.0; size = 0.9 + 0.8 * r2; }
			else if (r1 < 0.85) { mark_layer = 6.0; size = 3.0 + 1.0 * r2; }
			else { mark_layer = 7.0; size = 1.5 + 1.5 * r2; }
			float half_size = size * 0.5;
			vec2 jitter = vec2(d_hash(cell + 2.9), d_hash(cell + 11.3)) - 0.5;
			vec2 centre = (cell + 0.5) * MARK_CELL + jitter * max(MARK_CELL - 2.0 * half_size * 1.05, 0.0);
			mat2 rot = mark_rot(d_hash(cell + 23.1) * 6.2832);
			mark = street_mark(rot * (p - centre) / half_size, rot * dpx / half_size, rot * dpy / half_size, mark_layer);
		}
		// Manholes and drains go by the street's own lines: along it (from
		// the way `across` grows over the ground) and across it.
		vec4 fixture = vec4(0.5, 0.5, 0.5, 0.0);
		float fixture_layer = 3.0;
		float det = dpx.x * dpy.y - dpx.y * dpy.x;
		if (across >= 0.0 && hw > 0.5 && abs(det) > 1e-12) {
			vec2 g = vec2(dax * dpy.y - day * dpx.y, dpx.x * day - dpy.x * dax) / det;
			if (dot(g, g) > 0.25) {
				vec2 t = normalize(vec2(-g.y, g.x));
				float along = dot(p, t);
				float w = hw * 2.0;
				bool far_side = across > hw;
				float dc = far_side ? w - across : across;
				float lane = clamp(hw - 1.9, 1.7, 4.4);
				vec2 dq = vec2(dot(dpx, t), far_side ? -dax : dax);
				vec2 dqy2 = vec2(dot(dpy, t), far_side ? -day : day);
				if (dc < 1.2) {
					// A storm drain in the gutter every 25 m or so, on one side.
					float k = floor(along / 25.0);
					float hh = d_hash(vec2(k, floor(hw * 4.0)) + 41.0);
					if (hh < 0.85 && (hh < 0.42) == far_side) {
						float ac = (k + 0.25 + 0.5 * d_hash(vec2(k, 3.0))) * 25.0;
						vec2 q = vec2(along - ac, dc - 0.3) / 0.5;
						fixture = street_mark(q, dq / 0.5, dqy2 / 0.5, 4.0);
						fixture_layer = 4.0;
					}
				} else if (abs(dc - lane) < 0.6) {
					// A manhole cover in the middle of a lane every 35 m or so.
					float k = floor(along / 35.0);
					float hh = d_hash(vec2(k, floor(hw * 4.0)) + 57.0);
					if (hh < 0.7 && (hh < 0.35) == far_side) {
						float ac = (k + 0.2 + 0.6 * d_hash(vec2(k, 9.0))) * 35.0;
						vec2 q = vec2(along - ac, dc - lane) / 0.42;
						fixture = street_mark(q, dq / 0.42, dqy2 / 0.42, 3.0);
					}
				}
			}
		} else if (across < 0.0) {
			// Junctions: the odd manhole cover near the middle.
			vec2 jc = floor(p / 14.0);
			if (d_hash(jc + 61.0) < 0.3) {
				vec2 centre = (jc + 0.5 + (vec2(d_hash(jc + 1.7), d_hash(jc + 6.1)) - 0.5) * 0.4) * 14.0;
				fixture = street_mark((p - centre) / 0.42, dpx / 0.42, dpy / 0.42, 3.0);
			}
		}
		float ma = mark.a * mark_ok;
		c = mix(c, c * mark.rgb * 2.0, ma);
		h -= ma * max(0.0, 1.0 - mark.r * 2.0) * 0.8;
		if (MARK_ROUGH[int(mark_layer)] > 0.0) rough = mix(rough, MARK_ROUGH[int(mark_layer)], ma);
		float fa = fixture.a * mark_ok;
		c = mix(c, c * fixture.rgb * 2.0, fa);
		h += fa * (fixture.r * 2.0 - 1.0) * 0.6;
		rough = mix(rough, MARK_ROUGH[int(fixture_layer)], fa);
	}
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
