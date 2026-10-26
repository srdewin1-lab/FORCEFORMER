shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 tile_colour : source_color = vec4(0.7,0.75,0.65,1.0);
varying vec3 cell_position;
void vertex() { cell_position = VERTEX; }
void fragment() {
 float edge = step(0.485, max(abs(cell_position.x), abs(cell_position.z)));
 ALBEDO = mix(tile_colour.rgb, tile_colour.rgb*0.91, edge);
 ROUGHNESS = 0.9;
}
