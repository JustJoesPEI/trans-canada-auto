// The police lights' lenses (PoliceGear, CarBuilder.flash_meshes): one
// shared material for every car, the colour from the vertex colours (an LED
// face brighter than its bezel) and each car's own flash as an instance
// uniform, so a fleet's lights cost no material of their own.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 0 dark (a faint glow, so the colour still reads), 1 lit.
instance uniform float lit = 0.0;
// 1 for a clear lens (Charlottetown's bar): silvery when off, coloured lit.
instance uniform float clear_lens = 0.0;

void fragment() {
	// Vertex colours are sRGB, as the other car materials take them.
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	float clear = clear_lens * (1.0 - lit);
	ALBEDO = mix(c * 0.4, vec3(0.55, 0.57, 0.6) * (0.6 + 0.4 * dot(c, vec3(1.0))), clear);
	ROUGHNESS = 0.12;
	SPECULAR = mix(0.7, 0.9, clear);
	METALLIC = clear * 0.6;
	EMISSION = c * (0.14 * (1.0 - clear_lens) + lit * 2.6);
}
