@tool
extends Node3D
const Visuals = preload("res://shared/element_visuals.gd")
@export var colour = Color("ffe0a3")
@export var radius = .5
@export var brightness = 3.2
@export var reach = 24.0
@export var pulse = false
var age = 0.0
func _ready() -> void:
 var orb = MeshInstance3D.new()
 orb.name = "Orb"
 var mesh = SphereMesh.new()
 mesh.radius = radius
 mesh.height = radius*2
 orb.mesh = mesh
 var mat = StandardMaterial3D.new()
 mat.albedo_color = colour
 mat.emission_enabled = true
 mat.emission = colour
 mat.emission_energy_multiplier = 2.8
 orb.material_override = mat
 add_child(orb)
 var glow = Visuals.halo(colour,5.5)
 add_child(glow)
 var light = OmniLight3D.new()
 light.name = "Light"
 light.light_color = colour
 light.light_energy = brightness
 light.omni_range = reach
 light.shadow_enabled = true
 add_child(light)
func _process(delta: float) -> void:
 age += delta
 var level = 1.0+.08*sin(TAU*age/3.6) if pulse else 1.0
 if not has_node("Light"): return
 $Light.light_energy = brightness*level
 $Light.light_color = colour
 $Light.omni_range = reach
 $Orb.material_override.emission_energy_multiplier = 2.8*level
 $Glow.material_override.set_shader_parameter("strength",.8*level)
