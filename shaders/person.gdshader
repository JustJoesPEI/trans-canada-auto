// People. Clothes, skin and hair are vertex colours; this adds a fine weave
// and soft folds to the cloth so it doesn't read as plastic, and a soft rim
// of light round the figure. UV and UV2.x hold each point's position on the
// body at rest, so the pattern stays put on the clothes as people move.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

void fragment() {
	// The tips of the hands, feet and head close in to a single point whose
	// normal can come out as zero; a bad normal there turns into a bright
	// speck that the glow then spreads. Fall back to facing the camera.
	vec3 nn = NORMAL;
	if (!(dot(nn, nn) > 0.0001)) {
		nn = VIEW;
	}
	NORMAL = normalize(nn);
	vec3 rest = vec3(UV.x, UV.y, UV2.x);
	float folds = d_noise(rest.xy * 14.0 + rest.z * 9.0) * 0.6 + d_noise(rest.zy * 22.0) * 0.4;
	float weave = d_noise(rest.xy * 260.0 + rest.z * 140.0);
	vec3 c = d_lin(COLOR.rgb) * (0.9 + 0.14 * folds) * (0.96 + 0.06 * weave * gfx_detail);
	ALBEDO = c;
	ROUGHNESS = 0.82;
	SPECULAR = 0.35;
	RIM = 0.25;
	RIM_TINT = 0.6;
	if (gfx_detail > 0.5) {
		NORMAL = d_bump(NORMAL, VERTEX, folds * 0.004 + weave * 0.0004, 1.0);
	}
}
