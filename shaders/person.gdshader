// People. Clothes, skin and hair are vertex colours; this adds the cloth:
// a fine weave and soft folds so it doesn't read as plastic, fabric
// patterns (plaid, denim, quilting, ribbing), shine (satin, leather, nylon),
// printed graphics from the prints sheet, and a soft rim of light round the
// figure.
//
// Per vertex (BodyBuilder):
//   UV, UV2.x  the point's position on the body at rest, so patterns stay put
//              on the clothes as people move
//   COLOR.a    1 = matte cloth, lower = shinier (satin, leather, nylon)
//   CUSTOM0    print: u, v (0..1 across the print), tile + 1 on the sheet,
//              1 where printed (0 = no print here)
//   CUSTOM1    pattern number, then the pattern's second colour
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

// tools/make_clothing_prints.py draws it: 4 x 4 tiles.
uniform sampler2D prints : source_color, filter_linear_mipmap, repeat_disable;

varying vec4 v_print;
varying vec4 v_pattern;

const float PLAID = 1.0;
const float DENIM = 2.0;
const float QUILTED = 3.0;
const float RIBBED = 4.0;
const float RIBBED_STRIPES = 5.0;

void vertex() {
	v_print = CUSTOM0;
	v_pattern = CUSTOM1;
}

// 1 on the pattern number `id` (vertices of one garment all carry the same
// number; where two garments meet the value blends and matches neither).
float is_pattern(float id) {
	return 1.0 - step(0.02, abs(v_pattern.x - id));
}

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
	vec3 base = COLOR.rgb;
	vec3 second = v_pattern.yzw;
	float relief = 0.0;
	// Around the body, so stripes and ribs carry on round the sides.
	float wrap = rest.x + rest.z;

	if (is_pattern(PLAID) > 0.5) {
		// Flannel: wide bands of the second colour both ways, darker where
		// they cross, and fine light lines between.
		vec2 g = vec2(wrap, rest.y) / 0.075;
		vec2 f = abs(fract(g) - 0.5);
		vec2 band = 1.0 - smoothstep(0.17, 0.21, f);
		vec2 line = 1.0 - smoothstep(0.012, 0.03, abs(f - 0.38));
		vec3 c = mix(base, second, max(band.x, band.y) * 0.85);
		c *= 1.0 - band.x * band.y * 0.35;
		c = mix(c, vec3(0.92, 0.9, 0.84), max(line.x, line.y) * 0.45);
		base = c;
	} else if (is_pattern(DENIM) > 0.5) {
		// Twill: fine diagonal lines, and faded patches.
		float twill = sin((wrap + rest.y) * 1100.0) * 0.5 + 0.5;
		float fade = d_fbm(vec2(wrap, rest.y) * 9.0);
		base *= 0.9 + twill * 0.12 * gfx_detail;
		base = mix(base, base * 1.35 + 0.03, smoothstep(0.55, 0.85, fade) * 0.35);
		relief = twill * 0.0004;
	} else if (is_pattern(QUILTED) > 0.5) {
		// Puffer: horizontal channels, stitched in at the seams.
		float ch = abs(fract(rest.y / 0.075) - 0.5) * 2.0; // 1 at the seams
		float puff = 1.0 - ch * ch;
		base *= 0.72 + 0.28 * puff;
		relief = puff * 0.02;
	} else if (is_pattern(RIBBED) > 0.5 || is_pattern(RIBBED_STRIPES) > 0.5) {
		// Knit bands: fine ribs; the varsity kind has two stripes.
		float rib = sin(wrap * 900.0) * 0.5 + 0.5;
		base *= 0.88 + 0.12 * rib;
		relief = rib * 0.0012;
		if (is_pattern(RIBBED_STRIPES) > 0.5) {
			float s = fract(rest.y / 0.024);
			base = mix(base, second, step(0.35, s) * step(s, 0.6));
		}
	}

	// Printed graphics: screen print, a little faded by the weave.
	float tile = v_print.z - 1.0;
	vec2 puv = v_print.xy;
	float printed = 0.0;
	if (v_print.w > 0.999 && tile > -0.5 && all(greaterThan(puv, vec2(0.0))) && all(lessThan(puv, vec2(1.0)))) {
		float t = round(tile);
		vec2 cell = vec2(mod(t, 4.0), floor(t / 4.0));
		vec4 ink = texture(prints, (cell + mix(vec2(0.01), vec2(0.99), puv)) / 4.0);
		printed = ink.a;
		base = mix(base, ink.rgb, ink.a * 0.95);
	}

	float folds = d_noise(rest.xy * 14.0 + rest.z * 9.0) * 0.6 + d_noise(rest.zy * 22.0) * 0.4;
	float weave = d_noise(rest.xy * 260.0 + rest.z * 140.0);
	vec3 c = d_lin(base) * (0.9 + 0.14 * folds) * (0.96 + 0.06 * weave * gfx_detail);
	ALBEDO = c;
	float matte = COLOR.a;
	ROUGHNESS = mix(0.36, 0.82, matte) + printed * 0.08;
	SPECULAR = mix(0.55, 0.35, matte);
	RIM = 0.25;
	RIM_TINT = 0.6;
	if (gfx_detail > 0.5) {
		NORMAL = d_bump(NORMAL, VERTEX, folds * 0.004 + weave * 0.0004 * matte + relief, 1.0);
	}
}
