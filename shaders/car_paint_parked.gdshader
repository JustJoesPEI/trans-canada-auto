shader_type spatial;
// Paint for the cars parked along the curbs. A whole street of one model is
// a single MultiMesh; each car's colour comes from its instance custom data
// and the mesh's vertex colours shade it (white is the colour itself, darker
// for the panel gaps). Matches CarBuilder.paint_material().

varying vec3 paint;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	paint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb * paint);
	METALLIC = 0.45;
	SPECULAR = 0.6;
	ROUGHNESS = 0.3;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.04;
}
