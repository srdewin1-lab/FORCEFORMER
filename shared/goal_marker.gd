@tool
extends Label3D
@export var marker_height = 1.0
func _process(_delta: float) -> void:
 var orb = get_parent().get_node_or_null("Beacons/BOrb")
 if orb == null: return
 position = get_parent().to_local(orb.global_position)+Vector3(0,marker_height-1.5,0)
