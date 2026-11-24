shader_type spatial;
// Paint on a car or a person, drawn as a material overlay (PaintCoverage,
// BodyPaint). The last few hits come in as uniform arrays and each is drawn
// as a splat shape (PaintTexture) laid on the surface along its normal, in
// the mesh's own space, so it moves with the car. Works on every renderer,
// Compatibility included: no decals, no screen reads.
//
//   hit_pos[i]  xyz: centre, w: radius (m)
//   hit_nrm[i]  xyz: the way the paint came from (out of the surface),
//               w: shape (0..3)
//   hit_col[i]  rgb: colour (sRGB), a: turn of the shape (radians)
//   hit_born[i] when it landed (s, on PaintSplats.clock): fresh paint runs
//               down the surface for its first 20 s (paint_drips), "down"
//               being the mesh's own -Y (a car on its wheels, a person at
//               rest, standing).
//
// Each splat is projected like a slide along the way the paint came: onto
// every surface facing that way from a little in front of the hit to
// `reach` behind it. A car's hits land on its collision box, which sits
// off the body in places (half a metre over the bonnet), so the paint is
// carried on through to the body under it.
//
// rest_space: a person. Their skinned mesh carries each point's position at
// rest in UV and UV2.x (BodyBuilder), so the splats are kept in rest space
// and stay on the clothes as they move, with nothing updated per frame.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/paint_drips.gdshaderinc"

// 32: PaintCoverage.MAX_HITS.
uniform vec4 hit_pos[32];
uniform vec4 hit_nrm[32];
uniform vec4 hit_col[32];
uniform float hit_born[32];
uniform int hit_count = 0;
uniform bool rest_space = false;
uniform float reach = 0.7;
uniform sampler2D splat_tex : hint_default_black, filter_linear_mipmap, repeat_disable;

varying vec3 obj_pos;
varying vec3 obj_nrm;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	obj_pos = rest_space ? vec3(UV.x, UV.y, UV2.x) : VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 col = vec3(0.0);
	float a = 0.0;
	vec3 fn = normalize(obj_nrm);
	for (int i = 0; i < 32; i++) {
		if (i >= hit_count) {
			break;
		}
		vec3 n = hit_nrm[i].xyz;
		float size = hit_pos[i].w;
		vec3 d = obj_pos - hit_pos[i].xyz;
		vec3 t = normalize(cross(n, abs(n.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 b = cross(n, t);
		float r = hit_col[i].a;
		vec2 uv = vec2(dot(d, t), dot(d, b)) / size;
		uv = vec2(uv.x * cos(r) - uv.y * sin(r), uv.x * sin(r) + uv.y * cos(r));
		// Only on surfaces facing the paint (a door's splat doesn't show
		// through on the far side), from just in front of the hit to `reach`
		// behind it.
		float facing = rest_space ? 1.0 : smoothstep(0.05, 0.3, dot(fn, n));
		float depth = dot(d, n);
		float near = smoothstep(-reach - 0.05, -reach, depth) * (1.0 - smoothstep(size * 0.6, size * 1.1, depth));
		float inside = step(abs(uv.x), 1.0) * step(abs(uv.y), 1.0);
		float shape = floor(hit_nrm[i].w + 0.5);
		vec2 cell = vec2(mod(shape, 2.0), floor(shape / 2.0)) * 0.5;
		float m = texture(splat_tex, cell + (clamp(uv, -1.0, 1.0) * 0.5 + 0.5) * 0.5).r * inside;
		// Drips: down the surface, the way gravity goes along it, running
		// for 20 s and then staying. None on a roof or a bonnet (nothing to
		// run down), less on a slope. Only worked out under the splat.
		vec3 g = vec3(0.0, -1.0, 0.0) - n * -n.y;
		float steep = length(g);
		if (steep > 0.3) {
			vec3 down = g / steep;
			vec2 dp = vec2(dot(d, cross(n, down)), dot(d, down)) / size;
			if (abs(dp.x) < 0.8 && dp.y > 0.0 && dp.y < DRIP_LEN + 0.6) {
				m = max(m, drips(dp, fract(r * 0.159155), paint_now - hit_born[i], smoothstep(0.3, 0.8, steep)));
			}
		}
		m *= facing * near;
		col = mix(col, hit_col[i].rgb, m);
		a = max(a, m);
	}
	if (a < 0.01) {
		discard;
	}
	ALBEDO = to_linear(col);
	ALPHA = a;
	ROUGHNESS = 0.35; // still a little wet-looking
	SPECULAR = 0.5;
}
