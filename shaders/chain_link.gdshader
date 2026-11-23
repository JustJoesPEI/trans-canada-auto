shader_type spatial;
// Chain-link fence fabric: a diamond mesh of galvanised wire drawn from UV
// (metres along the fence, metres up), see-through between the wires.
// Far off, where the wires are finer than a pixel, it fades to the faint
// grey haze a real chain-link fence makes at a distance.
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec3 wire_color : source_color = vec3(0.42, 0.44, 0.44);
uniform float mesh_size = 0.06; // metres between wires

void fragment() {
	vec2 d = vec2(UV.x + UV.y, UV.x - UV.y) / mesh_size;
	vec2 fd = fract(d);
	float w = min(min(fd.x, 1.0 - fd.x), min(fd.y, 1.0 - fd.y));
	float px = max(length(fwidth(d)), 1e-4);
	float wire = 1.0 - smoothstep(0.1, 0.1 + px, w);
	float far = smoothstep(0.2, 0.7, px);
	ALPHA = mix(wire, 0.32, far);
	ALBEDO = wire_color;
	METALLIC = 0.6;
	ROUGHNESS = 0.45;
}
