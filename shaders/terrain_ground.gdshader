// The open ground between the streets, draped over the real terrain.
// The ground mask says what covers each spot (R lawn, G parking and other
// asphalt, B stone-paved square, A path: 255 brick, 100 gravel trail);
// anything else is rough grass. Colours are written in sRGB and converted.
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

void fragment() {
	vec2 uv = (wpos.xz - mask_origin) / mask_size;
	vec4 w = vec4(0.0);
	vec4 raw = vec4(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		raw = texture(ground_mask, uv);
		w = raw;
		// Crisp edges: the map is half a metre per pixel, so sharpen the
		// blend between areas into a clean line a few centimetres wide.
		w = smoothstep(vec4(0.4), vec4(0.6), w);
	}
	float n = fbm(wpos.xz * 0.12);
	float fine = vnoise(wpos.xz * 1.7);
	// Ground nobody has mapped: rough grass, a little duller than a lawn.
	vec3 lot = lin(mix(vec3(0.29, 0.37, 0.2), vec3(0.4, 0.44, 0.27), n)) * (0.9 + 0.14 * fine);
	// Lawns: patchy green with drier yellowish spots and a fine blade texture
	// up close.
	float px = length(fwidth(wpos.xz));
	float near = 1.0 - smoothstep(0.02, 0.08, px);
	float blades = d_noise(wpos.xz * vec2(38.0, 31.0)) * 0.5 + d_noise(wpos.xz * vec2(23.0, 47.0) + 3.0) * 0.5;
	float dry = smoothstep(0.55, 0.85, d_fbm(wpos.xz * 0.18 + 21.0));
	vec3 grass = lin(mix(vec3(0.25, 0.38, 0.17), vec3(0.36, 0.49, 0.24), n));
	grass = mix(grass, lin(vec3(0.46, 0.47, 0.28)), dry * 0.5);
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
	vec3 c = lot;
	c = mix(c, grass, w.r);
	c = mix(c, parking, w.g);
	c = mix(c, plaza, w.b);
	c = mix(c, gravel, trail);
	c = mix(c, path, brick);
	ALBEDO = c;
	ROUGHNESS = mix(0.97, 0.88, max(w.g, w.b));
	if (gfx_detail > 0.5 && near > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, blades * 0.006 * near * w.r, 1.0);
	}
}
