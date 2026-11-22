// Small helpers shared by the town's shaders: hashes and value noise, and a
// bump that tilts the surface normal from a height pattern without needing
// tangents (works on any generated mesh, on every renderer).
//
// `gfx_detail` is set by the Graphics autoload: 1 on High, 0 on Low. Fine
// relief and extras are skipped on Low.
global uniform float gfx_detail;

float d_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float d_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(d_hash(i), d_hash(i + vec2(1.0, 0.0)), u.x), mix(d_hash(i + vec2(0.0, 1.0)), d_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float d_fbm(vec2 p) {
	return d_noise(p) * 0.5 + d_noise(p * 2.03 + 17.1) * 0.3 + d_noise(p * 4.37 + 5.3) * 0.2;
}

// Linear from sRGB, for colours typed by eye.
vec3 d_lin(vec3 c) {
	return pow(c, vec3(2.2));
}

// Tilts `n` (view space) by the screen-space slope of height `h` over the
// surface at view-space position `pos`. `strength` is in metres of relief
// per unit of h, roughly. From Mikkelsen, "Bump Mapping Unparametrized
// Surfaces on the GPU" (2010).
vec3 d_bump(vec3 n, vec3 pos, float h, float strength) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float dhdx = dFdx(h) * strength;
	float dhdy = dFdy(h) * strength;
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	return normalize(abs(det) * n - grad);
}
