// Red brick pavers, as on Victoria Row and the plazas around Province House
// and Confederation Centre. Ground meshes use UV = metres * 0.25.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 brick_color : source_color = vec3(0.6, 0.38, 0.32);
uniform vec3 joint_color : source_color = vec3(0.55, 0.52, 0.48);
uniform float brick_length = 0.2;
uniform float brick_width = 0.1;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 m = UV * 4.0;
	float row = floor(m.y / brick_width);
	float x = m.x / brick_length + mod(row, 2.0) * 0.5;
	vec2 cell = vec2(floor(x), row);
	float bx = fract(x);
	float by = fract(m.y / brick_width);
	float joint = max(step(bx, 0.03), step(by, 0.06)) * 0.6;
	vec3 c = brick_color * (0.88 + 0.18 * hash(cell));
	ALBEDO = mix(c, joint_color, joint);
	ROUGHNESS = 0.9;
}
