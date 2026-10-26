shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 glow_colour : source_color = vec4(1.,.86,.56,1.);
uniform float strength = .6;
void vertex() {
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
 float distance_from_center = length(UV-vec2(.5))*2.;
 float falloff = pow(max(0.,1.-distance_from_center),2.5);
 ALBEDO = glow_colour.rgb*strength;
 ALPHA = falloff*glow_colour.a;
}
