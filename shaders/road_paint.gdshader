// Painted road markings (centre lines, crosswalks), worn by traffic: the
// asphalt grain shows through and the paint thins out in places.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

uniform vec3 paint_color : source_color = vec3(0.9, 0.9, 0.87);
uniform vec3 under_color : source_color = vec3(0.3, 0.3, 0.31);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float px = length(fwidth(p));
	float fine_ok = 1.0 - smoothstep(0.02, 0.08, px);
	float wear = smoothstep(0.35, 0.8, d_fbm(p * 1.4)) * 0.75;
	float grain = d_noise(p * 45.0);
	wear = max(wear, step(0.75, grain) * 0.6 * fine_ok);
	vec3 c = mix(paint_color * (0.9 + 0.1 * d_noise(p * 3.0)), under_color * (0.8 + 0.3 * grain), wear);
	ALBEDO = c;
	ROUGHNESS = mix(0.6, 0.9, wear);
	SPECULAR = 0.45;
}
