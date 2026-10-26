@tool
extends Node3D
@export_enum("Ground","Ramp","Wall","Tree") var kind = "Ramp":
 set(value): kind = value; queue_rebuild()
@export var dimensions = Vector3(4,1,3):
 set(value): dimensions = Vector3(maxf(.1,value.x),maxf(.1,value.y),maxf(.1,value.z)); queue_rebuild()
var queued = false
func _ready() -> void: rebuild()
func queue_rebuild() -> void:
 if not is_inside_tree() or queued: return
 queued = true
 call_deferred("rebuild")
func rebuild() -> void:
 queued = false
 if not is_inside_tree(): return
 var visual = get_node_or_null("Visual")
 if visual == null:
  visual = MeshInstance3D.new()
  visual.name = "Visual"
  add_child(visual)
 var body = get_node_or_null("Solid")
 if body == null:
  body = StaticBody3D.new()
  body.name = "Solid"
  body.collision_layer = 1
  add_child(body)
  var shape = CollisionShape3D.new()
  shape.name = "Shape"
  body.add_child(shape)
 var collider = body.get_node("Shape")
 var mat = StandardMaterial3D.new()
 mat.albedo_color = Color("c5c7ab") if kind == "Ground" else Color("d0c2a7") if kind == "Ramp" else Color("92978d") if kind == "Wall" else Color("809370")
 mat.roughness = .9
 visual.position = Vector3.ZERO
 collider.position = Vector3.ZERO
 if kind == "Ramp":
  var a = Vector3(-dimensions.x/2,0,-dimensions.z/2)
  var b = Vector3(dimensions.x/2,0,-dimensions.z/2)
  var c = Vector3(dimensions.x/2,dimensions.y,-dimensions.z/2)
  var d = Vector3(-dimensions.x/2,0,dimensions.z/2)
  var e = Vector3(dimensions.x/2,0,dimensions.z/2)
  var f = Vector3(dimensions.x/2,dimensions.y,dimensions.z/2)
  var tool = SurfaceTool.new()
  tool.begin(Mesh.PRIMITIVE_TRIANGLES)
  tool.set_smooth_group(-1)
  var triangles = [a,c,b,d,e,f,a,d,f,a,f,c,b,c,f,b,f,e,a,b,e,a,e,d]
  for index in range(0,triangles.size(),3):
   for v in [triangles[index],triangles[index+2],triangles[index+1]]: tool.add_vertex(v)
  tool.generate_normals()
  visual.mesh = tool.commit()
  var shape = ConvexPolygonShape3D.new()
  shape.points = PackedVector3Array([a,b,c,d,e,f])
  collider.shape = shape
 elif kind == "Tree":
  var tool = SurfaceTool.new()
  tool.begin(Mesh.PRIMITIVE_TRIANGLES)
  var trunk = CylinderMesh.new()
  trunk.top_radius = dimensions.x*.06
  trunk.bottom_radius = dimensions.x*.09
  trunk.height = dimensions.y*.5
  tool.append_from(trunk,0,Transform3D(Basis.IDENTITY,Vector3(0,dimensions.y*.25,0)))
  var crown = SphereMesh.new()
  crown.radius = .5
  crown.height = 1
  var basis = Basis.IDENTITY.scaled(Vector3(dimensions.x,dimensions.y*.6,dimensions.z))
  tool.append_from(crown,0,Transform3D(basis,Vector3(0,dimensions.y*.7,0)))
  visual.mesh = tool.commit()
  var shape = CylinderShape3D.new()
  shape.radius = dimensions.x*.09
  shape.height = dimensions.y*.5
  collider.shape = shape
  collider.position.y = dimensions.y*.25
 else:
  var box = BoxMesh.new()
  box.size = dimensions
  visual.mesh = box
  var shape = BoxShape3D.new()
  shape.size = dimensions
  collider.shape = shape
  visual.position.y = -dimensions.y/2 if kind == "Ground" else dimensions.y/2
  collider.position = visual.position
 visual.material_override = mat
