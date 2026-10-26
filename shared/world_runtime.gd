extends Node3D
const Compiler = preload("res://shared/compiler.gd")
const Body = preload("res://shared/body.gd")
var compiler = Compiler.new()
var hour = 0.0
var elapsed = 0.0
var days = 0
var clock_elapsed = 0.0
var partial_support: Array = []
var preview_seconds = 1200.0
var next_id = 1
var rain_accumulator = 0.0
var bonds: Dictionary = {}
var contacts: Dictionary = {}
var current: Dictionary = {}
var bodies: Array = []
var errors: Array = []
var strike_count = 0
var contact_exclusions: Dictionary = {}
func spawn(kind: String,pos: Vector3,velocity: Vector3,weather: bool,index: int=0):
 var n = compiler.numbers
 if bodies.size()>=n.body.cap: return null
 var material = n.bench.precipitation.get(kind,n.bench.precipitation.things)
 var body = Body.new()
 body.name = "Witness" if not weather and index == 0 else "Thing%d" % next_id
 body.runtime = self
 body.data = {"id":next_id,"kind":kind,"mass":material.mass if weather else n.body.mass.heavy if index%2 == 0 else n.body.mass.light,"scale":material.scale*(.8+compiler.noise(next_id,6)*.4) if weather else lerp(n.body.initial_scale_range[0],n.body.initial_scale_range[1],compiler.noise(index+1,11)),"sonority":0,"visibility":1,"brightness":n.light.coal_energy if kind == "things" else 0,"mobility":1,"state":"solid","shape":"round","weather":weather}
 if weather:
  body.data.ground_lifetime = material.ground_lifetime
  body.data.material_damp = material.damp
 next_id += 1
 var mesh = MeshInstance3D.new()
 mesh.name = "Sphere"
 var sphere = SphereMesh.new()
 sphere.radius = n.body.radius
 sphere.height = n.body.radius*2
 sphere.radial_segments = 16
 sphere.rings = 8
 mesh.mesh = sphere
 if kind == "books":
  var book = BoxMesh.new()
  book.size = Vector3(.45,.12,.32)
  mesh.mesh = book
 if kind == "tokens":
  var token = CylinderMesh.new()
  token.top_radius = .25
  token.bottom_radius = .25
  token.height = .07
  token.radial_segments = 16
  token.rings = 1
  mesh.mesh = token
 var mat = StandardMaterial3D.new()
 mat.albedo_color = Color(.9,.65,.23) if index == 0 and not weather else Color(.68,.72,.76) if body.data.mass<2 else Color(.28,.3,.34)
 if kind == "ash": mat.albedo_color = Color(.16,.14,.13)
 if kind == "raindrops": mat.albedo_color = Color(.35,.55,.72)
 if kind == "snowflakes": mat.albedo_color = Color(.85,.9,.95)
 if kind == "tokens": mat.albedo_color = Color(.8,.62,.2)
 if kind == "seeds": mat.albedo_color = Color(.38,.33,.22)
 mat.emission_enabled = true
 mat.emission = Color(1,.32,.08) if kind == "meteor" else mat.albedo_color
 mat.emission_energy_multiplier = body.data.brightness
 mesh.material_override = mat
 body.add_child(mesh)
 var shape = CollisionShape3D.new()
 shape.name = "Shape"
 shape.shape = SphereShape3D.new()
 body.add_child(shape)
 preload("res://shared/element_visuals.gd").decorate(body)
 var phys = PhysicsMaterial.new()
 phys.bounce = n.bench.bounce
 body.physics_material_override = phys
 var sound = AudioStreamPlayer3D.new()
 sound.name = "Strike"
 sound.stream = load("res://sounds/strike.wav")
 sound.max_distance = 120
 body.add_child(sound)
 var ring = MeshInstance3D.new()
 ring.name = "Vibration"
 var torus = TorusMesh.new()
 torus.inner_radius = .3
 torus.outer_radius = .33
 torus.rings = 24
 torus.ring_segments = 6
 ring.mesh = torus
 var ring_mat = StandardMaterial3D.new()
 ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 ring_mat.albedo_color = Color(.9,.7,.3)
 ring.material_override = ring_mat
 ring.hide()
 body.add_child(ring)
 if not weather and index<int(n.light.persistent_light_cap):
  var coal = OmniLight3D.new()
  # Join the plot light budget before becoming a real light. Its mesh still glows.
  coal.visible = not has_method("update_local_lights")
  coal.omni_range = n.light.coal_reach_metres
  coal.light_energy = n.light.coal_energy
  coal.light_color = Color(.7,.73,.83)
  body.add_child(coal)
 $Bodies.add_child(body)
 body.position = pos
 body.linear_velocity = velocity
 body.configure_scale()
 bodies.append(body)
 return body
func release_bonds(body) -> void:
 for key in bonds.keys():
  if bonds[key].has(body): bonds.erase(key)
