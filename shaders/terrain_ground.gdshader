// The open ground between the streets, draped over the real terrain.
// data/ground_mask.png says what covers each spot (R grass, G parking,
// B stone-paved square, A brick path); anything else is an ordinary lot of
// worn grass and gravel. Colours are written in sRGB and converted.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

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
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		w = texture(ground_mask, uv);
		// Crisp edges: the map is half a metre per pixel, so sharpen the
		// blend between areas into a clean line a few centimetres wide.
		w = smoothstep(vec4(0.4), vec4(0.6), w);
	}
	float n = fbm(wpos.xz * 0.12);
	float fine = vnoise(wpos.xz * 1.7);
	vec3 lot = lin(mix(vec3(0.34, 0.35, 0.27), vec3(0.47, 0.46, 0.38), n)) * (0.92 + 0.12 * fine);
	vec3 grass = lin(mix(vec3(0.27, 0.4, 0.19), vec3(0.36, 0.49, 0.25), n)) * (0.9 + 0.15 * fine);
	vec3 parking = lin(vec3(0.31, 0.31, 0.32)) * (0.82 + 0.3 * n);
	vec3 plaza = lin(pavers(wpos.xz, vec3(0.64, 0.61, 0.56), vec3(0.5, 0.48, 0.45), 0.6, 0.4));
	vec3 path = lin(pavers(wpos.xz, vec3(0.55, 0.4, 0.35), vec3(0.55, 0.52, 0.48), 0.2, 0.1));
	vec3 c = lot;
	c = mix(c, parking, w.g);
	c = mix(c, grass, w.r);
	c = mix(c, plaza, w.b);
	c = mix(c, path, w.a);
	ALBEDO = c;
	ROUGHNESS = mix(0.97, 0.88, max(w.g, w.b));
}
