shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, fog_disabled, shadows_disabled;

#define XENO_TRANSLUCENT
#include "res://rendering/optical/optical_surface_body.gdshaderinc"
