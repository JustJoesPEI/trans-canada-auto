// The building materials' layers (textures/facade/wall_materials.png and
// roof_materials.png, made by tools/make_building_materials.py), shared by
// the wall and roof shaders. The roofs' array starts at MAT_ASPHALT_SHINGLE.
// One entry per layer, in the order of the tool's LAYERS list. To add one:
// draw it in the tool, add its number here and a row to each table
// (docs/world_art.md, "Building materials").

const int MAT_BRICK = 0;
const int MAT_CLAPBOARD = 1;
const int MAT_VINYL = 2;
const int MAT_CEDAR = 3;
const int MAT_SANDSTONE = 4;
const int MAT_STUCCO = 5;
const int MAT_BLOCK = 6;
const int MAT_FIELDSTONE = 7;
const int MAT_ASPHALT_SHINGLE = 8;
const int MAT_STANDING_SEAM = 9;
const int MAT_FLAT_ROOF = 10;

// The real size one layer covers (metres along, metres up). The tool draws
// each at this size: change both together.
const vec2 MAT_TILE[11] = vec2[11](
	vec2(1.8, 1.8), vec2(2.4, 1.2), vec2(3.6, 1.2), vec2(1.5, 1.5),
	vec2(2.4, 2.4), vec2(2.0, 2.0), vec2(1.6, 1.6), vec2(1.5, 1.5),
	vec2(2.0, 1.4), vec2(1.6, 1.6), vec2(3.84, 3.84));

// What the joints are: the building's colour times MAT_JOINT_K where that
// is above 0 (a shadow under a lap, a seam), else the colour MAT_JOINT
// (linear: mortar).
const float MAT_JOINT_K[11] = float[11](0.0, 0.35, 0.45, 0.25, 0.0, 0.6, 0.85, 0.0, 0.35, 1.25, 0.7);
const vec3 MAT_JOINT[11] = vec3[11](
	vec3(0.42, 0.4, 0.36), vec3(0.0), vec3(0.0), vec3(0.0),
	vec3(0.55, 0.5, 0.44), vec3(0.0), vec3(0.0), vec3(0.3, 0.29, 0.27),
	vec3(0.0), vec3(0.0), vec3(0.0));

// Metres of relief for the height channel's full range (the bump on High).
const float MAT_RELIEF[11] = float[11](0.025, 0.02, 0.012, 0.02, 0.03, 0.008, 0.02, 0.035, 0.012, 0.015, 0.01);
// Roughness of the face (joints a little rougher).
const float MAT_ROUGH[11] = float[11](0.85, 0.75, 0.55, 0.85, 0.85, 0.9, 0.85, 0.85, 0.92, 0.45, 0.9);
