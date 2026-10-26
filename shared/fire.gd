@tool
extends Node3D
const Visuals = preload("res://shared/element_visuals.gd")
@export_range(.2,12,.1) var brightness = 1.2
@export_range(1,20,.5) var reach = 8.0
var age = 0.0
func _ready() -> void:
 for i in range(3):
  var flame = MeshInstance3D.new()
  flame.name = "Flame%d" % i
  flame.mesh = Visuals.drop_mesh()
  flame.position = Vector3((i-1)*.12,.3+(.1 if i==1 else 0),0)
  var mat = StandardMaterial3D.new()
  mat.albedo_color = Color("ffdc87") if i==1 else Color("ee8c47")
  mat.emission_enabled = true
  mat.emission = mat.albedo_color
  mat.emission_energy_multiplier = 1.2
  flame.material_override = mat
  add_child(flame)
 var glow = Visuals.halo(Color("ffab5c"),2.8)
 glow.position.y = .4
 add_child(glow)
 var light = OmniLight3D.new()
 light.name = "Light"
 light.position.y = .6
 light.light_color = Color("ffad60")
 light.shadow_enabled = true
 light.light_energy = brightness
 light.omni_range = reach
 add_child(light)
func _process(delta: float) -> void:
 if not has_node("Light"): return
 age += delta
 $Light.light_energy = brightness*(1+sin(age*8)*.07+sin(age*13)*.03)
 $Light.omni_range = reach
 for i in range(3):
  var flame = get_node("Flame%d" % i)
  flame.scale = Vector3(1.8,1.6+sin(age*8+i)*.2,1.8)
  flame.rotation.z = sin(age*5+i)*.12
