// Roofs (and shop awnings) for every generated building, in one material.
//   COLOR rgb = colour (linear)
//   UV2   x = 0 flat roof, 1 shingled pitched roof or spire,
//           2 striped canvas awning, 3 plain canvas awning, 4 copper
//   UV    x = metres across, y = metres up the slope
//   fade  0 on the shared material; a faded copy is made only while a
//         building hides the player (see camera_rig.gd)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#include "res://shaders/include/building_roof_body.gdshaderinc"
