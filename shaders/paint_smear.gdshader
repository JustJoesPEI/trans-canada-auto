shader_type canvas_item;
// Paint on the windscreen (WindscreenSmear): the view behind it blurred,
// with a film of the paint's colour over it, in the splat's shape. The
// shape comes from the splat atlas (TEXTURE, .r); COLOR is the paint and
// how much of it is left (alpha). A blur of a few taps, no mipmaps, so it
// works the same on the Compatibility renderer.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur = 0.02;

void fragment() {
	float m = texture(TEXTURE, UV).r;
	vec4 paint = COLOR;
	vec3 seen = vec3(0.0);
	for (int i = 0; i < 10; i++) {
		float a = float(i) * 2.39996;
		float r = sqrt(float(i) + 0.5) / sqrt(10.0);
		seen += texture(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r * blur * vec2(SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y, 1.0)).rgb;
	}
	seen /= 10.0;
	COLOR = vec4(mix(seen, paint.rgb, 0.3 + 0.3 * m), smoothstep(0.05, 0.6, m) * paint.a);
}
