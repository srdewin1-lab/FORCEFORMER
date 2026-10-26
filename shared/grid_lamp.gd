@tool
extends Node3D
# A painted Lamp keeps its mesh in GridMap; this supplies its glow and actual light.
const COLOUR = Color("f3d4a2")
var strength = 1.0
func _ready() -> void:
 var bulb = MeshInstance3D.new()
 bulb.name = "Bulb"
 bulb.position.y = 1.5
 var mesh = SphereMesh.new()
 mesh.radius = .17
 mesh.height = .34
 bulb.mesh = mesh
 var material = StandardMaterial3D.new()
 material.albedo_color = COLOUR
 material.emission_enabled = true
 material.emission = COLOUR
 bulb.material_override = material
 add_child(bulb)
 var light = OmniLight3D.new()
 light.name = "Light"
 light.position.y = 1.5
 light.light_color = COLOUR
 light.omni_range = 8
 light.shadow_enabled = false
 add_child(light)
 set_strength(strength)
func set_strength(value: float) -> void:
 strength = clampf(value,0,2)
 if not has_node("Light"): return
 $Light.light_energy = 2.4*strength
 $Bulb.material_override.emission_energy_multiplier = 2.8*strength
