// The body of building_roof.gdshader and building_roof_fade.gdshader (which defines
// FADE: only the faded copies of the material, for the few buildings in the
// camera's way, can discard; the shared one can't, so the town's buildings
// keep the depth test's early-out).

#include "res://shaders/include/detail.gdshaderinc"

uniform float fade = 0.0;
// Buildings are merged a chunk at a time; CUSTOM0.r is each vertex's
// building number in its chunk. A faded copy of the material can fade up to
// four of them by number (fade_ids) by their own amounts (fade_levels).
uniform vec4 fade_ids = vec4(-1.0);
uniform vec4 fade_levels = vec4(0.0);
varying flat float building_id;

varying vec3 wpos;
// The roofs' material layers (textures/facade/roof_materials.png: layer 0
// is MAT_ASPHALT_SHINGLE in the shared tables), see building_wall_body.
uniform sampler2DArray roof_materials : filter_linear_mipmap_anisotropic, repeat_enable;
#include "res://shaders/include/building_materials.gdshaderinc"

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
#ifdef FADE
	if (f > 0.0 && ign(FRAGCOORD.xy) < f) {
		discard;
	}
#endif
	vec3 c = COLOR.rgb;
	float rough = 0.88;
	float metal = 0.0;
	float kind = UV2.x;
	float h = 0.0;
	float px = length(fwidth(UV));
	float fine_ok = 1.0 - smoothstep(0.02, 0.07, px);
	float h_scale = 0.01;
	// Pitched roofs, copper and flat roofs take a material layer: one
	// array read on every level. A quarter of the pitched roofs are
	// standing-seam metal, as so many on the Island are.
	int layer = -1;
	vec2 tuv = UV;
	float pick = d_hash(COLOR.rg * 71.0 + building_id * 0.61);
	if (kind > 0.5 && kind < 1.5) {
		layer = pick < 0.25 ? MAT_STANDING_SEAM : MAT_ASPHALT_SHINGLE;
	} else if (kind > 3.5) {
		layer = MAT_STANDING_SEAM;
	} else if (kind < 0.5) {
		layer = MAT_FLAT_ROOF;
		tuv = wpos.xz;
	}
	vec2 tex_grad = vec2(0.0);
	if (layer >= 0) {
		// Up the slope is down the texture (the tool draws the top row at the top).
		vec2 tscale = vec2(1.0, -1.0) / MAT_TILE[layer];
		vec2 s = tuv * tscale + vec2(pick * 5.0, 0.0);
		float li = float(layer - MAT_ASPHALT_SHINGLE);
		vec3 m = texture(roof_materials, vec3(s, li)).rgb;
		if (gfx_detail > 0.5 && fine_ok > 0.0) {
			vec2 e = max(fwidth(s), vec2(1.0 / 512.0));
			float hx = texture(roof_materials, vec3(s + vec2(e.x, 0.0), li)).b;
			float hy = texture(roof_materials, vec3(s - vec2(0.0, e.y), li)).b;
			tex_grad = vec2(hx - m.b, hy - m.b) / (e * MAT_TILE[layer]) * MAT_RELIEF[layer] * fine_ok;
		}
		vec3 jc = MAT_JOINT_K[layer] > 0.0 ? c * MAT_JOINT_K[layer] : MAT_JOINT[layer];
		c = mix(c, jc, m.g) * m.r * 2.0;
		rough = MAT_ROUGH[layer];
	}
	if (layer == MAT_ASPHALT_SHINGLE) {
		// Streaks running down the slope, and moss low on the roof.
		c *= 0.9 + 0.14 * d_noise(vec2(UV.x * 1.5, UV.y * 0.15));
		float moss = smoothstep(0.62, 0.85, d_fbm(UV * 0.8)) * (1.0 - smoothstep(0.5, 3.0, UV.y));
		c = mix(c, d_lin(vec3(0.3, 0.33, 0.2)) * 0.6, moss * 0.5);
	} else if (layer == MAT_STANDING_SEAM) {
		// Painted metal fades in broad patches; copper weathers toward green.
		c *= 0.88 + 0.2 * d_fbm(UV * 0.4 + pick * 9.0);
		metal = kind > 3.5 ? 0.3 : 0.5;
	} else if (layer == MAT_FLAT_ROOF) {
		// Broad patching and ponding stains.
		vec2 q = wpos.xz;
		c *= 0.85 + 0.25 * d_fbm(q * 0.25);
		float pond = smoothstep(0.6, 0.8, d_fbm(q * 0.12 + 3.0));
		c *= 1.0 - 0.25 * pond;
		rough = mix(rough, 0.6, pond);
	} else if (kind > 1.5 && kind < 2.5) {
		c = mix(c, vec3(0.8, 0.79, 0.74), step(0.5, fract(UV.x / 0.6)));
		c *= 0.92 + 0.1 * d_noise(UV * 3.0);
		rough = 0.95;
	} else {
		c *= 0.92 + 0.1 * d_noise(UV * 3.0);
		rough = 0.95;
	}
	if (gfx_detail > 0.5 && fine_ok > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, h * h_scale * fine_ok, 1.0);
		if (tex_grad != vec2(0.0)) {
			NORMAL = d_tex_bump(NORMAL, VERTEX, tuv, tex_grad);
		}
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
}
