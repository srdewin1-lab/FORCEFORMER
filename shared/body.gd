extends RigidBody3D
var runtime
var data: Dictionary = {}
var parameters: Dictionary = {}
var ground_age = 0.0
var last_up = 0.0
var risen = 0.0
var hanging = false
var carried = false
var landed = false
var previous_velocity = Vector3.ZERO
var ring_age = 2.0
var last_nudge = -1
var steady_speed = -1.0
var applied_scale = -1.0
var applied_mass = -1.0
func _ready() -> void:
 gravity_scale = 0
 contact_monitor = true
 max_contacts_reported = 8
 collision_layer = 2
 collision_mask = 1
 continuous_cd = true
 can_sleep = false
 body_entered.connect(_contact)
func snapshot() -> Dictionary:
 var out = data.duplicate()
 out.position = runtime.to_local(global_position)
 out.velocity = linear_velocity
 return out
func configure_scale() -> void:
 var r = runtime.compiler.numbers.body.radius*data.scale
 if applied_scale != data.scale:
  $Shape.shape.radius = r
  $Sphere.scale = Vector3.ONE*data.scale
  applied_scale = data.scale
 if applied_mass != data.mass:
  mass = max(.1,float(data.mass))
  applied_mass = data.mass
func prepare(p: Dictionary,delta: float) -> void:
 parameters = p
 var n = runtime.compiler.numbers
 var gravity = p.gravity.vector*p.gravity.strength if p.gravity.enabled else Vector3.ZERO
 var acceleration = Vector3.ZERO if hanging or carried else gravity
 if p.weather.wind_enabled and not hanging:
  acceleration += runtime.compiler.vector_path(p.weather.wind_path,Vector3.RIGHT,runtime.elapsed)*(n.bench.wind_ground_gain if landed else n.bench.wind_air_gain)/n.bench.wind_reference_pixels_per_metre*p.body.response_factor/data.mass*p.weather.get("wind_strength",1.0)
 if p.body.random_enabled and int(runtime.elapsed*2) != last_nudge:
  last_nudge = int(runtime.elapsed*2)
  linear_velocity += Vector3((runtime.compiler.noise(int(data.id),last_nudge)-.5)*2,runtime.compiler.noise(int(data.id)+1,last_nudge),(runtime.compiler.noise(int(data.id)+2,last_nudge)-.5)*2)
 linear_velocity += acceleration*delta
 if p.body.rest == "stay" or data.mobility<=0: linear_velocity = Vector3.ZERO
 if p.body.rest == "rise": linear_velocity.y += n.gravity.strength*delta
 if p.body.rest == "fall": linear_velocity.y -= n.gravity.strength*delta
 if p.body.rest == "move" and linear_velocity.length()<.1: linear_velocity = Vector3.RIGHT
 if p.body.rest in ["expand","contract"]: data.scale = clamp(data.scale*pow(n.operations.growth if p.body.rest == "expand" else n.operations.shrink,delta),n.body.scale_limits[0],n.body.scale_limits[1])
 for op in p.body.operations:
  var sign_value = {"consistent":0,"increasing":1,"decreasing":-1,"random":(runtime.compiler.noise(int(data.id),int(runtime.elapsed))-.5)*2}.get(op.pattern,0)
  if op.quality == "speed":
   if op.pattern == "consistent":
    if steady_speed<0: steady_speed = max(1,linear_velocity.length())
    linear_velocity = (linear_velocity.normalized() if linear_velocity.length()>.001 else p.gravity.vector)*steady_speed
   else: linear_velocity = linear_velocity.normalized()*clamp(linear_velocity.length()*exp(sign_value*n.operations.speed_rate*delta),0,100)
  else:
   var property = {"weight":"mass","size":"scale","sonority":"sonority","brightness":"brightness","visibility":"visibility","mobility":"mobility"}.get(op.quality,"")
   if property.is_empty(): continue
   var value = float(data.get(property,0))
   var limits = {"mass":n.body.mass_limits,"scale":n.body.scale_limits,"sonority":[-80,12],"brightness":[0,n.light.bright_energy],"visibility":[0,1],"mobility":[0,1]}[property]
   if property in ["mass","scale"]: value *= pow(n.operations.growth if sign_value>0 else n.operations.shrink,abs(sign_value)*delta)
   else: value += sign_value*delta*(n.operations.sound_db_rate if property == "sonority" else n.operations.light_rate if property == "brightness" else n.operations.speed_rate)
   data[property] = clamp(value,limits[0],limits[1])
 var up = -gravity.normalized() if gravity.length() > .001 else Vector3.UP
 var up_speed = linear_velocity.dot(up)
 if last_up>0 and up_speed<=0 and risen>=n.body.radius*data.scale and not landed:
  if p.body.apex_verb == "stay":
   hanging = true
   linear_velocity = Vector3.ZERO
  if p.body.apex_verb == "move":
   carried = true
   linear_velocity = up*max(.2,last_up)
  if p.body.apex_verb == "rise": linear_velocity = up*2
 if up_speed>0: risen += up_speed*delta
 last_up = up_speed
 linear_damp = data.get("material_damp",0.0)+p.body.get("motion_resistance",n.body.damp)
 physics_material_override.bounce = p.body.get("rebound",n.bench.bounce)
 configure_scale()
 var floor_y = runtime.ground_at(global_position)+n.body.radius*data.scale
 landed = global_position.y<=floor_y+.12
 if landed:
  risen = 0
  carried = false
  if data.get("weather",false):
   ground_age += delta
   if ground_age>=data.ground_lifetime:
    runtime.remove_body(self)
    return
 if position.y>n.world.height-n.body.radius*data.scale:
  position.y = n.world.height-n.body.radius*data.scale
  linear_velocity.y = min(0,linear_velocity.y)
 runtime.wrap_body(self)
 previous_velocity = linear_velocity
 $Sphere.visible = data.visibility>0
 var mat = $Sphere.material_override
 mat.emission_energy_multiplier = data.brightness
 if data.kind == "meteor": mat.emission_energy_multiplier = clamp((linear_velocity.length()-n.bench.meteor_glow_start)/n.bench.meteor_glow_range,0,1)*2
 preload("res://shared/element_visuals.gd").update(self)
 ring_age += delta
 $Vibration.visible = p.sound.visible and ring_age<1.5
 $Vibration.scale = Vector3.ONE*(1+ring_age*8)
func _contact(other: Node) -> void:
 if runtime == null or parameters.is_empty(): return
 var speed = (previous_velocity-other.previous_velocity).length() if other.get_script() == get_script() else abs(previous_velocity.y)
 runtime.strike(self,speed)
 if other.get_script() == get_script(): runtime.meet(self,other)
