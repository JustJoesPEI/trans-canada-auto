shader_type spatial;
// Everything opaque on the cars parked along the curbs, in one surface (see
// CarBuilder._commit_parked). UV2.x says which finish a vertex is:
//   0 paint  1 gloss (chrome, lenses)  2 rough (tyres, trim)  3 satin  4 metal
// matching CarBuilder.material(). A whole tile of one model is a single
// MultiMesh; each car's colour comes from its instance custom data and the
// paint's vertex colours shade it (white is the colour itself, darker for
// the panel gaps). The other finishes take their vertex colour as it is.

varying vec3 paint;
varying flat float finish;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	paint = INSTANCE_CUSTOM.rgb;
	finish = UV2.x;
}

void fragment() {
	if (finish < 0.5) {
		ALBEDO = to_linear(COLOR.rgb * paint);
		METALLIC = 0.45;
		SPECULAR = 0.6;
		ROUGHNESS = 0.3;
		CLEARCOAT = 1.0;
		CLEARCOAT_ROUGHNESS = 0.04;
	} else {
		ALBEDO = to_linear(COLOR.rgb);
		if (finish < 1.5) {
			ROUGHNESS = 0.12;
			SPECULAR = 0.7;
			CLEARCOAT = 1.0;
			CLEARCOAT_ROUGHNESS = 0.03;
		} else if (finish < 2.5) {
			ROUGHNESS = 0.8;
			SPECULAR = 0.35;
		} else if (finish < 3.5) {
			ROUGHNESS = 0.42;
			SPECULAR = 0.45;
		} else {
			METALLIC = 1.0;
			ROUGHNESS = 0.16;
		}
	}
}
