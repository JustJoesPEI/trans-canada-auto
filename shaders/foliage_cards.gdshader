// Tree crowns made of leaf clumps (see StreetProps._branchy_crown): each
// clump is three crossed cards showing a spray of leaves from the 2x2 atlas
// textures/foliage/leaf_cluster.png, cut out with alpha scissor. Card
// normals point out from the crown's middle, so the crown shades as one
// leafy mass, darker underneath and inside, with sky through the gaps.
//   COLOR rgb = shade and slight hue for this clump (linear, about 0.3..1.1)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/include/detail.gdshaderinc"

uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Sway grows toward the outside of the crown; none on Low.
	float sway = gfx_detail * clamp(length(VERTEX.xz) * 0.3 + VERTEX.y * 0.1 + 0.2, 0.0, 1.0) * 0.06;
	VERTEX.x += sin(TIME * 1.3 + w.x * 0.5 + w.z * 0.3) * sway;
	VERTEX.z += sin(TIME * 1.05 + w.z * 0.45 + w.x * 0.2) * sway * 0.8;
	VERTEX.y += sin(TIME * 1.7 + w.x * 0.9) * sway * 0.3;
	wpos = w;
}

void fragment() {
	vec4 t = texture(leaves, UV);
	// Mipmaps average leaves with the gaps and a clump would thin out with
	// distance: raise the alpha with the mip level to keep it full.
	vec2 texel = UV * vec2(textureSize(leaves, 0));
	float mip = max(0.0, 0.5 * log2(max(dot(dFdx(texel), dFdx(texel)), dot(dFdy(texel), dFdy(texel)))));
	ALPHA = clamp(t.a * (1.0 + 0.3 * mip), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = t.rgb * COLOR.rgb;
	// Real foliage is less saturated than paint: pull a little toward grey
	// and vary it slowly across the crown.
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, 0.8) * (0.85 + 0.25 * d_noise(wpos.xz * 0.7 + wpos.y));
	ALBEDO = c;
	ROUGHNESS = 0.7;
	SPECULAR = 0.4;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS || CURRENT_RENDERER == RENDERER_MOBILE
	// Sun through the leaves, seen from underneath or behind.
	BACKLIGHT = c * vec3(0.75, 0.9, 0.5);
#endif
	// Godot flips the normal on the back of a two-sided card; the crown
	// should shade by its own outward normal from either side.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
