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

#include "res://shaders/include/detail.gdshaderinc"

uniform float fade = 0.0;
// Buildings are merged a chunk at a time; CUSTOM0.r is each vertex's
// building number in its chunk. A faded copy of the material can fade up to
// four of them by number (fade_ids) by their own amounts (fade_levels).
uniform vec4 fade_ids = vec4(-1.0);
uniform vec4 fade_levels = vec4(0.0);
varying flat float building_id;
// 1 where the wall was built with real window holes and set-back glass
// (building id + 0.5): no painted arch, no faked depth.
varying flat float real_open;
uniform float floor_height = 3.2;
// Photographed wall surfaces (CC0, Poly Haven), one layer each:
// 0 brick, 1 sandstone ashlar, 2 painted clapboard, 3 cedar shingle,
// 4 rubble foundation stone. wall_hr: R = height, G = roughness.
uniform sampler2DArray wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray wall_hr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_photo = false;
uniform float shop_floor_height = 4.0;

void vertex() {
	building_id = floor(CUSTOM0.r + 0.25);
	real_open = step(0.25, fract(CUSTOM0.r + 0.25));
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

float hash(vec2 p) {
	return d_hash(p);
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
	float f = fade;
	if (fade_levels != vec4(0.0)) {
		vec4 hit = vec4(equal(fade_ids, vec4(building_id)));
		f = max(f, max(max(hit.x * fade_levels.x, hit.y * fade_levels.y), max(hit.z * fade_levels.z, hit.w * fade_levels.w)));
	}
	if (f > 0.0 && ign(FRAGCOORD.xy) < f) {
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
	// `relief` is a height pattern (0 = face of the wall, negative = sunk in)
	// that the bump below turns into light and shade on mortar and boards.
	float px = length(fwidth(vec2(mx, p.y)));
	float fine_ok = 1.0 - smoothstep(0.015, 0.05, px);
	float relief = 0.0;
	float relief_scale = 0.006;
	// Each building starts its texture at its own place, so neighbours
	// don't line up joint for joint.
	vec2 photo_off = vec2(d_hash(COLOR.rg * 91.0), 0.0);
	if (style > 7.5) {
		// Foundation stone (only ever on the plinths and exposed footings).
		vec2 tuv = vec2(mx, p.y) / 1.5 + photo_off;
		// Mostly grey fieldstone, as Island foundations are, with a little
		// of the stone's own colour left in.
		vec3 st = texture(wall_albedo, vec3(tuv, 4.0)).rgb;
		wall = mix(vec3(dot(st, vec3(0.2126, 0.7152, 0.0722))), st, 0.35) * COLOR.rgb * 1.7;
		vec2 hr = texture(wall_hr, vec3(tuv, 4.0)).rg;
		relief = hr.r - 0.5;
		relief_scale = 0.06;
		rough = 0.75 + 0.25 * hr.g;
	} else if (use_photo && (style < 0.5 || (style > 1.5 && style < 2.5) || (style > 6.5 && style < 7.5) || (style > 0.5 && style < 1.5) || (style > 4.5 && style < 5.5))) {
		float layer = style < 0.5 ? 0.0 : (style < 1.5 ? 2.0 : (style < 2.5 || style > 6.5 ? 1.0 : 3.0));
		float tile = layer < 0.5 ? 1.0 : (layer < 1.5 ? 2.0 : (layer < 2.5 ? 1.0 : 1.5));
		vec2 tuv = vec2(mx, p.y) / tile + photo_off;
		vec3 tx = texture(wall_albedo, vec3(tuv, layer)).rgb;
		vec2 hr = texture(wall_hr, vec3(tuv, layer)).rg;
		if (layer > 1.5 && layer < 2.5) {
			// Painted boards: the photo gives the boards, the cracks and the
			// worn paint; the building's own colour is the paint.
			float l = dot(tx, vec3(0.2126, 0.7152, 0.0722)) / 0.1387;
			wall = COLOR.rgb * mix(1.0, clamp(l, 0.2, 1.8), 0.75);
			relief_scale = 0.02;
		} else {
			vec3 avg = layer < 0.5 ? vec3(0.156, 0.0983, 0.0812) : (layer < 1.5 ? vec3(0.2759, 0.2138, 0.1537) : vec3(0.2998, 0.2557, 0.1949));
			vec3 tint = clamp(COLOR.rgb / avg, vec3(0.3), vec3(3.0));
			wall = tx * mix(vec3(1.0), tint, 0.8);
			relief_scale = layer < 0.5 ? 0.025 : 0.035;
		}
		relief = hr.r - 0.5;
		rough = 0.7 + 0.3 * hr.g;
	} else if (style < 0.5) {
		float row = floor(p.y / 0.076);
		float shifted = mx + mod(row, 2.0) * 0.115;
		float bx = fract(shifted / 0.23);
		float by = fract(p.y / 0.076);
		float mortar = max(step(bx, 0.045), step(by, 0.14));
		// Distance to the nearest joint in metres, for a rounded mortar groove.
		float mortar_soft = max(1.0 - smoothstep(0.0, 0.014, min(bx, 1.0 - bx) * 0.23), 1.0 - smoothstep(0.0, 0.009, min(by, 1.0 - by) * 0.076));
		float brick_id = d_hash(vec2(floor(shifted / 0.23), row));
		wall *= 0.86 + 0.28 * brick_id;
		// A few burnt dark headers and pale soft bricks.
		wall *= brick_id > 0.93 ? 0.7 : 1.0;
		wall = mix(wall, vec3(0.45, 0.42, 0.38), mortar * 0.45 * fine_ok + 0.12 * (1.0 - fine_ok));
		relief = -mortar_soft;
	} else if (style < 1.5) {
		float f = fract(p.y / 0.16);
		wall *= 0.84 + 0.16 * smoothstep(0.0, 0.3, f);
		relief = f; // each board laps over the one below
		relief_scale = 0.012;
		rough = 0.8;
	} else if (style < 2.5 || style > 6.5) {
		float row = floor(p.y / 0.45);
		float sx = (mx + mod(row, 2.0) * 0.4) / 0.8;
		float joint = max(step(fract(sx), 0.02), step(fract(p.y / 0.45), 0.04));
		wall *= 0.9 + 0.16 * d_hash(vec2(floor(sx), row));
		// Sandstone weathers in soft patches.
		wall *= 0.9 + 0.14 * d_fbm(vec2(mx, p.y) * 1.3);
		wall = mix(wall, wall * 0.72, joint);
		relief = -joint;
	} else if (style > 3.5 && style < 4.5) {
		float panel = max(step(fract(mx / 1.5), 0.01), step(fract(p.y / 1.2), 0.012));
		wall = mix(wall, wall * 0.82, panel);
		relief = -panel;
	} else if (style > 4.5 && style < 5.5) {
		float row = floor(p.y / 0.14);
		float sx = (mx + d_hash(vec2(row, 3.0)) * 0.3) / 0.18;
		wall *= 0.8 + 0.25 * d_hash(vec2(floor(sx), row));
		float f = fract(p.y / 0.14);
		wall *= 0.9 + 0.1 * smoothstep(0.0, 0.35, f);
		relief = f - step(fract(sx), 0.04);
		relief_scale = 0.01;
	}
	// Weathering: broad mottling, and grime splashed up the bottom of the wall.
	float mottle = d_fbm(vec2(mx, p.y) * 0.35 + COLOR.rg * 40.0);
	wall *= 0.9 + 0.16 * mottle;
	// Rain running down from the roof leaves faint vertical streaks.
	wall *= 1.0 - 0.1 * smoothstep(0.55, 0.9, d_noise(vec2(mx * 2.5, p.y * 0.06 + COLOR.b * 30.0)));
	float base_grime = 1.0 - smoothstep(-0.2, 0.9, p.y);
	wall = mix(wall, wall * vec3(0.55, 0.52, 0.48), base_grime * (0.55 + 0.3 * d_noise(vec2(mx * 3.0, 0.0))));

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
	// The view direction in the wall's own frame: x along the wall (the way
	// UV.x grows), y up, z out of the wall. Used for the depth of windows.
	vec3 wall_view = vec3(0.0, 0.0, 1.0);
	if (gfx_detail > 0.5) {
		vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec3 along_v = normalize(cross(up_v, NORMAL));
		if (dot(along_v, dFdx(VERTEX)) * dFdx(UV.x) + dot(along_v, dFdy(VERTEX)) * dFdy(UV.x) < 0.0) {
			along_v = -along_v;
		}
		wall_view = vec3(dot(VIEW, along_v), dot(VIEW, up_v), dot(VIEW, NORMAL));
	}
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
			rough = 0.25; relief = 0.0;
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
				rough = 0.5; relief = 0.0;
			} else if (pilaster || fy > 0.95) {
				albedo = trim;
				rough = 0.6; relief = 0.0;
			} else if (door) {
				albedo = fy > 0.32 && abs(bx - 0.5) < 0.12 ? vec3(0.05, 0.07, 0.09) : vec3(0.09, 0.05, 0.03);
				rough = 0.4; relief = 0.0;
			} else if (kick || abs(bx - 0.07) < 0.025 || abs(bx - 0.93) < 0.025 || (fy > 0.68 && fy < 0.71)) {
				albedo = trim * 0.6;
				rough = 0.6; relief = 0.0;
			} else {
				// Glass with a sky reflection fading down the pane.
				albedo = mix(vec3(0.03, 0.045, 0.06), vec3(0.16, 0.22, 0.3), smoothstep(0.1, 0.8, fy) * 0.6);
				rough = 0.05; relief = 0.0;
				spec = 0.9;
			}
		} else if (!modern) {
			vec2 lo = is_house ? vec2(0.36, 0.28) : vec2(0.33, 0.22);
			vec2 hi = is_house ? vec2(0.64, 0.8) : vec2(0.67, 0.8);
			float fw = is_house ? 0.05 : 0.03;
			float fh = fi < 0.5 ? gf : floor_height;
			float bay_m = bay_metres(style);
			// The opening, as seen on the face of the wall. Victorian windows
			// have a shallow arched top.
			float u_c = (bx - 0.5) / (hi.x - lo.x) * 2.0;
			float arch = is_house || real_open > 0.5 ? 0.0 : 0.05 * sqrt(max(0.0, 1.0 - u_c * u_c));
			float top = hi.y + arch;
			float sash = is_house ? 0.012 : 0.03; // sash frame inside the opening
			bool in_open = bx > lo.x - sash && bx < hi.x + sash && fy > lo.y - sash && fy < top + sash;
			bool casing = is_house && !in_open && bx > lo.x - sash - fw && bx < hi.x + sash + fw && fy > lo.y - sash - fw && fy < top + sash + fw;
			bool sill = bx > lo.x - 0.06 && bx < hi.x + 0.06 && fy > lo.y - sash - 0.05 && fy < lo.y - sash;
			bool hood = !is_house && real_open < 0.5 && bx > lo.x - 0.05 && bx < hi.x + 0.05 && fy > top + sash && fy < top + sash + 0.05;
			if (in_open) {
				// The glass sits back in the wall: follow the view ray in to
				// the glass and see whether it lands on the window or on the
				// side of the opening (the reveal).
				vec2 g = vec2(bx, fy);
				float reveal_side = 0.0;
				if (gfx_detail > 0.5 && real_open < 0.5) {
					float depth = is_house ? 0.06 : 0.13;
					vec2 off = -wall_view.xy / max(wall_view.z, 0.2) * depth;
					g += vec2(off.x / bay_m, off.y / fh);
					float u_g = (g.x - 0.5) / (hi.x - lo.x) * 2.0;
					float top_g = hi.y + (is_house ? 0.0 : 0.05 * sqrt(max(0.0, 1.0 - u_g * u_g)));
					if (g.y > top_g + sash) reveal_side = 3.0; // soffit
					else if (g.y < lo.y - sash) reveal_side = 1.0; // sill
					else if (g.x < lo.x - sash || g.x > hi.x + sash) reveal_side = 2.0; // jamb
				}
				if (reveal_side > 0.5) {
					vec3 rv = is_house ? trim : wall;
					albedo = rv * (reveal_side > 2.5 ? 0.35 : (reveal_side > 1.5 ? 0.6 : 0.85));
					rough = 0.85; relief = 0.0;
					spec = 0.3;
				} else {
					bool in_glass = g.x > lo.x && g.x < hi.x && g.y > lo.y && g.y < top;
					float mid_y = (lo.y + hi.y) * 0.5;
					bool muntin = abs(g.y - mid_y) < 0.014 || abs(g.x - 0.5) < 0.009;
					if (!in_glass || muntin) {
						albedo = trim;
						rough = 0.6; relief = 0.0;
					} else {
						// What's behind each window: a dark room, curtains,
						// a blind part way down, or a lamp on.
						float wid = d_hash(vec2(bay, fi) + COLOR.rg * 57.0 + p.x * 0.001);
						float gx = (g.x - lo.x) / (hi.x - lo.x);
						float gy = (g.y - lo.y) / (top - lo.y);
						vec3 room = vec3(0.025, 0.028, 0.032) * (0.7 + 0.6 * gy);
						vec3 inside = room;
						if (wid < 0.3) {
							float cw = 0.18 + 0.12 * d_hash(vec2(wid, 3.0));
							vec3 cloth = d_lin(wid < 0.1 ? vec3(0.82, 0.78, 0.68) : (wid < 0.2 ? vec3(0.5, 0.16, 0.14) : vec3(0.3, 0.38, 0.3)));
							float folds = 0.75 + 0.25 * sin(gx * 60.0);
							inside = (gx < cw || gx > 1.0 - cw) ? cloth * 0.5 * folds : room;
						} else if (wid < 0.55) {
							float level = 0.35 + 0.5 * d_hash(vec2(wid, 9.0));
							float slat = 0.85 + 0.15 * step(0.5, fract(gy * 30.0));
							inside = gy > 1.0 - level ? d_lin(vec3(0.75, 0.72, 0.64)) * 0.45 * slat : room;
						} else if (wid > 0.9) {
							EMISSION = d_lin(vec3(1.0, 0.8, 0.55)) * 0.18 * (0.6 + 0.4 * gy);
							inside = d_lin(vec3(0.5, 0.42, 0.32)) * 0.3;
						}
						albedo = inside;
						// Old glass isn't perfectly flat: each pane reflects a little differently.
						rough = 0.03 + 0.1 * d_hash(vec2(wid, floor(g.y / max(0.01, mid_y)))); relief = 0.0;
						spec = 0.9;
					}
				}
			} else if (casing || sill || hood) {
				albedo = (sill || hood) && style < 0.5 ? vec3(0.62, 0.58, 0.5) : trim;
				rough = 0.6; relief = 0.0;
				relief = sill || hood ? 0.5 : 0.3;
			} else if (bx > lo.x - 0.02 && bx < hi.x + 0.02 && fy < lo.y - sash && fy > lo.y - sash - 0.35 * (0.6 + 0.4 * d_hash(vec2(bay, fi)))) {
				// Rain streaks running down from the sill.
				float st = d_noise(vec2(mx * 14.0, fi * 3.0 + bay));
				albedo *= 1.0 - 0.18 * smoothstep(0.4, 0.8, st) * smoothstep(lo.y - sash - 0.35, lo.y - sash, fy);
			}
			// A front door on the ground floor of houses (second bay).
			if (is_house && fi < 0.5 && bay > 0.5 && bay < 1.5) {
				if (bx > 0.36 && bx < 0.64 && fy < 0.72) {
					// Door colour picked per house: red, navy or green.
					float pick = hash(vec2(COLOR.r * 31.0, COLOR.b * 17.0));
					vec3 door = pick < 0.34 ? vec3(0.3, 0.03, 0.02) : (pick < 0.67 ? vec3(0.02, 0.04, 0.12) : vec3(0.03, 0.1, 0.05));
					albedo = (bx > 0.37 && bx < 0.63 && fy < 0.7) ? door : trim;
					rough = 0.5; relief = 0.0;
					spec = 0.4;
				}
			}
		}
		// String course between the shopfront and the floors above.
		if (tall_ground && abs(p.y - gf) < 0.12) {
			albedo = trim;
			rough = 0.6; relief = 0.0;
		}
	}
	if (style > 5.5 && style < 6.5) {
		albedo = COLOR.rgb;
		rough = 0.7; relief = 0.0;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	if (gfx_detail > 0.5 && fine_ok > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, relief * relief_scale * fine_ok, 1.0);
	}
}
