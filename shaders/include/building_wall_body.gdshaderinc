// The body of building_wall.gdshader and building_wall_fade.gdshader (which defines
// FADE: only the faded copies of the material, for the few buildings in the
// camera's way, can discard; the shared one can't, so the town's buildings
// keep the depth test's early-out).

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
// The wall materials (textures/facade/wall_materials.png, made by
// tools/make_building_materials.py), one layer each: R shade (0.5 = the
// building's colour), G joint (mortar, gaps, seams), B height. The tables
// (shared with the roofs) are in the same order as the tool's LAYERS list.
uniform sampler2DArray wall_materials : filter_linear_mipmap_anisotropic, repeat_enable;
#include "res://shaders/include/building_materials.gdshaderinc"
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

// Which material layer a wall style is drawn with (-1: plain colour).
// `pick` is the building's own random number: half the clapboard houses
// are vinyl-sided, and a third of the painted buildings are painted brick.
int wall_layer(float style, float pick) {
	if (style < 0.5) return MAT_BRICK;
	if (style < 1.5) return pick < 0.45 ? MAT_VINYL : MAT_CLAPBOARD;
	if (style < 2.5) return MAT_SANDSTONE;
	if (style < 3.5) return pick < 0.3 ? MAT_BRICK : MAT_STUCCO;
	if (style < 4.5) return MAT_BLOCK;
	if (style < 5.5) return MAT_CEDAR;
	if (style < 6.5) return -1;
	if (style < 7.5) return MAT_SANDSTONE;
	if (style < 8.5) return MAT_FIELDSTONE;
	return MAT_SANDSTONE;
}

float bay_metres(float style) {
	if (style < 0.5) return 2.0; // Victorian brick: narrow bays
	if (style > 3.5 && style < 4.5) return 3.0;
	if (style > 8.5) return 2.6; // ribbed sandstone (Confederation Centre)
	if (style > 6.5) return 3.4;
	return 2.6;
}

