// Experimental crowns built from leaf cards: each card draws a cluster of
// small leaves (alpha-scissored), so the outline of the crown is made of
// leaves with sky through the gaps, not a lumpy ball.
//   UV: 0..1 across the card. COLOR: leaf colour with crown shading (linear).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/include/detail.gdshaderinc"

varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = max(0.0, VERTEX.y + 2.0) * 0.015;
	VERTEX.x += sin(TIME * 1.3 + w.x * 0.5 + w.z * 0.3) * sway;
	VERTEX.z += sin(TIME * 1.1 + w.z * 0.4) * sway * 0.7;
	wpos = w;
}

void fragment() {
	vec2 p = UV * 7.0;
	// Far away a leaf is under a pixel: grow the leaves so the crown stays full
	// instead of turning to sparkle.
	float grow = 1.0 + clamp(length(fwidth(p)) * 1.2, 0.0, 1.2);
	vec2 cell = floor(p);
	float best = 0.0;
	float shade = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float r = d_hash(c + 0.37);
			vec2 ctr = c + 0.5 + (vec2(d_hash(c), d_hash(c + 9.1)) - 0.5) * 0.8;
			float a = r * 6.2831;
			vec2 d = p - ctr;
			d = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * d;
			// A leaf: pointed ellipse.
			float leaf = 1.0 - length(d * vec2(1.0, 2.1)) / ((0.4 + 0.2 * r) * grow) - abs(d.x) * 0.25;
			if (leaf > best) {
				best = leaf;
				shade = 0.82 + 0.3 * d_hash(c + 3.3);
			}
		}
	}
	// Fade the card out toward its edges so cards never show a square.
	float round = 1.0 - length(UV - 0.5) * 2.0;
	ALPHA = step(0.0, best) * step(0.0, round + 0.15 * (d_hash(floor(p)) - 0.5));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = COLOR.rgb * shade * (0.8 + 0.35 * best);
	c *= mix(vec3(1.06, 1.0, 0.82), vec3(0.88, 0.97, 1.04), d_noise(wpos.xz * 0.4 + wpos.y));
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.8;
}
