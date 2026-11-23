// Experimental camera/film post-process, drawn as a full-screen rect.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.0;
uniform float vignette = 0.0;
uniform float aberration = 0.0;
uniform float green_desat = 0.0;   // pulls cartoon greens toward olive
uniform vec3 shadow_tint = vec3(1.0);
uniform vec3 highlight_tint = vec3(1.0);
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float lift = 0.0;
uniform float halation = 0.0;
uniform float soft = 0.0;          // slight lens softness

float hh(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	vec3 col;
	if (aberration > 0.0) {
		vec2 o = c * aberration * 0.01;
		col = vec3(texture(screen, uv + o).r, texture(screen, uv).g, texture(screen, uv - o).b);
	} else {
		col = texture(screen, uv).rgb;
	}
	if (soft > 0.0) {
		col = mix(col, textureLod(screen, uv, 1.2).rgb, soft * smoothstep(0.1, 0.6, length(c)));
	}
	if (halation > 0.0) {
		vec3 b = textureLod(screen, uv, 4.5).rgb;
		col += max(b - 0.7, 0.0) * vec3(1.0, 0.55, 0.35) * halation;
	}
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	// Pull saturated, cartoon greens toward natural olive/grey.
	float g = clamp((col.g - max(col.r, col.b)) * 4.0, 0.0, 1.0);
	col = mix(col, mix(vec3(l), col * vec3(1.08, 0.94, 0.85), 0.55), g * green_desat);
	col = mix(vec3(l), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col = col * (1.0 - lift) + lift;
	col *= mix(shadow_tint, highlight_tint, smoothstep(0.1, 0.8, l));
	col *= 1.0 - vignette * dot(c, c) * 1.6;
	col += (hh(uv * 1000.0 + fract(TIME) * 17.0) - 0.5) * grain;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
