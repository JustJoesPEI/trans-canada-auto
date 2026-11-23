shader_type spatial;
render_mode cull_disabled;
// A flag on a pole: UV.x runs from the pole (0) to the fly end (1). It
// ripples along its length, more toward the free end, and both sides show
// the same picture.

uniform sampler2D flag : source_color, filter_linear_mipmap, repeat_disable;
uniform float wave_speed = 3.2;
uniform float amplitude = 0.22;

void vertex() {
	float k = UV.x;
	float t = TIME * wave_speed + NODE_POSITION_WORLD.x * 0.37;
	float w = sin(k * 7.0 - t) * 0.7 + sin(k * 13.0 - t * 1.7 + UV.y * 2.0) * 0.3;
	VERTEX.z += w * amplitude * k;
	VERTEX.y -= k * k * 0.12;
	float slope = (cos(k * 7.0 - t) * 4.9 + cos(k * 13.0 - t * 1.7 + UV.y * 2.0) * 3.9) * amplitude * k;
	NORMAL = normalize(vec3(-slope, 0.0, 1.0));
}

void fragment() {
	ALBEDO = texture(flag, UV).rgb;
	ROUGHNESS = 0.85;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
