extends "res://shared/body.gd"
const RADIUS = .32
const MAX_SPEED = 3.0
const GROUND_STEERING_FORCE = 4.0
const AIR_STEERING_FORCE = .5
## On: steady speed, braking and surface grip. Off: physical steering, momentum
## and the condition's gravity, wind, resistance and rebound, without a speed cap.
@export var assisted = true
# Storage alias keeps legacy scenes readable. The saved scene resolver below
# handles old inherited nodes that reapply script defaults during instantiation.
@export_storage var ground_adhesion: bool = true:
 get: return assisted
 set(value): assisted = value
var control_override = Vector2.ZERO
var sinking = false
var sink_age = 0.0
var water_level = 0
var pending_reset = false
var reset_position = Vector3.ZERO
var supported = false
var support_normal = Vector3.UP
var air_age = 0.0
func restore_saved_assistance() -> void:
 # Walk from the Wheel scene to its containing plot; outer saved overrides win.
 var scene_root: Node = self
 while scene_root != null:
  if not scene_root.scene_file_path.is_empty():
   var scene = load(scene_root.scene_file_path) as PackedScene
   if scene != null:
    var state = scene.get_state()
    var path = scene_root.get_path_to(self)
    for node_index in range(state.get_node_count()):
     if state.get_node_path(node_index) != path: continue
     var current_choice = null
     var legacy_choice = null
     for property_index in range(state.get_node_property_count(node_index)):
      var property_name = state.get_node_property_name(node_index,property_index)
      if property_name == "assisted": current_choice = state.get_node_property_value(node_index,property_index)
      elif property_name == "ground_adhesion": legacy_choice = state.get_node_property_value(node_index,property_index)
     if current_choice != null: assisted = bool(current_choice)
     elif legacy_choice != null: assisted = bool(legacy_choice)
  scene_root = scene_root.get_parent()
func _ready() -> void:
 restore_saved_assistance()
 super._ready()
 collision_layer = 2
 collision_mask = 5
 angular_damp = .8
func configure_scale() -> void:
 $Shape.shape.radius = RADIUS
 mass = maxf(.1,float(data.get("mass",1)))
func snapshot() -> Dictionary:
 var out = super.snapshot()
 out.scale = RADIUS/runtime.compiler.numbers.body.radius
 return out
func prepare(p: Dictionary,delta: float) -> void:
 # Both modes use the imported forces. Only Assisted adds a movement controller.
 # Generic Things additionally carry the full rest/apex laws.
 parameters = p
 var gravity = p.gravity.vector*p.gravity.strength if p.gravity.enabled else Vector3.ZERO
 gravity_scale = -gravity.y/9.8 if absf(gravity.x)+absf(gravity.z)<.0001 else 0.0
 constant_force = gravity*mass if absf(gravity.x)+absf(gravity.z)>=.0001 else Vector3.ZERO
 if p.weather.wind_enabled:
  var n = runtime.compiler.numbers
  constant_force += runtime.compiler.vector_path(p.weather.wind_path,Vector3.RIGHT,runtime.elapsed)*(n.bench.wind_ground_gain if supported else n.bench.wind_air_gain)/n.bench.wind_reference_pixels_per_metre*p.body.response_factor*p.weather.wind_strength
 linear_damp = p.body.motion_resistance
 angular_damp = .8 if assisted else p.body.motion_resistance
 linear_damp_mode = RigidBody3D.DAMP_MODE_COMBINE if assisted else RigidBody3D.DAMP_MODE_REPLACE
 angular_damp_mode = RigidBody3D.DAMP_MODE_COMBINE if assisted else RigidBody3D.DAMP_MODE_REPLACE
 physics_material_override.bounce = p.body.rebound
 previous_velocity = linear_velocity
 landed = supported
 hanging = false
 carried = false
 ring_age += delta
 $Vibration.visible = p.sound.visible and ring_age<1.5 and not runtime.first_person
 $Vibration.scale = Vector3.ONE*(1+ring_age*8)
 if supported: air_age = 0
 else: air_age += delta
 # Unassisted steering adds force and leaves launch/fall velocity intact.
 # Sand contact, water, map bounds and the void floor recover; R returns to A.
func _contact(other: Node) -> void:
 # The dunes show the conditions; they are not part of the playable route.
 # Wait for a real collision so the Wheel can complete a flight off a ramp.
 if runtime != null and other == runtime.get_node_or_null("Dunes/Banks"):
  if runtime.active_plot and not pending_reset: runtime.recover_wheel()
  return
 super._contact(other)
func reset_to(point: Vector3) -> void:
 reset_position = point
 pending_reset = true
 sinking = false
 sink_age = 0
 hanging = false
 carried = false
 supported = false
 air_age = 0
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
 if pending_reset:
  state.transform = Transform3D(Basis.IDENTITY,reset_position)
  state.linear_velocity = Vector3.ZERO
  state.angular_velocity = Vector3.ZERO
  pending_reset = false
 if runtime == null or not runtime.active_plot or parameters.is_empty(): return
 var axis = control_override
 if axis.is_zero_approx():
  axis = Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_UP)))
 if axis.length()>1: axis = axis.normalized()
 var direction = Vector3(-axis.y,0,axis.x)
 var support = runtime.wheel_support(state.transform.origin)
 supported = not support.is_empty() and support.normal.dot(Vector3.UP)>.5 and not sinking
 if supported:
  support_normal = support.normal
  var tangent = direction.slide(support_normal).normalized()
  if assisted:
   var normal_speed = state.linear_velocity.dot(support_normal)
   # Cancel only separation from an existing surface, not the world's gravity on things.
   if normal_speed>0: state.linear_velocity -= support_normal*normal_speed
   var outward = (Vector3(0,-gravity_scale*9.8,0)+constant_force/mass).dot(support_normal)
   state.apply_central_force(-support_normal*mass*(4.0+maxf(0,outward)))
   var plane_velocity = state.linear_velocity.slide(support_normal)
   var target_velocity = tangent*MAX_SPEED
   if not direction.is_zero_approx():
    var barrier = runtime.wheel_barrier(state.transform.origin,direction)
    if not barrier.is_empty(): target_velocity = Vector3.ZERO
   state.apply_central_force((target_velocity-plane_velocity)*mass*10.0)
  elif not direction.is_zero_approx():
   state.apply_central_force(tangent*GROUND_STEERING_FORCE)
 else:
  if not direction.is_zero_approx(): state.apply_central_force(direction*(mass*.5 if assisted else AIR_STEERING_FORCE))
 var horizontal = Vector2(state.linear_velocity.x,state.linear_velocity.z)
 if assisted and horizontal.length()>MAX_SPEED:
  horizontal = horizontal.normalized()*MAX_SPEED
  state.linear_velocity.x = horizontal.x
  state.linear_velocity.z = horizontal.y
 # View orientation follows travel, independently of the sphere's rolling rotation.
 if not direction.is_zero_approx(): runtime.view_direction = direction
 if sinking:
  state.linear_velocity.y = minf(state.linear_velocity.y,-1.5)
  state.linear_velocity.x *= .9
  state.linear_velocity.z *= .9
