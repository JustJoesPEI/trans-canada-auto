// Roofs for every generated building, in one material.
//   COLOR rgb = roof colour
//   UV2   x = 1 for pitched (shingled) roofs, 0 for flat ones
//   UV    y = metres up the slope (pitched roofs)
//   fade  0 on the shared material; a faded copy is made only while a
//         building hides the player (see camera_rig.gd)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float fade = 0.0;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	if (fade > 0.0 && ign(FRAGCOORD.xy) < fade) {
		discard;
	}
	vec3 c = COLOR.rgb;
	if (UV2.x > 0.5) {
		// Shingle courses.
		c *= 0.86 + 0.14 * step(0.18, fract(UV.y / 0.2));
	}
	ALBEDO = c;
	ROUGHNESS = 0.88;
}
