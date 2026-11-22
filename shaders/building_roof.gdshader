// Roofs (and shop awnings) for every generated building, in one material.
//   COLOR rgb = colour (linear)
//   UV2   x = 0 flat roof, 1 shingled pitched roof or spire,
//           2 striped canvas awning, 3 plain canvas awning, 4 copper
//   UV    x = metres across, y = metres up the slope
//   fade  0 on the shared material; a faded copy is made only while a
//         building hides the player (see camera_rig.gd)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/include/detail.gdshaderinc"

uniform float fade = 0.0;
// Buildings are merged a chunk at a time; CUSTOM0.r is each vertex's
// building number in its chunk. A faded copy of the material can fade up to
// four of them by number (fade_ids) by their own amounts (fade_levels).
uniform vec4 fade_ids = vec4(-1.0);
uniform vec4 fade_levels = vec4(0.0);
varying flat float building_id;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	building_id = CUSTOM0.r;
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	float f = fade;
	if (fade_levels != vec4(0.0)) {
		vec4 hit = vec4(equal(fade_ids, vec4(building_id)));
		f = max(f, max(max(hit.x * fade_levels.x, hit.y * fade_levels.y), max(hit.z * fade_levels.z, hit.w * fade_levels.w)));
	}
	if (f > 0.0 && ign(FRAGCOORD.xy) < f) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float rough = 0.88;
	float kind = UV2.x;
	float h = 0.0;
	float px = length(fwidth(UV));
	float fine_ok = 1.0 - smoothstep(0.02, 0.07, px);
	if (kind > 0.5 && kind < 1.5) {
		// Asphalt shingles: courses of tabs, each a slightly different shade,
		// streaked and weathered, with the odd darker replacement.
		float course = floor(UV.y / 0.2);
		float fy = fract(UV.y / 0.2);
		float tx = UV.x / 0.45 + course * 0.5 + d_hash(vec2(course, 1.0)) * 0.3;
		float tab = floor(tx);
		float th = d_hash(vec2(tab, course));
		c *= 0.82 + 0.3 * th;
		c *= th > 0.95 ? 0.7 : 1.0;
		c *= 0.84 + 0.16 * step(0.15, fy);
		c *= 0.94 + 0.08 * step(0.5, fract(tx));
		// Streaks running down the slope, and moss low on the roof.
		c *= 0.88 + 0.16 * d_noise(vec2(UV.x * 1.5, UV.y * 0.15));
		float moss = smoothstep(0.62, 0.85, d_fbm(UV * 0.8)) * (1.0 - smoothstep(0.5, 3.0, UV.y));
		c = mix(c, d_lin(vec3(0.3, 0.33, 0.2)) * 0.6, moss * 0.5);
		h = fy * 0.6 + (1.0 - smoothstep(0.0, 0.03, fract(tx))) * -0.4;
	} else if (kind > 1.5 && kind < 2.5) {
		c = mix(c, vec3(0.8, 0.79, 0.74), step(0.5, fract(UV.x / 0.6)));
		c *= 0.92 + 0.1 * d_noise(UV * 3.0);
		rough = 0.95;
	} else if (kind > 2.5 && kind < 3.5) {
		c *= 0.92 + 0.1 * d_noise(UV * 3.0);
		rough = 0.95;
	} else if (kind > 3.5) {
		c *= 0.9 + 0.1 * step(0.08, fract(UV.x / 0.5));
		// Copper weathers unevenly toward green.
		c *= 0.85 + 0.25 * d_fbm(UV * 0.7);
		rough = 0.5;
		h = -step(fract(UV.x / 0.5), 0.08);
	} else {
		// Flat roofs: tar and gravel with membrane seams and ponding stains.
		vec2 q = wpos.xz;
		c *= 0.8 + 0.3 * d_fbm(q * 0.25);
		c *= 0.9 + 0.2 * d_noise(q * 25.0) * fine_ok;
		float seam = 1.0 - smoothstep(0.0, 0.03 + px, abs(fract(q.x / 1.0 + 0.5) - 0.5) * 1.0);
		c *= 1.0 - 0.25 * seam;
		float pond = smoothstep(0.6, 0.8, d_fbm(q * 0.12 + 3.0));
		c *= 1.0 - 0.25 * pond;
		rough = mix(0.92, 0.6, pond);
		h = -seam;
	}
	if (gfx_detail > 0.5 && fine_ok > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, h * 0.01 * fine_ok, 1.0);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
