// Tree crowns made of leaf cards (see StreetProps._card_crown_mesh): each
// card shows a clump of leaves from textures/foliage/leaf_cluster.png, cut
// out with alpha scissor. The card normals point out from the middle of the
// crown, so the whole crown shades as one leafy mass and its outline is
// leaves against the sky.
//   COLOR rgb = leaf tint with the shade deep inside the crown baked in (linear)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/include/detail.gdshaderinc"

uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = gfx_detail * max(0.0, VERTEX.y + 2.0) * 0.014;
	VERTEX.x += sin(TIME * 1.2 + w.x * 0.4 + w.z * 0.25) * sway;
	VERTEX.z += sin(TIME * 0.95 + w.z * 0.35) * sway * 0.7;
	wpos = w;
}

void fragment() {
	vec4 t = texture(leaves, UV);
	// Mipmaps average leaves with the empty gaps and the clump would thin
	// out with distance: raise the alpha with the mip level to keep it full.
	vec2 texel = UV * vec2(textureSize(leaves, 0));
	float mip = max(0.0, 0.5 * log2(max(dot(dFdx(texel), dFdx(texel)), dot(dFdy(texel), dFdy(texel)))));
	ALPHA = clamp(t.a * (1.0 + 0.35 * mip), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Shade per clump: each card is a little lighter or darker and warmer or cooler.
	float v = d_noise(wpos.xz * 0.6 + wpos.y * 0.4);
	vec3 c = t.rgb * COLOR.rgb * 2.6 * mix(vec3(1.05, 1.0, 0.85), vec3(0.9, 0.98, 1.05), v);
	ALBEDO = c;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS || CURRENT_RENDERER == RENDERER_MOBILE
	BACKLIGHT = c * 0.7;
#endif
	// Godot flips the normal on the back of a two-sided card; the crown
	// should shade by its own outward normal from either side.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
