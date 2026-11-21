// Walls for every generated building, in one material. Windows, brick,
// siding, shopfronts and doors are drawn here, so buildings need no textures
// and the window grid always fits the wall it is on.
//
// Per-vertex inputs (set by building_generator.gd):
//   UV    x = position along the wall in window bays (negative = no windows
//            on this stretch), y = metres above the ground
//   UV2   x = wall style:
//              0 brick  1 clapboard  2 sandstone  3 painted (smooth)
//              4 modern stone (blank)  5 cedar shingle  6 plain trim  7 church
//         y = shopfront flag (whole part) + trim colour index * 0.1
//   COLOR rgb = wall colour (linear), a = number of storeys with windows / 16
// Uniform:
//   fade  0..1, dithers the building away when it hides the player. The
//         shared material keeps 0; the camera swaps in a faded copy only
//         for the few buildings in the way.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float fade = 0.0;
uniform float floor_height = 3.2;
uniform float shop_floor_height = 4.0;

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Trim colours, in linear space: white, cream, dark green, near black.
vec3 trim_color(float idx) {
	if (idx < 0.5) return vec3(0.82, 0.82, 0.78);
	if (idx < 1.5) return vec3(0.72, 0.62, 0.42);
	if (idx < 2.5) return vec3(0.025, 0.07, 0.04);
	return vec3(0.02, 0.018, 0.016);
}

float bay_metres(float style) {
	if (style < 0.5) return 2.0; // Victorian brick: narrow bays
	if (style > 3.5 && style < 4.5) return 3.0;
	if (style > 6.5) return 3.4;
	return 2.6;
}

