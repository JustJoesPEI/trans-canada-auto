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
	return pow(max(c, vec3(0.0)), vec3(2.2));
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
	vec3 r = abs(det) * n - grad;
	// Tiny or edge-on triangles far away give no usable slope, and on a
	// silhouette edge the tilt can turn the surface away from the camera,
	// which makes bright specks in the lighting: keep n in those cases.
	float l = length(r);
	if (!(l > 1e-12) || !(abs(det) > 1e-14)) {
		return n;
	}
	vec3 b = r / l;
	return dot(b, normalize(-pos)) > 0.05 ? b : n;
}

// Tilts `n` (view space) by a height map's slope: `grad` is metres of rise
// per metre along `uv` (uv in metres on the surface, at `pos` in view
// space). The surface's own directions come from the screen-space change
// of pos and uv, so it needs no tangents, and unlike d_bump it doesn't
// take the slope from neighbouring pixels: a texture's slope is read from
// the texture (two more reads), so it stays smooth up close.
vec3 d_tex_bump(vec3 n, vec3 pos, vec2 uv, vec2 grad) {
	vec3 dp1 = dFdx(pos);
	vec3 dp2 = dFdy(pos);
	vec2 du1 = dFdx(uv);
	vec2 du2 = dFdy(uv);
	vec3 p2 = cross(dp2, n);
	vec3 p1 = cross(n, dp1);
	vec3 t = p2 * du1.x + p1 * du2.x;
	vec3 b = p2 * du1.y + p1 * du2.y;
	float m = max(dot(t, t), dot(b, b));
	if (!(m > 1e-20)) {
		return n;
	}
	m = inversesqrt(m);
	vec3 r = normalize(n - (grad.x * t + grad.y * b) * m);
	return dot(r, normalize(-pos)) > 0.05 ? r : n;
}
