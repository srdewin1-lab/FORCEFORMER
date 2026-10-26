@tool
extends Path3D
@export_range(24,600,24) var route_length = 168.0:
 set(value): route_length = value; queue_rebuild()
@export_range(4,32,.5) var narrow_width = 8.0:
 set(value): narrow_width = value; queue_rebuild()
@export_range(12,100,1) var vista_width = 56.0:
 set(value): vista_width = value; queue_rebuild()
@export_range(20,200,1) var opening_distance = 100.0:
 set(value): opening_distance = value; queue_rebuild()
@export_range(4,30,.5) var ridge_height = 13.0:
 set(value): ridge_height = value; queue_rebuild()
@export_range(5,40,1) var bank_width = 18.0:
 set(value): bank_width = value; queue_rebuild()
var rebuilding = false
var samples = PackedVector3Array()
func _ready() -> void:
 if curve != null and not curve.changed.is_connected(queue_rebuild): curve.changed.connect(queue_rebuild)
 rebuild()
func queue_rebuild() -> void:
 if not is_inside_tree() or rebuilding: return
 rebuilding = true
 call_deferred("rebuild")
func center_at(x: float) -> Vector3:
 if samples.is_empty(): return Vector3(x,-4,0)
 for i in range(1,samples.size()):
  if samples[i].x >= x:
   var span = samples[i].x-samples[i-1].x
   return samples[i-1].lerp(samples[i],clampf((x-samples[i-1].x)/maxf(.001,span),0,1))
 return samples[-1]
func width_at(x: float) -> float:
 return lerpf(narrow_width,vista_width,smoothstep(0,opening_distance,x))
func allows(point: Vector3) -> bool:
 return point.x >= -12 and point.x < route_length+12 and absf(point.z-center_at(point.x).z) < width_at(point.x)/2
func height_at(x: float,z: float) -> float:
 var center = center_at(x)
 var outside = maxf(0,absf(z-center.z)-width_at(x)/2)/bank_width
 return center.y+ridge_height*smoothstep(0,.8,outside)+sin(x*.075+z*.06)*1.4*smoothstep(0,.6,outside)
func rebuild() -> void:
 rebuilding = false
 if not is_inside_tree() or curve == null: return
 samples = curve.get_baked_points()
 var tool = SurfaceTool.new()
 tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 for x in range(-21,int(route_length)+33,3):
  var across = 24
  for i in range(across):
   for uv in [Vector2(0,i),Vector2(3,i),Vector2(0,i+1),Vector2(3,i),Vector2(3,i+1),Vector2(0,i+1)]:
    var xx = x+uv.x
    var center = center_at(xx)
    var z = center.z+(uv.y/across*2-1)*(width_at(xx)/2+bank_width)
    tool.add_vertex(Vector3(xx,height_at(xx,z),z))
 tool.generate_normals()
 var mesh = tool.commit()
 var sand = get_node_or_null("Sand")
 if sand == null:
  sand = MeshInstance3D.new()
  sand.name = "Sand"
  add_child(sand)
 var mat = StandardMaterial3D.new()
 mat.albedo_color = Color("9a9587")
 mat.roughness = .95
 sand.mesh = mesh
 sand.material_override = mat
 var body = get_node_or_null("Banks")
 if body == null:
  body = StaticBody3D.new()
  body.name = "Banks"
  body.collision_layer = 4
  body.collision_mask = 10
  add_child(body)
  var shape = CollisionShape3D.new()
  shape.name = "Shape"
  body.add_child(shape)
 body.get_node("Shape").shape = mesh.create_trimesh_shape()
 build_far_dunes(mat)

func scenery_height(x: float,z: float) -> float:
 var center = center_at(x)
 var end_distance = maxf(maxf(-21-x,x-(route_length+33)),0)
 var side_distance = maxf(0,absf(z-center.z)-width_at(x)/2-bank_width)
 var blend = smoothstep(0,90,maxf(end_distance,side_distance))
 var rolling = ridge_height*(.9+.2*sin(x*.017+z*.011))+2*sin(x*.009-z*.019)
 return height_at(x,z)+blend*rolling
func build_far_dunes(mat: Material) -> void:
 var tool = SurfaceTool.new()
 tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 var step = 12
 for x in range(-600,int(route_length)+600,step):
  for z in range(-600,600,step):
   # Leave the physical dune mesh unchanged within the building area.
   var inside = true
   for point in [Vector2(x,z),Vector2(x+step,z),Vector2(x,z+step),Vector2(x+step,z+step)]:
    if point.x < -18 or point.x > route_length+30 or absf(point.y-center_at(point.x).z)>width_at(point.x)/2+bank_width-3: inside=false
   if inside: continue
   for point in [Vector2(x,z),Vector2(x+step,z),Vector2(x,z+step),Vector2(x+step,z),Vector2(x+step,z+step),Vector2(x,z+step)]:
    tool.add_vertex(Vector3(point.x,scenery_height(point.x,point.y),point.y))
 tool.generate_normals()
 var far_dunes = get_node_or_null("FarDunes")
 if far_dunes==null:
  far_dunes=MeshInstance3D.new()
  far_dunes.name="FarDunes"
  add_child(far_dunes)
 far_dunes.mesh=tool.commit()
 far_dunes.material_override=mat
 far_dunes.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
