shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#define XENO_TRANSLUCENT
#define XENO_REFRACTIVE
#include "res://rendering/optical/optical_surface_body.gdshaderinc"
