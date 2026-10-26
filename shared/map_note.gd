@tool
extends Node3D
@export_multiline var text = "Write a note for someone exploring this map.":
 set(value): text = value; refresh()
@export_range(2,60,1) var reading_distance = 12.0
var label: Label3D
func _ready() -> void:
 label = Label3D.new()
 label.name = "Text"
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 label.font_size = 36
 label.pixel_size = .006
 label.outline_size = 4
 label.outline_modulate = Color("101014")
 label.modulate = Color("f1e5cf")
 add_child(label)
 refresh()
func refresh() -> void:
 if is_instance_valid(label): label.text = text
func _process(_delta: float) -> void:
 if not is_instance_valid(label) or Engine.is_editor_hint(): return
 var camera = get_viewport().get_camera_3d()
 label.visible = camera != null and camera.global_position.distance_to(global_position)<=reading_distance
