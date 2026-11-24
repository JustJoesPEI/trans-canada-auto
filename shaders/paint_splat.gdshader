shader_type spatial;
// Splats on walls, the ground and props: flat quads in one MultiMesh pool
// (PaintSplats). Each instance's colour is its paint (sRGB); its custom data
// is (shape 0..3, when it landed in seconds, 0, 0). Splats last `life`
// seconds and fade out over the last `fade` of it; past `fade_far` metres they
// fade out too (they're a few pixels across by then).
//
// Never floating, never flickering: the quad sits a centimetre off the
// surface (PaintSplats), and here it's drawn pulled toward the camera by a
// small share of its distance. Moving a point along the line of sight
// doesn't move it on screen, so up close nothing changes, and far off,
// where the depth buffer is coarse, it still wins against the surface.
render_mode blend_mix, depth_draw_never, cull_back, skip_vertex_transform, diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float now = 0.0;
uniform float life = 1200.0;
uniform float fade = 120.0;
uniform float fade_far = 90.0;
uniform float pull = 0.0015;

varying float alpha;
varying vec2 cell;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(view);
	VERTEX = view * (1.0 - pull);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float age = now - INSTANCE_CUSTOM.y;
	alpha = clamp((life - age) / fade, 0.0, 1.0) * (1.0 - smoothstep(fade_far * 0.8, fade_far, dist));
	float shape = floor(INSTANCE_CUSTOM.x + 0.5);
	cell = vec2(mod(shape, 2.0), floor(shape / 2.0)) * 0.5;
}

void fragment() {
	float m = texture(splat_tex, cell + UV * 0.5).r * alpha;
	if (m < 0.01) {
		discard;
	}
	ALBEDO = to_linear(COLOR.rgb);
	ALPHA = m;
	ROUGHNESS = 0.4;
	SPECULAR = 0.45;
}
