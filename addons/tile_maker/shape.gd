@tool
extends RefCounted
static func primitive(kind: String) -> Mesh:
 if kind == "Sphere":
  var sphere = SphereMesh.new();sphere.radius=.5;sphere.height=1; sphere.radial_segments=20;sphere.rings=12
  return sphere
 if kind == "Cylinder":
  var cylinder = CylinderMesh.new();cylinder.top_radius=.5;cylinder.bottom_radius=.5;cylinder.height=1;cylinder.radial_segments=20
  return cylinder
 if kind == "Ramp":
  var a=Vector3(-.5,-.5,-.5);var b=Vector3(.5,-.5,-.5);var c=Vector3(.5,.5,-.5)
  var d=Vector3(-.5,-.5,.5);var e=Vector3(.5,-.5,.5);var f=Vector3(.5,.5,.5)
  var vertices=[a,c,b,d,e,f,a,d,f,a,f,c,b,c,f,b,f,e,a,b,e,a,e,d]
  var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
  for index in range(0,vertices.size(),3):
   for v in [vertices[index],vertices[index+2],vertices[index+1]]:tool.add_vertex(v)
  # All primitives must use indices when appended into one mesh.
  tool.generate_normals();tool.index();return tool.commit()
 var box=BoxMesh.new();box.size=Vector3.ONE;return box
static func transform(part: Dictionary) -> Transform3D:
 return Transform3D((Basis(Vector3.UP,deg_to_rad(part.get("turn",0.0)))*Basis.from_scale(Vector3(part.size[0],part.size[1],part.size[2]))),Vector3(part.position[0],part.position[1],part.position[2]))
static func mesh(parts: Array,colour: Color) -> ArrayMesh:
 var tool=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 var material=StandardMaterial3D.new();material.albedo_color=colour;material.roughness=.9;material.cull_mode=BaseMaterial3D.CULL_DISABLED
 tool.set_material(material)
 for part in parts:tool.append_from(primitive(part.kind),0,transform(part))
 return tool.commit()
static func shapes(parts: Array) -> Array:
 var result=[]
 for part in parts:
  var points=PackedVector3Array()
  var basis=transform(part).basis
  for point in primitive(part.kind).get_faces():points.append(basis*point)
  var shape=ConvexPolygonShape3D.new();shape.points=points
  result.append(shape);result.append(Transform3D(Basis.IDENTITY,Vector3(part.position[0],part.position[1],part.position[2])))
 return result

# Recover only the released mixed-index bug. Compare the saved mesh with the
# non-ramp portion before rebuilding; never guess at hand-edited geometry.
static func same_faces(first: PackedVector3Array,second: PackedVector3Array) -> bool:
 if first.size()!=second.size():return false
 for index in range(first.size()):
  if not first[index].is_equal_approx(second[index]):return false
 return true
static func ramp_restorations(library: MeshLibrary) -> Dictionary:
 var result={}
 var saved=library.get_meta("custom_shapes",{})
 if not saved is Dictionary:return result
 for key in saved:
  if not str(key).is_valid_int():continue
  var id=int(key)
  if id not in library.get_item_list():continue
  var data=saved[key]
  if not data is Dictionary or not data.get("parts") is Array:continue
  var parts=data.parts
  if parts.is_empty() or parts.size()>256:continue
  var plain=[]
  var ramps=0
  var valid=true
  for part in parts:
   if not part is Dictionary or part.get("kind","") not in ["Box","Sphere","Cylinder","Ramp"]:valid=false;break
   for field in ["position","size"]:
    if not part.get(field) is Array or part[field].size()!=3:valid=false;break
    for number in part[field]:
     if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number))>100000:valid=false;break
   if not valid:break
   if float(part.size[0])<=0 or float(part.size[1])<=0 or float(part.size[2])<=0:valid=false;break
   var turn=part.get("turn",0.0)
   if not (turn is int or turn is float) or not is_finite(float(turn)):valid=false;break
   if part.kind=="Ramp":ramps+=1
   else:plain.append(part)
  if not valid or ramps==0 or plain.is_empty():continue
  var old=library.get_item_mesh(id)
  if old==null or old.get_surface_count()!=1:continue
  if not same_faces(old.get_faces(),mesh(plain,Color.WHITE).get_faces()):continue
  var restored=mesh(parts,Color.WHITE)
  # Keep the exact saved material, transform, collision shapes, name and ID.
  restored.surface_set_material(0,old.surface_get_material(0))
  result[id]=restored
 return result
