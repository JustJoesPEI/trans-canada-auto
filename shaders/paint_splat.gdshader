shader_type spatial;
// Splats on walls, the ground and props: flat quads in one MultiMesh pool
// (PaintSplats). Each instance's colour is its paint (sRGB); its custom data
// is (shape 0..3, when it landed in seconds, turn of the shape in radians,
// drip room 0..1). Splats last `life` seconds and fade out over the last
// `fade` of it; past `fade_far` metres they fade out too (they're a few
// pixels across by then).
//
// The quad's own x is across the surface and its y is down it (PaintSplats
// lays them that way), so fresh paint runs toward +y (paint_drips): for the
// first 20 s the quad's lower edge is stretched down as far as the drips
// have got, so the drips have room and a dry splat costs no more than before.
//
// Never floating, never flickering: the quad sits a centimetre off the
// surface (PaintSplats), and here it's drawn pulled toward the camera by a
// small share of its distance. Moving a point along the line of sight
// doesn't move it on screen, so up close nothing changes, and far off,
// where the depth buffer is coarse, it still wins against the surface.
render_mode blend_mix, depth_draw_never, cull_back, skip_vertex_transform, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/paint_drips.gdshaderinc"

uniform sampler2D splat_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float life = 1200.0;
uniform float fade = 120.0;
uniform float fade_far = 90.0;
uniform float pull = 0.0015;

varying float alpha;
varying vec2 cell;
varying vec2 local;
varying float age;
varying float room;
varying float turn;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	age = paint_now - INSTANCE_CUSTOM.y;
	room = INSTANCE_CUSTOM.w;
	turn = INSTANCE_CUSTOM.z;
	vec3 v = VERTEX;
	if (v.y > 0.0) {
		// Room below for the drips run so far (and their beads).
		v.y += max(0.0, 0.55 + drip_run(age) * room * DRIP_LEN - 1.0) * step(0.001, room);
	}
	local = v.xy;
	vec3 view = (MODELVIEW_MATRIX * vec4(v, 1.0)).xyz;
	float dist = length(view);
	VERTEX = view * (1.0 - pull);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	alpha = clamp((life - age) / fade, 0.0, 1.0) * (1.0 - smoothstep(fade_far * 0.8, fade_far, dist));
	float shape = floor(INSTANCE_CUSTOM.x + 0.5);
	cell = vec2(mod(shape, 2.0), floor(shape / 2.0)) * 0.5;
}

void fragment() {
	vec2 r = vec2(local.x * cos(turn) - local.y * sin(turn), local.x * sin(turn) + local.y * cos(turn));
	float inside = step(abs(r.x), 1.0) * step(abs(r.y), 1.0);
	float m = texture(splat_tex, cell + (clamp(r, -1.0, 1.0) * 0.5 + 0.5) * 0.5).r * inside;
	m = max(m, drips(local, fract(turn * 0.159155), age, room));
	m *= alpha;
	if (m < 0.01) {
		discard;
	}
	ALBEDO = to_linear(COLOR.rgb);
	ALPHA = m;
	ROUGHNESS = 0.4;
	SPECULAR = 0.45;
}
