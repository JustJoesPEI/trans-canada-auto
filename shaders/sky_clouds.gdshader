shader_type sky;
// The clouds are worked out at a quarter of the screen's resolution (they're
// soft; the background pass runs every frame, at every pixel of sky) and
// laid over the full-resolution gradient and sun.
render_mode use_quarter_res_pass;
// The town's sky: the same blue gradient and sun as the stock procedural
// sky it replaces, with a deck of high, rippled cloud over it, the
// mackerel altocumulus with patches of blue in Joe's photos driving down
// University Avenue at noon in November. Clouds are noise on a flat layer
// overhead, thinning out toward the horizon, lit brighter round the sun.
// They don't move: a sky that uses TIME redraws its lighting every frame.
// On Low graphics (gfx_detail 0) the ripples are coarser.

global uniform float gfx_detail;

uniform vec3 top_color : source_color = vec3(0.2, 0.39, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.64, 0.72, 0.8);
uniform vec3 ground_bottom : source_color = vec3(0.5, 0.55, 0.6);
uniform vec3 ground_horizon : source_color = vec3(0.6, 0.66, 0.72);
uniform float sky_curve = 0.12;
uniform float energy = 1.1;
uniform float sun_angle_max = 20.0; // degrees: how far the glow round the sun reaches
uniform float sun_curve = 0.08;
// How much of the sky the clouds cover (0 none .. 1 overcast).
uniform float cover : hint_range(0.0, 1.0) = 0.68;
uniform vec3 cloud_lit : source_color = vec3(0.98, 0.98, 0.97);
uniform vec3 cloud_shade : source_color = vec3(0.64, 0.68, 0.76);
uniform float cloud_scale = 0.9; // layers of cloud per unit of the flat layer

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < octaves; i++) {
		v += a * noise(p);
		p = turn * p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// The cloud layer in direction dir: its colour, and how much of it (alpha).
vec4 clouds(vec3 dir, float sun_dot) {
	if (dir.y <= 0.01) {
		return vec4(0.0);
	}
	vec2 uv = dir.xz / (dir.y + 0.08) * cloud_scale;
	int ripple_octaves = gfx_detail > 0.5 ? 4 : 2;
	// Big patches of cloud and blue...
	float big = fbm(uv * 0.55 + vec2(3.0, 7.0), 4);
	// ...made of rows of small rounded puffs (the mackerel ripples),
	// stretched a little across the wind.
	vec2 r = vec2(uv.x * 1.0 + uv.y * 0.35, uv.y * 1.3 - uv.x * 0.2) * 7.0;
	float puffs = fbm(r + big * 2.5, ripple_octaves);
	float d = big * 0.8 + (puffs - 0.5) * 0.7;
	float edge = 1.0 - cover;
	float dens = smoothstep(edge - 0.04, edge + 0.1, d);
	// Thin out toward the horizon, where the layer is seen edge on.
	dens *= smoothstep(0.02, 0.22, dir.y);
	// Lit side toward the sun, a little grey in the thick middles.
	float thick = smoothstep(edge, edge + 0.3, d);
	// Each ripple shaded on its underside: light tops, grey troughs.
	float trough = smoothstep(0.62, 0.38, puffs);
	vec3 c = mix(cloud_lit, cloud_shade, clamp(thick * 0.55 + trough * 0.45, 0.0, 1.0));
	float near_sun = pow(max(sun_dot, 0.0), 6.0);
	c += (LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0)) * near_sun * 0.6;
	return vec4(c * 1.05, dens * 0.92);
}

void sky() {
	vec3 dir = EYEDIR;
	float sun_dot = LIGHT0_ENABLED ? dot(dir, LIGHT0_DIRECTION) : 0.0;
	if (AT_QUARTER_RES_PASS) {
		vec4 cl = clouds(dir, sun_dot);
		COLOR = cl.rgb;
		ALPHA = cl.a;
	} else {
		vec3 col;
		if (dir.y >= 0.0) {
			float t = clamp(1.0 - pow(1.0 - dir.y, 1.0 / sky_curve), 0.0, 1.0);
			col = mix(horizon_color, top_color, t);
		} else {
			float t = clamp(1.0 - pow(1.0 + dir.y, 1.0 / 0.02), 0.0, 1.0);
			col = mix(ground_horizon, ground_bottom, t);
		}
		// The glow round the sun, as the procedural sky draws it.
		if (LIGHT0_ENABLED) {
			float ang = acos(clamp(sun_dot, -1.0, 1.0));
			float glow_r = radians(sun_angle_max);
			if (ang < glow_r) {
				float g = clamp(1.0 - ang / glow_r, 0.0, 1.0);
				col = mix(col, LIGHT0_COLOR * LIGHT0_ENERGY, pow(g, 1.0 / sun_curve) * 0.5);
			}
			float disk = LIGHT0_SIZE * 0.5;
			if (ang < disk) {
				col = LIGHT0_COLOR * LIGHT0_ENERGY * 4.0;
			}
		}
		// The cloud deck over it: from the quarter-resolution pass on
		// screen, worked out here for the reflections' cubemap.
		vec4 cl = AT_CUBEMAP_PASS ? clouds(dir, sun_dot) : QUARTER_RES_COLOR;
		col = mix(col, cl.rgb, cl.a);
		COLOR = col * energy;
	}
}
