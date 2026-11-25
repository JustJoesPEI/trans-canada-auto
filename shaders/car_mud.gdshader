// Mud on a vehicle, drawn over its body and wheels (material_overlay) only
// while it's dirty: one shared material, each vehicle's own amount and
// colour as instance uniforms (Car.dirt). Thrown up from the wheels, so it
// starts low down and climbs the body as it builds up, in splatters.
shader_type spatial;
render_mode blend_mix, depth_draw_never, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/detail.gdshaderinc"

instance uniform float dirt = 0.0;
// Linear colour (Car converts it).
instance uniform vec3 mud_colour = vec3(0.14, 0.035, 0.016);

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	// How high it's reached: the sills first, up to the windows when caked.
	float reach = 0.25 + 1.1 * dirt;
	float low = 1.0 - smoothstep(reach * 0.55, reach, lpos.y);
	float splat = d_fbm(lpos.xz * 4.0 + vec2(lpos.y * 6.0, -lpos.y * 3.0));
	float spots = d_noise(lpos.xz * 23.0 + lpos.y * 17.0);
	float flecks = d_noise(lpos.zy * 41.0 + lpos.x * 7.0);
	float cover = low * dirt * 1.25;
	// Solid low down, breaking up into splashes and then flecks higher up.
	float a = smoothstep(1.0 - cover, 1.08 - cover, splat * 0.55 + spots * 0.3 + flecks * 0.15);
	ALBEDO = mud_colour * (0.5 + 0.3 * spots + 0.2 * splat);
	ROUGHNESS = mix(0.95, 0.5, smoothstep(0.6, 0.9, splat)); // fresh mud is wet
	ALPHA = a * 0.95;
}