func remove_body(body) -> void:
 release_bonds(body)
 bodies.erase(body)
 body.queue_free()
func nearby_pairs(items: Array) -> Array:
 var width = .001
 for body in items: width = max(width,compiler.numbers.body.radius*body.data.scale*2)
 var cells = {}
 var locations = []
 for i in range(items.size()):
  var v = items[i].position/width
  var cell = Vector3i(floor(v.x),floor(v.y),floor(v.z))
  locations.append(cell)
  if not cells.has(cell): cells[cell] = []
  cells[cell].append(i)
 var pairs = []
 for i in range(items.size()):
  var neighbours = []
  for x in range(-1,2):
   for y in range(-1,2):
    for z in range(-1,2):
     for j in cells.get(locations[i]+Vector3i(x,y,z),[]):
      if j>i: neighbours.append(j)
  neighbours.sort()
  for j in neighbours: pairs.append(Vector2i(i,j))
 return pairs
func _physics_process(delta: float) -> void:
 if compiler.world.is_empty(): return
 elapsed += delta
 var snapshots = []
 for body in bodies: snapshots.append(body.snapshot())
 var ctx = {"bodies":snapshots,"listener":$Wheel.position,"right":Vector3.RIGHT,"forward":Vector3.FORWARD,"time":elapsed,"entries":compiler.entries(hour)}
 current = compiler.parameters(hour,{},ctx)
 if current.clock.running:
  clock_elapsed += delta
  var raw = hour+delta*24/preview_seconds*current.clock.sign*compiler.clock_rate(current.clock.pattern,hour,days)*compiler.clock_factor(current.clock.path,clock_elapsed,preview_seconds)*current.clock.get("pace",1.0)
  if raw>=24: days += 1
  if raw<0: days -= 1
  hour = fposmod(raw,24)
 ctx.entries = compiler.entries(hour)
 current = compiler.parameters(hour,{},ctx)
 for i in range(bodies.size()-1,-1,-1):
  if i>=bodies.size(): continue
  var body = bodies[i]
  body.prepare(compiler.parameters(hour,body.snapshot(),ctx),delta)
 # Native Godot handles sculpted terrain; pair impulses use the shared mass/response rule.
 var new_contacts = {}
 var pair_bodies = bodies.duplicate()
 for pair_indices in nearby_pairs(pair_bodies):
  var a = pair_bodies[pair_indices.x]
  var b = pair_bodies[pair_indices.y]
  if a.is_queued_for_deletion() or b.is_queued_for_deletion(): continue
  if (a == $Wheel or b == $Wheel) and (a.data.get("visual_only",false) or b.data.get("visual_only",false)): continue
  var offset = b.position-a.position
  var distance = offset.length()
  var radius = compiler.numbers.body.radius*(a.data.scale+b.data.scale)
  if distance>=radius or a.parameters.is_empty() or b.parameters.is_empty(): continue
  var pair = str(a.data.id)+":"+str(b.data.id)
  new_contacts[pair] = true
  var meeting = a.parameters.body.meeting
  if not contacts.has(pair):
   var speed = (a.linear_velocity-b.linear_velocity).length()
   strike(a,speed)
   strike(b,speed)
   meet(a,b)
  if a.is_queued_for_deletion() or b.is_queued_for_deletion() or meeting in ["overlap","mix","fuse"]: continue
  var normal = offset/distance if distance>.000001 else Vector3.RIGHT
  var ia = a.parameters.body.response_factor/a.data.mass if a.parameters.body.contact_enabled else 0.0
  var ib = b.parameters.body.response_factor/b.data.mass if b.parameters.body.contact_enabled else 0.0
  var total = ia+ib
  if total<=0: continue
  a.position -= normal*(radius-distance)*ia/total
  b.position += normal*(radius-distance)*ib/total
  var relative = (b.linear_velocity-a.linear_velocity).dot(normal)
  if relative<0:
   var impulse = -(1+(0 if meeting == "attract" else a.parameters.body.rebound))*relative/total
   a.linear_velocity -= normal*impulse*ia
   b.linear_velocity += normal*impulse*ib
 for key in bonds.keys():
  var a = bonds[key][0]
  var b = bonds[key][1]
  if not is_instance_valid(a) or not is_instance_valid(b) or a.parameters.body.meeting != "attract" or b.parameters.body.meeting != "attract":
   bonds.erase(key)
   continue
  var offset = b.position-a.position
  var target = compiler.numbers.body.radius*(a.data.scale+b.data.scale)
  var normal = offset.normalized() if offset.length()>.00001 else Vector3.RIGHT
  var total = a.data.mass+b.data.mass
  a.position += normal*(offset.length()-target)*b.data.mass/total
  b.position -= normal*(offset.length()-target)*a.data.mass/total
  var relative = (b.linear_velocity-a.linear_velocity).dot(normal)
  a.linear_velocity += normal*relative*b.data.mass/total
  b.linear_velocity -= normal*relative*a.data.mass/total
  new_contacts[key] = true
 contacts = new_contacts
 call("emit_weather",delta)
 update_sky()
 call("update_clouds")
 update_emitters()

