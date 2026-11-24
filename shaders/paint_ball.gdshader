shader_type spatial;
// Paintballs in flight (PaintShots): bright, unlit, the instance colour is
// the paint (sRGB). The mesh is stretched along the flight into a short
// streak, fading toward its tail (UV.y: 0 at the nose, 1 at the tail).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb) * 1.4;
	ALPHA = 1.0 - UV.y * 0.85;
}
