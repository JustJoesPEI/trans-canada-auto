// Tree bark: a photographed bark texture (CC0, Poly Haven) wrapped round
// the trunk and branches by their position, so the generated meshes need
// no UVs. Vertical grain follows the trunk; branches get it from the side.
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	// Triplanar in the tree's own space, the bark's grain running up.
	vec3 w = abs(normalize(lnrm));
	w = pow(w, vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 s = vec2(0.9, 0.45); // the texture is 1 m square; grain stretched up
	vec3 cx = texture(bark, lpos.zy * s).rgb;
	vec3 cz = texture(bark, lpos.xy * s).rgb;
	vec3 cy = texture(bark, lpos.xz * 0.9).rgb;
	vec3 c = cx * w.x + cy * w.y + cz * w.z;
	// Darker and mossier toward the ground.
	c *= mix(0.7, 1.0, clamp(lpos.y / 2.0, 0.0, 1.0));
	c = mix(c, c * vec3(0.8, 0.95, 0.7), clamp(1.0 - lpos.y, 0.0, 1.0) * 0.5);
	ALBEDO = c * tint;
	ROUGHNESS = 0.95;
}
