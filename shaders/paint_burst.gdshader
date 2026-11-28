shader_type spatial;
// A paint burst's puff (PaintShots._draw_puffs): unlit, see-through, the
// instance colour is the paint (sRGB) and its alpha the fade. Lumpy at the
// edge and thinner through the middle, so it reads as a splash of paint,
// not a ball.
render_mode unshaded, cull_back, blend_mix, depth_draw_never, shadows_disabled;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

varying float lump;

void vertex() {
	// Lumps: a few fixed bumps round the ball, so no two angles match.
	vec3 p = VERTEX;
	lump = sin(p.x * 5.1 + p.y * 3.3) * sin(p.z * 4.7 - p.y * 2.9);
	VERTEX = p * (1.0 + 0.18 * lump);
}

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = to_linear(COLOR.rgb) * (1.15 + 0.25 * lump);
	ALPHA = COLOR.a * clamp(0.35 + rim * 0.9 + lump * 0.15, 0.0, 1.0);
}
