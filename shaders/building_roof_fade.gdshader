// building_roof.gdshader for the faded copies (BuildingFade, CameraRig): the
// same, and dithered away by `fade` / `fade_levels`.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

#define FADE
#include "res://shaders/include/building_roof_body.gdshaderinc"
