// Roofs (and shop awnings) for every generated building, in one material.
//   COLOR rgb = colour (linear)
//   UV2   x = 0 flat roof, 1 shingled pitched roof or spire,
//           2 striped canvas awning, 3 plain canvas awning, 4 copper
//   UV    x = metres across, y = metres up the slope
//   fade  0 on the shared material; a faded copy is made only while a
//         building hides the player (see camera_rig.gd)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform float fade = 0.0;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	if (fade > 0.0 && ign(FRAGCOORD.xy) < fade) {
		discard;
	}
	vec3 c = COLOR.rgb;
	float rough = 0.88;
	float kind = UV2.x;
	if (kind > 0.5 && kind < 1.5) {
		c *= 0.84 + 0.16 * step(0.15, fract(UV.y / 0.2));
		c *= 0.94 + 0.08 * step(0.5, fract(UV.x / 0.45 + floor(UV.y / 0.2) * 0.5));
	} else if (kind > 1.5 && kind < 2.5) {
		c = mix(c, vec3(0.8, 0.79, 0.74), step(0.5, fract(UV.x / 0.6)));
		rough = 0.95;
	} else if (kind > 2.5 && kind < 3.5) {
		rough = 0.95;
	} else if (kind > 3.5) {
		c *= 0.9 + 0.1 * step(0.08, fract(UV.x / 0.5));
		rough = 0.5;
	} else {
		c *= 0.95 + 0.05 * step(0.02, fract(UV.x / 3.0));
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
