// Walls for every generated building, in one material.
// Windows, brick courses and siding are drawn here, so buildings need no
// textures and the window grid always fits the wall it is on.
//
// Per-vertex inputs (set by building_generator.gd):
//   UV    x = position along the wall in "bay" units of bay_width metres
//            (negative = no windows on this stretch), y = metres above ground
//   UV2   x = wall style: 0 brick, 1 clapboard, 2 sandstone, 3 painted render
//         y = 1 when the ground floor is a shopfront
//   COLOR rgb = wall colour, a = number of storeys with windows / 16
// Per-instance:
//   fade  0..1, dithers the building away when it hides the player.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform float fade = 0.0;
uniform float floor_height = 3.2;
uniform float bay_width = 2.6;
uniform vec3 glass_color : source_color = vec3(0.13, 0.16, 0.2);
uniform vec3 trim_color : source_color = vec3(0.9, 0.88, 0.83);

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	if (fade > 0.0 && ign(FRAGCOORD.xy) < fade) {
		discard;
	}
	vec2 p = UV;
	float metres_x = p.x * bay_width;
	float style = UV2.x;
	vec3 wall = COLOR.rgb;
	float rough = 0.9;

	if (style < 0.5) {
		// Running-bond brick.
		float row = floor(p.y / 0.076);
		float shifted = metres_x + mod(row, 2.0) * 0.115;
		float bx = fract(shifted / 0.23);
		float by = fract(p.y / 0.076);
		float mortar = max(step(bx, 0.045), step(by, 0.14));
		wall *= 0.9 + 0.2 * hash(vec2(floor(shifted / 0.23), row));
		wall = mix(wall, vec3(0.7, 0.67, 0.62), mortar * 0.55);
	} else if (style < 1.5) {
		// Lapped clapboard: a soft shadow under each board.
		float s = fract(p.y / 0.18);
		wall *= 0.86 + 0.14 * smoothstep(0.0, 0.3, s);
		rough = 0.8;
	} else if (style < 2.5) {
		// Coursed sandstone blocks.
		float row = floor(p.y / 0.45);
		float bx = fract((metres_x + mod(row, 2.0) * 0.4) / 0.8);
		float by = fract(p.y / 0.45);
		float joint = max(step(bx, 0.02), step(by, 0.04));
		wall *= 0.93 + 0.12 * hash(vec2(floor((metres_x + mod(row, 2.0) * 0.4) / 0.8), row));
		wall = mix(wall, wall * 0.78, joint);
	}

	vec3 albedo = wall;
	float metal = 0.0;
	float floors = COLOR.a * 16.0;
	float fi = floor(p.y / floor_height);
	if (p.x >= 0.0 && p.y > 0.0 && fi < floors - 0.5) {
		float fy = fract(p.y / floor_height);
		float bx = fract(p.x);
		bool shop = UV2.y > 0.5 && fi < 0.5;
		vec2 lo = shop ? vec2(0.06, 0.06) : vec2(0.3, 0.3);
		vec2 hi = shop ? vec2(0.94, 0.7) : vec2(0.7, 0.8);
		float fw = 0.035;
		bool in_frame = bx > lo.x - fw && bx < hi.x + fw && fy > lo.y - fw && fy < hi.y + fw;
		bool in_glass = bx > lo.x && bx < hi.x && fy > lo.y && fy < hi.y;
		if (in_glass) {
			albedo = glass_color;
			rough = 0.12;
			metal = 0.35;
			if (!shop && abs(fy - (lo.y + hi.y) * 0.5) < 0.012) {
				albedo = trim_color;
				rough = 0.6;
				metal = 0.0;
			}
		} else if (in_frame) {
			albedo = trim_color;
			rough = 0.6;
		}
		if (shop && fy > 0.76 && fy < 0.93) {
			albedo = wall * 0.4; // sign band over the shop windows
			rough = 0.7;
		}
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
}
