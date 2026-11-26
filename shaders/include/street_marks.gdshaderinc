// Marks on the streets and sidewalks (textures/ground/street_decals.png,
// made by tools/make_street_decals.py): one mark centred in each 512 px
// layer, RGB the change to the surface under it (a multiplier, 0.5 = none),
// A how much of it is there. The asphalt and sidewalk shaders place them
// from a hash of the spot, at most one per cell of a grid, so a pixel
// reads one or two and none is a node or a Decal.
//
// Layers: 0 cracking, 1 sealed cracks, 2 patch, 3 manhole cover,
// 4 storm drain (long side along x), 5 oil stain, 6 tyre marks,
// 7 ravelled asphalt.

uniform sampler2DArray street_decals : filter_linear_mipmap_anisotropic, repeat_disable;

// Roughness each mark leaves (-1: the surface's own).
const float MARK_ROUGH[8] = float[8](-1.0, 0.45, -1.0, 0.55, 0.6, 0.55, 0.7, -1.0);

// The mark `layer` at q (-1..1 across the mark's square), with q's change
// per pixel given (it's read inside branches, where the GPU's own
// derivatives can't be trusted). Outside the square: nothing, unread.
vec4 street_mark(vec2 q, vec2 dqx, vec2 dqy, float layer) {
	if (abs(q.x) >= 1.0 || abs(q.y) >= 1.0) {
		return vec4(0.5, 0.5, 0.5, 0.0);
	}
	return textureGrad(street_decals, vec3(q * 0.5 + 0.5, layer), dqx * 0.5, dqy * 0.5);
}

// A rotation by `a` radians.
mat2 mark_rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}
