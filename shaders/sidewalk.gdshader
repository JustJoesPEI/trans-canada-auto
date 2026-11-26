// Concrete sidewalks and curbs. Poured slabs with tooled joints every metre
// and a half, a separate curb stone along the street edge, slab-to-slab
// colour differences, old gum spots and grime toward the buildings; the curb
// face is darkened by road spray toward the bottom.
//   UV2  x = metres along the curb
//        y = metres in from the curb on the walking surface,
//            -1 on the curb face, -2 on the back edge
//   UV   on vertical faces = (metres along this piece, metres up)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"
#include "res://shaders/include/street_marks.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.66, 0.64, 0.6);
uniform vec3 curb_color : source_color = vec3(0.7, 0.69, 0.66);
uniform float slab = 1.5;
uniform float curb_width = 0.3;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float px = length(fwidth(p));
	float fine_ok = 1.0 - smoothstep(0.02, 0.08, px);
	float n = d_fbm(p * 0.4);
	vec2 dux = dFdx(UV2);
	vec2 duy = dFdy(UV2);
	vec3 c;
	float rough = 0.9;
	float h = 0.0;
	if (UV2.y >= -0.5) {
		float along = UV2.x;
		float inn = UV2.y;
		if (inn < curb_width) {
			// Curb stone: lighter, longer pieces.
			float piece = floor(along / 2.4);
			c = curb_color * (0.9 + 0.12 * d_hash(vec2(piece, 7.0)));
			float jt = 1.0 - smoothstep(0.0, 0.012 + px * 0.5, abs(fract(along / 2.4 + 0.5) - 0.5) * 2.4);
			float edge = 1.0 - smoothstep(0.0, 0.015 + px * 0.5, abs(inn - curb_width));
			c *= 1.0 - 0.4 * max(jt, edge);
			h -= max(jt, edge);
		} else {
			float sa = (along) / slab;
			float sb = (inn - curb_width) / slab;
			vec2 cell = floor(vec2(sa, sb));
			c = base_color * (0.9 + 0.13 * d_hash(cell)) * (0.88 + 0.2 * n);
			vec2 f = abs(fract(vec2(sa, sb) + 0.5) - 0.5) * slab; // metres to the nearest joint
			float jw = 0.01 + px * 0.5;
			float joint = 1.0 - smoothstep(0.0, jw, min(f.x, f.y));
			c *= 1.0 - 0.45 * joint;
			h -= joint;
			// Grime collects in the joints and toward the building line.
			c *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.1, min(f.x, f.y)));
			// Old chewing gum: little dark dots.
			vec2 g = floor(p * 5.0);
			float gum = step(0.985, d_hash(g + 13.0)) * (1.0 - smoothstep(0.03, 0.07, length(fract(p * 5.0) - 0.5) / 5.0));
			c *= 1.0 - gum * 0.45 * fine_ok;
			// A cracked slab here and there, and the odd stain (the
			// street marks' cracks and oil, one read, near only).
			float sh = d_hash(cell + 71.0);
			if (fine_ok > 0.0 && sh < 0.08) {
				float layer = sh < 0.055 ? 1.0 : 5.0;
				float k = layer > 2.0 ? 2.5 : 1.0;
				vec2 q = (fract(vec2(sa, sb)) - 0.5) * 2.0 * k;
				mat2 rot = mark_rot(floor(d_hash(cell + 3.3) * 4.0) * 1.5708);
				vec2 sc = vec2(k * 2.0 / slab);
				vec4 m = street_mark(rot * q, rot * (dux * sc), rot * (duy * sc), layer);
				float a = m.a * fine_ok * (layer > 2.0 ? 0.6 : 1.0);
				c = mix(c, c * m.rgb * (layer > 2.0 ? 2.0 : 1.6), a);
				h -= a * 0.5;
			}
		}
		// Wet-weather staining in blotches.
		c *= 0.92 + 0.1 * d_fbm(p * 0.09 + 4.0);
	} else {
		// Curb face or back edge: grimy toward the bottom.
		float up = clamp(UV.y / 0.12, 0.0, 1.0);
		c = curb_color * (0.85 + 0.15 * n);
		if (UV2.y > -1.5) {
			c *= mix(0.55, 1.0, smoothstep(0.0, 0.9, up));
			c = mix(c, d_lin(vec3(0.36, 0.33, 0.29)), (1.0 - up) * 0.35);
		} else {
			c *= 0.8;
		}
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	if (gfx_detail > 0.5 && fine_ok > 0.0) {
		float grain = (d_noise(p * 60.0) - 0.5) * 0.2 * fine_ok;
		NORMAL = d_bump(NORMAL, VERTEX, h * 0.004 + grain * 0.002, 1.0);
	}
}