void fragment() {
	if (fade > 0.0 && ign(FRAGCOORD.xy) < fade) {
		discard;
	}
	vec2 p = UV;
	float style = UV2.x;
	bool shop_building = UV2.y > 0.95;
	float trim_idx = floor(fract(UV2.y + 0.001) * 10.0 + 0.5);
	vec3 trim = trim_color(trim_idx);
	float mx = p.x * bay_metres(style); // metres along the wall
	vec3 wall = COLOR.rgb;
	float rough = 0.9;

	// --- wall surface ---------------------------------------------------------
	if (style < 0.5) {
		float row = floor(p.y / 0.076);
		float shifted = mx + mod(row, 2.0) * 0.115;
		float bx = fract(shifted / 0.23);
		float by = fract(p.y / 0.076);
		float mortar = max(step(bx, 0.045), step(by, 0.14));
		wall *= 0.88 + 0.24 * hash(vec2(floor(shifted / 0.23), row));
		wall = mix(wall, vec3(0.45, 0.42, 0.38), mortar * 0.45);
	} else if (style < 1.5) {
		wall *= 0.84 + 0.16 * smoothstep(0.0, 0.3, fract(p.y / 0.16));
		rough = 0.8;
	} else if (style < 2.5 || style > 6.5) {
		float row = floor(p.y / 0.45);
		float sx = (mx + mod(row, 2.0) * 0.4) / 0.8;
		float joint = max(step(fract(sx), 0.02), step(fract(p.y / 0.45), 0.04));
		wall *= 0.92 + 0.14 * hash(vec2(floor(sx), row));
		wall = mix(wall, wall * 0.75, joint);
	} else if (style > 3.5 && style < 4.5) {
		float panel = max(step(fract(mx / 1.5), 0.01), step(fract(p.y / 1.2), 0.012));
		wall = mix(wall, wall * 0.82, panel);
	} else if (style > 4.5 && style < 5.5) {
		float row = floor(p.y / 0.14);
		float sx = (mx + hash(vec2(row, 3.0)) * 0.3) / 0.18;
		wall *= 0.8 + 0.25 * hash(vec2(floor(sx), row));
		wall *= 0.9 + 0.1 * smoothstep(0.0, 0.35, fract(p.y / 0.14));
	}

	vec3 albedo = wall;
	float metal = 0.0;
	float spec = 0.5;

	// --- which storey are we on? ------------------------------------------------
	float floors = COLOR.a * 16.0;
	bool tall_ground = shop_building && (style < 0.5 || (style > 1.5 && style < 4.5));
	float gf = tall_ground ? shop_floor_height : floor_height;
	float fi;
	float fy;
	if (p.y < gf) {
		fi = 0.0;
		fy = p.y / gf;
	} else {
		fi = 1.0 + floor((p.y - gf) / floor_height);
		fy = fract((p.y - gf) / floor_height);
	}
	float bx = fract(p.x);
	float bay = floor(p.x);
	bool windows_here = p.x >= 0.0 && p.y > 0.0 && fi < floors - 0.5 && style < 6.5 + 1.0;

	if (windows_here && style > 6.5) {
		// Church: one tall pointed window per bay, spanning the wall.
		float top = floors * floor_height - 1.2;
		float wy = p.y;
		float half_w = 0.17;
		float dx = abs(bx - 0.5);
		float arch_start = top - 1.1;
		bool in_shape = dx < half_w && wy > 2.2 && wy < top;
		if (in_shape && wy > arch_start) {
			// Two arcs meeting at a point.
			float a = (wy - arch_start) / (top - arch_start);
			in_shape = dx < half_w * sqrt(max(0.0, 1.0 - a * a)) - a * 0.02;
		}
		if (in_shape) {
			bool lead = abs(dx - 0.0) < 0.012 || fract(wy / 0.6) < 0.04;
			albedo = lead ? vec3(0.05) : mix(vec3(0.05, 0.08, 0.14), vec3(0.18, 0.08, 0.06), step(0.5, hash(vec2(bay, floor(wy / 0.6)))));
			rough = 0.25;
			spec = 0.7;
		}
	} else if (windows_here && style < 6.5) {
		bool is_house = style > 0.5 && style < 1.5 || (style > 4.5 && style < 5.5);
		bool storefront = tall_ground && fi < 0.5;
		bool modern = style > 3.5 && style < 4.5;
		if (storefront || (shop_building && fi < 0.5 && !is_house)) {
			// Shopfront: pilasters, sign band, kick plate, big glass, a door every third bay.
			bool pilaster = bx < 0.07 || bx > 0.93;
			bool sign = fy > 0.8 && fy < 0.95;
			bool kick = fy < 0.1;
			bool door_bay = mod(bay, 3.0) > 0.5 && mod(bay, 3.0) < 1.5;
			bool door = door_bay && bx > 0.34 && bx < 0.66 && fy < 0.68;
			if (sign) {
				albedo = trim_idx > 1.5 ? trim : wall * 0.3;
				rough = 0.5;
			} else if (pilaster || fy > 0.95) {
				albedo = trim;
				rough = 0.6;
			} else if (door) {
				albedo = fy > 0.32 && abs(bx - 0.5) < 0.12 ? vec3(0.05, 0.07, 0.09) : vec3(0.09, 0.05, 0.03);
				rough = 0.4;
			} else if (kick || abs(bx - 0.07) < 0.025 || abs(bx - 0.93) < 0.025 || (fy > 0.68 && fy < 0.71)) {
				albedo = trim * 0.6;
				rough = 0.6;
			} else {
				// Glass with a sky reflection fading down the pane.
				albedo = mix(vec3(0.03, 0.045, 0.06), vec3(0.16, 0.22, 0.3), smoothstep(0.1, 0.8, fy) * 0.6);
				rough = 0.05;
				spec = 0.9;
			}
		} else if (!modern) {
			vec2 lo = is_house ? vec2(0.36, 0.28) : vec2(0.33, 0.22);
			vec2 hi = is_house ? vec2(0.64, 0.8) : vec2(0.67, 0.8);
			float fw = is_house ? 0.05 : 0.03;
			// Victorian windows have a shallow arched top.
			float arch = 0.0;
			if (!is_house) {
				float u = (bx - 0.5) / (hi.x - lo.x) * 2.0;
				arch = 0.05 * sqrt(max(0.0, 1.0 - u * u));
			}
			float top = hi.y + arch;
			bool in_glass = bx > lo.x && bx < hi.x && fy > lo.y && fy < top;
			bool in_frame = bx > lo.x - fw && bx < hi.x + fw && fy > lo.y - fw && fy < top + fw;
			bool sill = bx > lo.x - 0.06 && bx < hi.x + 0.06 && fy > lo.y - 0.05 && fy < lo.y - fw;
			bool hood = !is_house && bx > lo.x - 0.05 && bx < hi.x + 0.05 && fy > top + fw && fy < top + fw + 0.05;
			if (in_glass) {
				bool muntin = abs(fy - (lo.y + hi.y) * 0.5) < 0.012 || abs(bx - 0.5) < 0.008;
				albedo = muntin ? trim : mix(vec3(0.03, 0.04, 0.055), vec3(0.15, 0.2, 0.27), smoothstep(lo.y, top, fy) * 0.7);
				rough = muntin ? 0.6 : 0.06;
				spec = muntin ? 0.5 : 0.85;
			} else if (in_frame || sill || hood) {
				albedo = (sill || hood) && style < 0.5 ? vec3(0.62, 0.58, 0.5) : trim;
				rough = 0.6;
			}
			// A front door on the ground floor of houses (second bay).
			if (is_house && fi < 0.5 && bay > 0.5 && bay < 1.5) {
				if (bx > 0.36 && bx < 0.64 && fy < 0.72) {
					// Door colour picked per house: red, navy or green.
					float pick = hash(vec2(COLOR.r * 31.0, COLOR.b * 17.0));
					vec3 door = pick < 0.34 ? vec3(0.3, 0.03, 0.02) : (pick < 0.67 ? vec3(0.02, 0.04, 0.12) : vec3(0.03, 0.1, 0.05));
					albedo = (bx > 0.37 && bx < 0.63 && fy < 0.7) ? door : trim;
					rough = 0.5;
					spec = 0.4;
				}
			}
		}
		// String course between the shopfront and the floors above.
		if (tall_ground && abs(p.y - gf) < 0.12) {
			albedo = trim;
			rough = 0.6;
		}
	}
	if (style > 5.5 && style < 6.5) {
		albedo = COLOR.rgb;
		rough = 0.7;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
}