func strike(body,speed: float) -> void:
 if speed<compiler.numbers.bench.strike_threshold: return
 strike_count += 1
 body.data.sonority = clamp(20*log(max(.001,speed/5))/log(10),-80,12)
 body.hanging = false
 body.ring_age = 0
 var sound = body.get_node("Strike")
 sound.volume_db = clamp(body.data.sonority-16+linear_to_db(max(.001,body.parameters.sound.get("strength",1.0))),-80,0)
 sound.pitch_scale = compiler.numbers.bench.click_heavy_hz/compiler.numbers.bench.click_light_hz if body.data.mass>=2 else 1
 if body.parameters.sound.propagates and body.parameters.sound.get("strength",1.0)>0 and DisplayServer.get_name() != "headless": sound.play()
func meet(a,b) -> void:
 if a.is_queued_for_deletion() or b.is_queued_for_deletion(): return
 var key = "%d:%d" % [min(a.data.id,b.data.id),max(a.data.id,b.data.id)]
 var kind = a.parameters.body.meeting
 if kind == "random":
  var choices = []
  for option in compiler.families.meeting:
   if option.status == "honoured" and option.key != "random": choices.append(option.key)
  kind = choices[int(compiler.noise(a.data.id,strike_count)*choices.size())]
 var normal = (b.position-a.position).normalized()
 if kind == "fuse":
  var total = a.data.mass+b.data.mass
  a.linear_velocity = (a.linear_velocity*a.data.mass+b.linear_velocity*b.data.mass)/total
  a.data.mass = clamp(total,compiler.numbers.body.mass_limits[0],compiler.numbers.body.mass_limits[1])
  a.data.scale = clamp(pow(pow(a.data.scale,3)+pow(b.data.scale,3),1.0/3),compiler.numbers.body.scale_limits[0],compiler.numbers.body.scale_limits[1])
  remove_body(b)
 if kind == "attract": bonds[key] = [a,b]
 if kind == "mix":
  a.linear_velocity -= normal*.2
  b.linear_velocity += normal*.2
 if kind == "stack":
  a.linear_velocity = Vector3.ZERO
  b.linear_velocity = Vector3.ZERO
 if kind == "repel":
  var kick = max(1,(a.linear_velocity-b.linear_velocity).length())
  a.linear_velocity -= normal*kick
  b.linear_velocity += normal*kick
 if kind in ["grow","shrink"]:
  for body in [a,b]: body.data.scale = clamp(body.data.scale*(compiler.numbers.operations.growth if kind == "grow" else compiler.numbers.operations.shrink),compiler.numbers.body.scale_limits[0],compiler.numbers.body.scale_limits[1])
func update_sky() -> void:
 var light = current.light
 var direction = light.vector
 if direction.length()>.01: $Sun.look_at($Sun.global_position-direction,Vector3.FORWARD if abs(direction.y)>.99 else Vector3.UP)
 $Sun.light_energy = .08*light.energy*smoothstep(0,.12,direction.y)
 $Sun.light_color = Color(light.colour[0],light.colour[1],light.colour[2])
 $Sun.light_angular_distance = .5*light.disc_scale
 var sky = $Overview.environment.sky.sky_material
 sky.set_shader_parameter("sun_direction",direction)
 sky.set_shader_parameter("day_energy",light.energy)
 sky.set_shader_parameter("disc_visible",light.disc_visible)
 sky.set_shader_parameter("disc_scale",float(light.disc_scale))
 sky.set_shader_parameter("predawn",float(light.predawn))
 var rise = {"right":Vector3.RIGHT,"forward":Vector3.FORWARD,"behind":Vector3.BACK}.get(light.next_location,Vector3.LEFT)
 sky.set_shader_parameter("rise_direction",rise)
 var rgb = compiler.numbers.light.night_colour
 sky.set_shader_parameter("night_colour",Vector3(rgb[0],rgb[1],rgb[2])*.015)
 sky.set_shader_parameter("day_colour",Vector3(light.colour[0]*.35,light.colour[1]*.4,light.colour[2]*.5))
 $Overview.environment.ambient_light_energy = .001+maxf(0,direction.y)*light.energy*.05

func update_emitters() -> void:
 # Student positional players stay on their own authored streams; atmosphere is separate.
 for emitter in $Emitters.get_children():
  if not emitter is AudioStreamPlayer3D: continue
  if not emitter.has_meta("authored_volume"):
   emitter.set_meta("authored_volume",emitter.volume_db)
  emitter.volume_db = clampf(float(emitter.get_meta("authored_volume"))+linear_to_db(maxf(.001,float(current.sound.get("strength",1)))), -80,12) if current.sound.propagates and current.sound.get("strength",1.0)>0 else -80.0
