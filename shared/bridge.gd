@tool
extends Node3D
# An editable span: origin at the starting end, along local +X.
# Rise may be negative. The deck and rails use real native collision.
@export_range(.5,48,.1,"suffix:m") var length = 12.0:
 set(value):length=maxf(.5,value);queue_rebuild()
@export_range(.8,16,.1,"suffix:m") var width = 4.2:
 set(value):width=maxf(.8,value);queue_rebuild()
@export_range(-8,8,.1,"suffix:m") var rise = 0.0:
 set(value):rise=value;queue_rebuild()
@export var rails = false:
 set(value):rails=value;queue_rebuild()
@export var left_rail = true:
 set(value):left_rail=value;queue_rebuild()
@export var right_rail = true:
 set(value):right_rail=value;queue_rebuild()
@export_range(.15,2,.05,"suffix:m") var rail_height = .35:
 set(value):rail_height=value;queue_rebuild()
@export var colour = Color("b8c0b0"):
 set(value):colour=value;queue_rebuild()
var queued=false
func _ready()->void:rebuild()
func queue_rebuild()->void:
 if not is_inside_tree() or queued:return
 queued=true;call_deferred("rebuild")
func rebuild()->void:
 queued=false
 if not is_inside_tree():return
 var old=get_node_or_null("Geometry")
 if old!=null:remove_child(old);old.queue_free()
 var geometry=Node3D.new();geometry.name="Geometry";add_child(geometry)
 var floor_piece=Node3D.new();floor_piece.set_script(load("res://shared/editable_piece.gd"));floor_piece.name="Deck"
 floor_piece.kind="Ground" if is_zero_approx(rise) else "Ramp"
 floor_piece.dimensions=Vector3(length,.35 if is_zero_approx(rise) else absf(rise),width)
 floor_piece.position=Vector3(length/2,minf(0,rise),0)
 if rise<0:floor_piece.rotation.y=PI
 geometry.add_child(floor_piece)
 var mat=StandardMaterial3D.new();mat.albedo_color=colour;mat.roughness=.9
 floor_piece.get_node("Visual").material_override=mat
 if not rails:return
 for side in [-1,1]:
  if (side<0 and not left_rail) or (side>0 and not right_rail):continue
  var rail=StaticBody3D.new();rail.name="LeftRail" if side<0 else "RightRail"
  rail.collision_layer=1;rail.collision_mask=0
  rail.position=Vector3(length/2,rise/2+rail_height/2,float(side)*(width/2+.025))
  rail.rotation.z=atan2(rise,length)
  var dimensions=Vector3(sqrt(length*length+rise*rise)+.1,rail_height,.16)
  var mesh=MeshInstance3D.new();var box=BoxMesh.new();box.size=dimensions;mesh.mesh=box
  var rail_mat=StandardMaterial3D.new();rail_mat.albedo_color=colour.darkened(.42);rail_mat.roughness=.9;mesh.material_override=rail_mat
  var collider=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=dimensions;collider.shape=shape
  rail.add_child(mesh);rail.add_child(collider);geometry.add_child(rail)
