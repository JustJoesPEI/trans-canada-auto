// The open ground between the streets, draped over the real terrain.
// The ground mask says what covers each spot (R lawn, G parking and other
// asphalt, B what else it is: 255 stone-paved square, 190 farm field, 125
// wetland, 60 sand; A path: 255 brick, 100 gravel trail); anything else is
// rough grass. Colours are written in sRGB and converted.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

uniform sampler2D ground_mask : filter_linear, repeat_disable;
uniform vec2 mask_origin;
uniform vec2 mask_size = vec2(1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.3) * 0.3 + vnoise(p * 5.1) * 0.15;
}

// Running-bond pavers of a given size, with joints.
vec3 pavers(vec2 m, vec3 col, vec3 joint, float len, float wid) {
	float row = floor(m.y / wid);
	float x = m.x / len + mod(row, 2.0) * 0.5;
	float bx = fract(x);
	float by = fract(m.y / wid);
	float j = max(step(bx, 0.03), step(by, 0.06)) * 0.6;
	vec3 c = col * (0.88 + 0.18 * hash(vec2(floor(x), row)));
	return mix(c, joint, j);
}

// B holds one kind per pixel, so it's read as four pixels round the spot,
// each sorted into what it is, and those blended: two neighbouring kinds
// never smear into a third between them. (plaza, field, wetland, sand)
vec4 b_kinds(vec2 uv) {
	ivec2 sz = textureSize(ground_mask, 0);
	vec2 t = uv * vec2(sz) - 0.5;
	ivec2 i0 = ivec2(floor(t));
	vec2 f = fract(t);
	vec4 k = vec4(0.0);
	for (int j = 0; j < 4; j++) {
		ivec2 c = ivec2(j & 1, j >> 1);
		float b = texelFetch(ground_mask, clamp(i0 + c, ivec2(0), sz - 1), 0).b;
		vec4 one = vec4(step(0.87, b), step(0.62, b) * step(b, 0.87), step(0.36, b) * step(b, 0.62), step(0.12, b) * step(b, 0.36));
		vec2 wt = mix(1.0 - f, f, vec2(c));
		k += one * wt.x * wt.y;
	}
	return k;
}