void fragment() {
	float f = fade;
	if (fade_levels != vec4(0.0)) {
		vec4 hit = vec4(equal(fade_ids, vec4(building_id)));
		f = max(f, max(max(hit.x * fade_levels.x, hit.y * fade_levels.y), max(hit.z * fade_levels.z, hit.w * fade_levels.w)));
	}
#ifdef FADE
	if (f > 0.0 && ign(FRAGCOORD.xy) < f) {
		discard;
	}
#endif
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
	// don't line up joint for joint, and picks its variant (vinyl or wood
	// siding, painted brick or render) by its own number.
	float pick = d_hash(COLOR.rg * 91.0 + building_id * 0.37);
	vec2 tex_off = vec2(pick * 7.0, d_hash(COLOR.gb * 53.0));
	int layer = wall_layer(style, pick);
	bool painted_brick = style > 2.5 && style < 3.5 && layer == 0;
	// The material: one array read on every level (Low too); the height in
	// its blue channel is only turned into light and shade on High.
	// tex_grad: the material's slope (metres per metre along and up), on
	// High only; tex_k goes to 0 where a window or trim is drawn over it.
	vec2 tex_grad = vec2(0.0);
	float tex_k = 1.0;
	if (layer >= 0) {
		// The layers are drawn with the image's top row at the top of the
		// wall: up the wall is down the texture.
		vec2 tscale = vec2(1.0, -1.0) / MAT_TILE[layer];
		vec2 tuv = vec2(mx, p.y) * tscale + tex_off;
		vec3 m = texture(wall_materials, vec3(tuv, float(layer))).rgb;
		if (gfx_detail > 0.5 && fine_ok > 0.0) {
			vec2 e = max(fwidth(tuv), vec2(1.0 / 1024.0));
			float hx = texture(wall_materials, vec3(tuv + vec2(e.x, 0.0), float(layer))).b;
			float hy = texture(wall_materials, vec3(tuv - vec2(0.0, e.y), float(layer))).b;
			tex_grad = vec2(hx - m.b, hy - m.b) / (e * MAT_TILE[layer]) * MAT_RELIEF[layer] * fine_ok;
		}
		float sh = m.r * 2.0;
		if (painted_brick) {
			// Paint evens out the bricks and fills the mortar with its colour.
			sh = mix(1.0, sh, 0.35);
			wall = COLOR.rgb * sh * mix(1.0, 0.82, m.g);
		} else {
			vec3 jc = MAT_JOINT_K[layer] > 0.0 ? COLOR.rgb * MAT_JOINT_K[layer] : MAT_JOINT[layer];
			wall = mix(COLOR.rgb, jc, m.g) * sh;
		}
		rough = MAT_ROUGH[layer] + 0.12 * m.g;
	}
	// Ribbed sandstone (style 9, Confederation Centre): ashlar with a
	// vertical rib every 1.2 m, groups of three tall slot windows every
	// 14 m, and (with the shop flag) the glass curtain wall of a lobby.
	bool ribbed_slot = false;
	bool ribbed_glass = false;
	if (style > 8.5) {
		float f = fract(mx / 1.2);
		float rib = smoothstep(0.0, 0.14, f) * (1.0 - smoothstep(0.86, 1.0, f));
		wall *= 0.78 + 0.22 * rib;
		relief = rib;
		relief_scale = 0.05;
		if (shop_building) {
			ribbed_glass = true;
		} else {
			float m14 = mod(mx, 14.0);
			float slot_top = COLOR.a * 16.0 * floor_height - 2.2;
			ribbed_slot = p.y > 1.2 && p.y < slot_top && (abs(m14 - 5.0) < 0.25 || abs(m14 - 6.4) < 0.25 || abs(m14 - 7.8) < 0.25);
		}
	} else if (style > 7.5) {
		// Foundation stone (only ever on the plinths and exposed footings):
		// mostly grey fieldstone, darker than the stone colour it's given.
		wall *= 0.55;
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
	if (ribbed_glass) {
		bool mullion = fract(mx / 1.5) < 0.035 || fract(p.y / 2.2) < 0.03;
		albedo = mullion ? vec3(0.07, 0.07, 0.075) : mix(vec3(0.02, 0.028, 0.035), vec3(0.13, 0.17, 0.22), smoothstep(0.0, 8.0, p.y) * 0.7);
		rough = mullion ? 0.45 : 0.04;
		metal = mullion ? 0.6 : 0.0;
		spec = 0.9;
		relief = mullion ? 0.4 : 0.0; tex_k = 0.0;
	} else if (ribbed_slot) {
		albedo = vec3(0.025, 0.03, 0.036);
		rough = 0.06;
		spec = 0.9;
		relief = -1.0; tex_k = 0.0;
	}

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
			rough = 0.25; relief = 0.0; tex_k = 0.0;
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
				rough = 0.5; relief = 0.0; tex_k = 0.0;
			} else if (pilaster || fy > 0.95) {
				albedo = trim;
				rough = 0.6; relief = 0.0; tex_k = 0.0;
			} else if (door) {
				albedo = fy > 0.32 && abs(bx - 0.5) < 0.12 ? vec3(0.05, 0.07, 0.09) : vec3(0.09, 0.05, 0.03);
				rough = 0.4; relief = 0.0; tex_k = 0.0;
			} else if (kick || abs(bx - 0.07) < 0.025 || abs(bx - 0.93) < 0.025 || (fy > 0.68 && fy < 0.71)) {
				albedo = trim * 0.6;
				rough = 0.6; relief = 0.0; tex_k = 0.0;
			} else {
				// Glass with a sky reflection fading down the pane.
				albedo = mix(vec3(0.03, 0.045, 0.06), vec3(0.16, 0.22, 0.3), smoothstep(0.1, 0.8, fy) * 0.6);
				rough = 0.05; relief = 0.0; tex_k = 0.0;
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
			float arch = is_house ? 0.0 : 0.05 * sqrt(max(0.0, 1.0 - u_c * u_c));
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
					rough = 0.85; relief = 0.0; tex_k = 0.0;
					spec = 0.3;
				} else {
					bool in_glass = g.x > lo.x && g.x < hi.x && g.y > lo.y && g.y < top;
					float mid_y = (lo.y + hi.y) * 0.5;
					bool muntin = abs(g.y - mid_y) < 0.014 || abs(g.x - 0.5) < 0.009;
					if (!in_glass || muntin) {
						albedo = trim;
						rough = 0.6; relief = 0.0; tex_k = 0.0;
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
						rough = 0.03 + 0.1 * d_hash(vec2(wid, floor(g.y / max(0.01, mid_y)))); relief = 0.0; tex_k = 0.0;
						spec = 0.9;
					}
				}
			} else if (casing || sill || hood) {
				albedo = (sill || hood) && style < 0.5 ? vec3(0.62, 0.58, 0.5) : trim;
				rough = 0.6; relief = 0.0; tex_k = 0.0;
				relief = sill || hood ? 0.5 : 0.3; tex_k = 0.0;
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
					rough = 0.5; relief = 0.0; tex_k = 0.0;
					spec = 0.4;
				}
			}
		}
		// String course between the shopfront and the floors above.
		if (tall_ground && abs(p.y - gf) < 0.12) {
			albedo = trim;
			rough = 0.6; relief = 0.0; tex_k = 0.0;
		}
	}
	if (style > 5.5 && style < 6.5) {
		albedo = COLOR.rgb;
		rough = 0.7; relief = 0.0; tex_k = 0.0;
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	if (gfx_detail > 0.5 && fine_ok > 0.0) {
		NORMAL = d_bump(NORMAL, VERTEX, relief * relief_scale * fine_ok, 1.0);
		if (tex_k > 0.5 && tex_grad != vec2(0.0)) {
			NORMAL = d_tex_bump(NORMAL, VERTEX, vec2(mx, p.y), tex_grad);
		}
	}
}
