// The police lights' lenses (PoliceGear, CarBuilder.flash_meshes): one
// shared material for every car, the colour from the vertex colours (an LED
// face brighter than its bezel) and each car's own flash as an instance
// uniform, so a fleet's lights cost no material of their own.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 0 dark (a faint glow, so the colour still reads), 1 lit.
instance uniform float lit = 0.0;

void fragment() {
	// Vertex colours are sRGB, as the other car materials take them.
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c * 0.4;
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
	EMISSION = c * (0.14 + lit * 2.6);
}