void fragment() {
	vec2 uv = (wpos.xz - mask_origin) / mask_size;
	vec4 w = vec4(0.0);
	vec4 raw = vec4(0.0);
	vec3 soft = vec3(0.0); // field, wetland, sand
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		raw = texture(ground_mask, uv);
		vec4 k = b_kinds(uv);
		w = vec4(raw.rg, k.x, raw.a);
		// Crisp edges: the map is half a metre per pixel, so sharpen the
		// blend between areas into a clean line a few centimetres wide.
		// Ragged, worn borders instead of ruler-straight ones.
		float edge_n = d_fbm(wpos.xz * 0.9) - 0.5;
		w = smoothstep(vec4(0.36), vec4(0.64), w + vec4(edge_n * 0.35, edge_n * 0.12, edge_n * 0.12, 0.0));
		soft = smoothstep(vec3(0.3), vec3(0.7), k.yzw + vec3(edge_n * 0.3));
	}
	float n = fbm(wpos.xz * 0.12);
	float fine = vnoise(wpos.xz * 1.7);
	// Ground nobody has mapped: rough grass, a little duller than a lawn.
	vec3 lot = lin(mix(vec3(0.3, 0.34, 0.2), vec3(0.46, 0.44, 0.3), d_fbm(wpos.xz * 0.04))) * (0.85 + 0.25 * fine);
	// Lawns: patchy green with drier yellowish spots and a fine blade texture
	// up close.
	float px = length(fwidth(wpos.xz));
	float near = 1.0 - smoothstep(0.02, 0.08, px);
	float blades = d_noise(wpos.xz * vec2(38.0, 31.0)) * 0.5 + d_noise(wpos.xz * vec2(23.0, 47.0) + 3.0) * 0.5;
	float dry = smoothstep(0.55, 0.85, d_fbm(wpos.xz * 0.18 + 21.0));
	// Big, slow patches (tens of metres) so a lawn never reads as one flat
	// colour: greener damp hollows, straw-coloured dry stretches, clover.
	float macro = d_fbm(wpos.xz * 0.025 + 3.0);
	float mid = d_fbm(wpos.xz * 0.11 + 9.0);
	vec3 grass = lin(mix(vec3(0.24, 0.33, 0.15), vec3(0.4, 0.45, 0.24), macro));
	grass = mix(grass, lin(vec3(0.2, 0.3, 0.14)), smoothstep(0.55, 0.8, mid) * 0.5);
	grass = mix(grass, lin(vec3(0.5, 0.47, 0.3)), dry * 0.65);
	// Worn, browner grass along the edge of paths and pavement.
	float worn = (1.0 - smoothstep(0.55, 0.95, raw.r)) * step(0.3, raw.r);
	grass = mix(grass, lin(vec3(0.42, 0.38, 0.27)), worn * (0.5 + 0.5 * fine));
	grass *= (0.9 + 0.15 * fine) * mix(1.0, 0.75 + 0.45 * blades, near);
	// Parking lots: asphalt like the streets, with darker oil stains and
	// lighter patched areas. The stall lines are painted on separately.
	float stain = smoothstep(0.62, 0.8, d_noise(wpos.xz * vec2(0.9, 2.3)));
	vec3 parking = lin(vec3(0.3, 0.3, 0.31)) * (0.84 + 0.24 * n) * (1.0 - 0.25 * stain);
	parking = mix(parking, lin(vec3(0.36, 0.36, 0.36)), 0.5 * smoothstep(0.6, 0.75, fbm(wpos.xz * 0.05 + 7.0)));
	vec3 plaza = lin(pavers(wpos.xz, vec3(0.64, 0.61, 0.56), vec3(0.5, 0.48, 0.45), 0.6, 0.4));
	vec3 path = lin(pavers(wpos.xz, vec3(0.55, 0.4, 0.35), vec3(0.55, 0.52, 0.48), 0.2, 0.1));
	vec3 gravel = lin(vec3(0.55, 0.5, 0.42)) * (0.85 + 0.2 * fine);
	// The path channel: 255 is a brick footpath, about 100 a gravel trail.
	float a_raw = raw.a;
	float brick = smoothstep(0.7, 0.85, a_raw);
	float trail = smoothstep(0.28, 0.36, a_raw) * (1.0 - brick);
	// Farm fields: PEI's red soil in potato drills, ridges about 0.9 m
	// apart across x (the tyres feel the same furrows, GroundMap.bump_at),
	// young plants along the ridge tops, thicker in some stretches than
	// others, and darker wet hollows.
	float rows_seen = 1.0 - smoothstep(0.04, 0.22, px);
	float ridge = 0.5 + 0.5 * sin(wpos.x * 6.2832 / 0.9);
	float growth = mix(0.25, 0.8, smoothstep(0.3, 0.7, d_fbm(wpos.xz * 0.012 + 40.0)));
	float leaves = d_noise(wpos.xz * vec2(4.0, 6.0)) * 0.65 + d_noise(wpos.xz * vec2(13.0, 17.0)) * 0.35;
	float plants = smoothstep(0.55, 0.95, ridge) * smoothstep(1.0 - growth, 1.1 - growth, leaves) * 0.9;
	float wet_soil = smoothstep(0.55, 0.75, d_fbm(wpos.xz * 0.05 + 11.0));
	vec3 soil = lin(mix(vec3(0.44, 0.26, 0.19), vec3(0.31, 0.17, 0.12), wet_soil * 0.8)) * (0.88 + 0.2 * fine);
	soil *= mix(1.0, 0.75 + 0.35 * ridge, rows_seen);
	vec3 crop = lin(vec3(0.23, 0.33, 0.14)) * (0.7 + 0.45 * leaves);
	// From afar the rows blur into a green tint over the soil.
	vec3 field = mix(soil, crop, mix(growth * 0.3, plants, rows_seen));
	// Wetland: dark sedge with standing water between the tussocks.
	float pool = smoothstep(0.6, 0.7, d_fbm(wpos.xz * 0.15 + 5.0));
	vec3 bog = mix(lin(vec3(0.26, 0.29, 0.15)) * (0.75 + 0.4 * fine), lin(vec3(0.1, 0.11, 0.09)), pool);
	// Sand: beaches and the golf course's bunkers.
	vec3 sand = lin(vec3(0.74, 0.67, 0.52)) * (0.9 + 0.15 * fine);
	vec3 c = lot;
	c = mix(c, grass, w.r);
	c = mix(c, field, soft.x);
	c = mix(c, bog, soft.y);
	c = mix(c, sand, soft.z);
	c = mix(c, parking, w.g);
	c = mix(c, plaza, w.b);
	c = mix(c, gravel, trail);
	c = mix(c, path, brick);
	ALBEDO = c;
	ROUGHNESS = mix(mix(0.97, 0.88, max(w.g, w.b)), 0.15, pool * soft.y);
	if (gfx_detail > 0.5 && near > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, blades * 0.006 * near * w.r, 1.0);
	}
	if (gfx_detail > 0.5 && rows_seen > 0.0 && soft.x > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, ridge * 0.06 * rows_seen * soft.x, 1.0);
	}
}
