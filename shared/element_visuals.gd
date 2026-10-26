extends RefCounted
# Own primitive meshes; rendering changes neither the compiler nor the authored forces.
static func drop_mesh() -> ArrayMesh:
 var tool = SurfaceTool.new()
 tool.begin(Mesh.PRIMITIVE_TRIANGLES)
 var heights = [-.25,-.19,-.07,.1,.42]
 var radii = [0.0,.09,.115,.065,0.0]
 for ring in range(heights.size()-1):
  for side in range(10):
   var a = TAU*side/10
   var b = TAU*(side+1)/10
   var p = Vector3(cos(a)*radii[ring],heights[ring],sin(a)*radii[ring])
   var q = Vector3(cos(b)*radii[ring],heights[ring],sin(b)*radii[ring])
   var r = Vector3(cos(a)*radii[ring+1],heights[ring+1],sin(a)*radii[ring+1])
   var s = Vector3(cos(b)*radii[ring+1],heights[ring+1],sin(b)*radii[ring+1])
   for point in [p,q,r,q,s,r]: tool.add_vertex(point)
 tool.generate_normals()
 return tool.commit()
static func halo(colour: Color,size: float=2.5) -> MeshInstance3D:
 var node = MeshInstance3D.new()
 node.name = "Glow"
 var quad = QuadMesh.new()
 quad.size = Vector2.ONE*size
 node.mesh = quad
 var mat = ShaderMaterial.new()
 mat.shader = load("res://shared/soft_glow.gdshader")
 mat.set_shader_parameter("glow_colour",colour)
 node.material_override = mat
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 return node
static func decorate(body) -> void:
 var visual = body.get_node("Sphere")
 var mat = visual.material_override
 match str(body.data.kind):
  "things":
   mat.albedo_color = Color("e2ddcb")
   mat.emission = Color("ffdb92")
   body.data.brightness = maxf(float(body.data.brightness),.7)
   body.add_child(halo(Color("ffdc9b"),2.5))
  "raindrops":
   visual.mesh = drop_mesh()
   mat.albedo_color = Color("83bed0")
   mat.emission = Color("6b9eb5")
   body.data.brightness = .16
   mat.roughness = .3
  "ash":
   var flake = BoxMesh.new()
   flake.size = Vector3(.3,.025,.19)
   visual.mesh = flake
   mat.albedo_color = Color("8d8881")
   body.data.brightness = .025
  "snowflakes":
   var tool = SurfaceTool.new()
   tool.begin(Mesh.PRIMITIVE_TRIANGLES)
   for i in range(3):
    var branch = BoxMesh.new()
    branch.size = Vector3(.43,.025,.035)
    tool.append_from(branch,0,Transform3D(Basis(Vector3.UP,PI*i/3),Vector3.ZERO))
   visual.mesh = tool.commit()
   mat.albedo_color = Color("e1e7e8")
   body.data.brightness = .08
  "seeds":
   var seed = SphereMesh.new()
   seed.radius = .1
   seed.height = .37
   seed.radial_segments = 8
   seed.rings = 4
   visual.mesh = seed
   mat.albedo_color = Color("9e8d64")
  "meteor":
   var stone = SphereMesh.new()
   stone.radius = .23
   stone.height = .46
   stone.radial_segments = 7
   stone.rings = 3
   visual.mesh = stone
   mat.albedo_color = Color("756759")
   body.add_child(halo(Color("ff8f42"),2.8))
static func update(body) -> void:
 var visual = body.get_node("Sphere")
 var kind = str(body.data.kind)
 var scale_factor = float(body.data.scale)
 if kind == "raindrops":
  if body.landed:
   visual.basis = Basis.IDENTITY.scaled(Vector3(1.7,.15,1.7)*scale_factor)
  elif body.linear_velocity.length()>.2:
   visual.basis = Basis(Quaternion(Vector3.UP,-body.linear_velocity.normalized())).scaled(Vector3.ONE*scale_factor)
 elif kind in ["ash","snowflakes","seeds"]:
  var time = body.runtime.elapsed+float(body.data.id)
  visual.rotation = Vector3(sin(time*2)*.4,time*.7,cos(time*1.3)*.35)
 if body.has_node("Glow"):
  var energy = float(visual.material_override.emission_energy_multiplier)
  body.get_node("Glow").visible = body.data.visibility>0 and energy>.001
  body.get_node("Glow").material_override.set_shader_parameter("strength",minf(1.2,energy)*.65)
