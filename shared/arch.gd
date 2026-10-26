@tool
extends Node3D
# A half-ellipse in the local YZ plane; local +X passes through it.
@export_range(1,24,.1,"suffix:m") var span = 8.6:
 set(value):span=maxf(1,value);queue_rebuild()
@export_range(1,16,.1,"suffix:m") var height = 4.3:
 set(value):height=maxf(1,value);queue_rebuild()
@export_range(.1,2,.05,"suffix:m") var thickness = .42:
 set(value):thickness=maxf(.1,value);queue_rebuild()
@export_range(.1,4,.05,"suffix:m") var depth = .5:
 set(value):depth=maxf(.1,value);queue_rebuild()
@export_range(6,40,1) var segments = 20:
 set(value):segments=clampi(value,6,40);queue_rebuild()
@export var solid = true:
 set(value):solid=value;queue_rebuild()
@export var colour = Color("9da9a4"):
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
 var mat=StandardMaterial3D.new();mat.albedo_color=colour;mat.roughness=.85
 for i in range(segments):
  var a=float(i)/segments*PI;var b=float(i+1)/segments*PI
  var p=Vector3(0,sin(a)*height,cos(a)*span/2)
  var q=Vector3(0,sin(b)*height,cos(b)*span/2)
  var rib=StaticBody3D.new() if solid else Node3D.new();rib.name="Rib%02d"%i
  rib.position=(p+q)/2;rib.rotation.x=atan2(q.z-p.z,q.y-p.y)
  if solid:rib.collision_layer=1;rib.collision_mask=0
  var size=Vector3(depth,p.distance_to(q)+.04,thickness)
  var mesh=MeshInstance3D.new();var box=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.material_override=mat;rib.add_child(mesh)
  if solid:
   var collider=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;collider.shape=shape;rib.add_child(collider)
  geometry.add_child(rib)
