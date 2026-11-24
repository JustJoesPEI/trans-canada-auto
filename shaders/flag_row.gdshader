shader_type spatial;
render_mode cull_disabled;
// A row of flags drawn as one mesh from one picture holding them all
// (textures/flags/atlas.png). UV picks the flag's cell in the atlas; UV2.x
// runs from the pole (0) to the fly end (1) and drives the ripple, as UV.x
// does in flag.gdshader; COLOR.r is each flag's own phase so they don't
// all flap in step. Every flag flies toward +X (the wind is from the west).

uniform sampler2D flag : source_color, filter_linear_mipmap, repeat_disable;
uniform float wave_speed = 3.2;
uniform float amplitude = 0.16;

void vertex() {
	float k = UV2.x;
	float t = TIME * wave_speed + COLOR.r * 6.283;
	float w = sin(k * 7.0 - t) * 0.7 + sin(k * 13.0 - t * 1.7 + UV2.y * 2.0) * 0.3;
	VERTEX.z += w * amplitude * k;
	VERTEX.y -= k * k * 0.08;
	float slope = (cos(k * 7.0 - t) * 4.9 + cos(k * 13.0 - t * 1.7 + UV2.y * 2.0) * 3.9) * amplitude * k;
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
}

void fragment() {
	ALBEDO = texture(flag, UV).rgb;
	ROUGHNESS = 0.85;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
