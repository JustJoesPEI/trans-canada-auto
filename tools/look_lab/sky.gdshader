// Experimental sky: gradient, sun, and soft drifting cloud cover.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.32, 0.45, 0.62);
uniform vec3 horizon : source_color = vec3(0.72, 0.76, 0.8);
uniform vec3 ground : source_color = vec3(0.45, 0.47, 0.48);
uniform vec3 cloud_lit : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 cloud_shade : source_color = vec3(0.55, 0.58, 0.62);
uniform float coverage = 0.5;
uniform float softness = 0.25;
uniform float energy = 1.0;
uniform float sun_glow = 0.3;

float h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float n(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), u.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 6; i++) {
		s += n(p) * a;
		p = p * 2.03 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float up = max(d.y, 0.0);
	vec3 col = mix(horizon, zenith, pow(up, 0.55));
	if (d.y < 0.0) {
		col = mix(horizon, ground, clamp(-d.y * 6.0, 0.0, 1.0));
	}
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += LIGHT0_COLOR * (pow(sd, 6.0) * sun_glow + pow(sd, 400.0) * 1.5) * LIGHT0_ENERGY * 0.4;
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.08) * 0.9;
		float c = fbm(uv * 1.3 + vec2(TIME * 0.004, 0.0));
		float cov = smoothstep(1.0 - coverage - softness, 1.0 - coverage + softness, c);
		float thick = fbm(uv * 2.6 + 3.0);
		vec3 cc = mix(cloud_shade, cloud_lit, clamp(thick * 1.4 - 0.2 + pow(sd, 4.0) * 0.4, 0.0, 1.0));
		cc *= mix(vec3(1.0), LIGHT0_COLOR, 0.35);
		float fade = smoothstep(0.0, 0.18, d.y);
		col = mix(col, cc, cov * fade);
	}
	COLOR = col * energy;
}
