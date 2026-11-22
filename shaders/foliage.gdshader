// Tree crowns. The crown mesh is a cluster of lumpy blobs whose normals point
// out from the middle of the crown, so it shades softly like a mass of
// leaves rather than like a ball. Here we break it up further into clumps of
// leaves with darker gaps, let a little sun through from behind, and sway
// the crown very gently in the wind.
//   COLOR rgb = leaf colour with the shade inside the crown baked in (linear)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Sway grows toward the top of the crown; no sway on Low.
	float sway = gfx_detail * max(0.0, VERTEX.y + 2.0) * 0.012;
	VERTEX.x += sin(TIME * 1.1 + w.x * 0.35 + w.z * 0.2) * sway;
	VERTEX.z += sin(TIME * 0.9 + w.z * 0.3) * sway * 0.7;
	wpos = w;
}

void fragment() {
	float px = length(fwidth(wpos));
	float near = 1.0 - smoothstep(0.03, 0.12, px);
	// Two crossed 2D noises stand in for a 3D one.
	float clump = d_noise(wpos.xy * 2.2 + wpos.z * 0.7) * 0.5 + d_noise(wpos.zy * 2.2 + wpos.x * 0.7 + 7.0) * 0.5;
	float leaves = d_noise(wpos.xy * 9.0 + wpos.z * 3.0) * 0.5 + d_noise(wpos.zy * 9.0 - wpos.x * 3.0) * 0.5;
	float m = mix(clump, clump * 0.6 + leaves * 0.4, near);
	vec3 c = COLOR.rgb * (0.6 + 0.65 * m);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.6;
	if (gfx_detail > 0.5) {
		NORMAL = d_bump(NORMAL, VERTEX, m, 0.12);
	}
}
