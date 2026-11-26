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

#include "res://shaders/include/building_wall_body.gdshaderinc"
