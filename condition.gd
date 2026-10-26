extends "res://shared/world_runtime.gd"
# A plot owns its data and physics. The Ring selects one active traveller/sky.
signal arrived(plot)
const HALF = 12.0 # Legacy plot unit; the Dunes path bounds this longer build.
# Stored only for compatibility with earlier scenes; painted height is unrestricted.
@export_storage var maximum_floor = 2
var terrain_columns: Dictionary = {}
var painted_bounds = Rect2()
var has_painted_bounds = false
var cloud_altitude = 26.0
const A = Vector3(0,0.45,0)
const B = Vector3(168,0,0) # Fallback only; move Beacons/BOrb to choose the destination.
const GROUND = 0
const RAISED = 1
const RAMP = 2
const WALL = 3
const WATER = 4
const GOAL = 5
@export var active_plot = true
var arrival_seconds = -1.0
var run_seconds = 0.0
@export var starting_hour = 0.0
var follow = true
@export var first_person = false
var free_view = false
var free_pitch = -.18
var camera_hint: Label
var chase_distance = 4.5
@export_range(0,6,.05) var observation_rate = .2
var observation_accumulator = 0.0
var observation_count = 0
var view_direction = Vector3.RIGHT
var view_yaw = 0.0
var plot_errors: Array[String] = []
var condition_path = ""
var reset_count = 0
var ignored_cell_count = 0
var compiled_report: Array = []
var rain_spawned = {}
var wheel
var placed_props: Array = []
var lamps: Array = []
var fire_lights: Array = []
var lighting_age = 0.0
var last_safe_position = A
var safe_age = 0.0
var recovery_count = 0
func _ready() -> void:
 compiler.load_catalogue()
 partial_support = compiler.read_json("res://catalogue/engine-unsupported.json")
 # scene_file_path follows a student's plot into its submodule in the Ring.
 condition_path = scene_file_path.get_base_dir().path_join("Condition.json")
 hour = starting_hour
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--condition="): condition_path = arg.trim_prefix("--condition=")
  if arg.begins_with("--hour="): hour = clampf(float(arg.trim_prefix("--hour=")),0,23.999)
 if not compiler.set_world(compiler.read_json(condition_path)):
  errors = compiler.errors.duplicate()
  push_error("Cannot open Condition.json: "+str(errors))
  $HUD/Label.text = "Cannot open Condition.json"
  set_physics_process(false)
  return
 preview_seconds = float(compiler.world.day_length_seconds)
 validate_plot()
 wheel = $Wheel
 wheel.runtime = self
 wheel.data = {"id":0,"kind":"things","mass":1.0,"scale":1.0,"sonority":0.0,"visibility":1.0,"brightness":0.0,"mobility":1.0,"state":"solid","shape":"round","weather":false}
 wheel.configure_scale()
 bodies = [wheel]
 next_id = 1
 $Overview.environment = $Overview.environment.duplicate(true)
 $Follow.environment = $Overview.environment
 $Overview.size = $Dunes.route_length+45
 $Overview.position = Vector3($Dunes.route_length/2,$Dunes.route_length*.7,$Dunes.route_length*.45)
 $Overview.look_at(to_global(Vector3($Dunes.route_length/2,0,0)),Vector3.UP)
 $Follow.look_at(to_global(wheel.position),Vector3.UP)
 create_clouds()
 create_props()
 create_beacons()
 for i in range(8): spawn_observation(true)
 create_camera_hint()
 $Instructions.visible = not follow
 $Forces.bind_plot(self)
 compiled_report = compatibility_report()
 set_active(active_plot)
 reset_wheel()
 update_local_lights()
func set_active(value: bool) -> void:
 active_plot = value
 if not is_node_ready(): return
 $Sun.visible = value
 $Dunes.visible = value
 if has_node("Beacons"): $Beacons.visible = value
 $CustomPieces.visible = value
 if has_node("MapNotes"): $MapNotes.visible = value
 for emitter in $Emitters.get_children():
  if emitter is AudioStreamPlayer3D: emitter.stream_paused = not value
 for lamp in lamps: lamp.visible = value
 $HUD.visible = value
 $Wheel.freeze = not value
 $Wheel.visible = value
 $Overview.current = value and not follow
 $Follow.current = value and follow
 update_view(0)
func _unhandled_input(event: InputEvent) -> void:
 if not active_plot: return
 if event is InputEventMouseMotion and free_view and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
  $Follow.rotation.y -= event.relative.x*.003
  $Follow.rotation.x = clampf($Follow.rotation.x-event.relative.y*.003,-1.45,1.45)
  get_viewport().set_input_as_handled()
 if event is InputEventMouseButton and event.pressed:
  var step = -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 0
  if step != 0:
   if not follow: $Overview.size = clampf($Overview.size*pow(1.15,step),6,650)
   elif not free_view and not first_person: chase_distance = clampf(chase_distance+step*.5,1.5,12)
 if not event is InputEventKey or not event.pressed or event.echo: return
 if event.keycode == KEY_R: reset_wheel()
 if event.keycode in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_Q,KEY_E] and follow and not free_view:
  enter_free_camera()
 if event.keycode == KEY_F:
  if free_view: free_view = false; follow = true
  else: enter_free_camera()
  set_camera_current()
  update_view(0)
  get_viewport().set_input_as_handled()
 if event.keycode == KEY_C:
  free_view = false
  follow = true
  first_person = not first_person
  set_camera_current()
  update_view(0)
  get_viewport().set_input_as_handled()
 if event.keycode == KEY_TAB:
  free_view = false
  follow = not follow
  set_camera_current()
  update_view(0)
  get_viewport().set_input_as_handled()
func set_camera_current() -> void:
 $Overview.current = active_plot and not follow
 $Follow.current = active_plot and follow
 $Instructions.visible = not follow
func enter_free_camera() -> void:
 free_view = true
 follow = true
 $Follow.position += Vector3.UP*1.5
 set_camera_current()
func create_camera_hint() -> void:
 camera_hint = Label.new()
 camera_hint.position = Vector2(24,764)
 camera_hint.add_theme_font_size_override("font_size",15)
 camera_hint.add_theme_color_override("font_color",Color(.88,.89,.9,.85))
 camera_hint.add_theme_color_override("font_outline_color",Color(0,0,0))
 camera_hint.add_theme_constant_override("outline_size",3)
 $HUD.add_child(camera_hint)
func camera_controls(delta: float) -> void:
 if free_view:
  var side = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
  var ahead = float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
  var up = float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
  var motion = $Follow.basis.x*side-$Follow.basis.z*ahead+Vector3.UP*up
  var speed = 30 if Input.is_physical_key_pressed(KEY_SHIFT) else 12
  $Follow.position += motion.limit_length(1)*speed*delta
 elif not follow:
  var side = float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A))
  var ahead = float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
  var forward = -$Overview.basis.z
  forward.y = 0
  var right = $Overview.basis.x
  right.y = 0
  $Overview.position += (forward.normalized()*ahead+right.normalized()*side).limit_length(1)*maxf(6,$Overview.size*.5)*delta
 if is_instance_valid(camera_hint):
  camera_hint.text = "Free camera · WASD move · Q/E down/up · hold right mouse to look · F return" if free_view else "Map · WASD pan · scroll zoom · Tab return" if not follow else ("First person" if first_person else "Follow")+" · arrows roll · C camera · WASD explore · Tab map · R reset"
func _physics_process(delta: float) -> void:
 if compiler.world.is_empty() or not active_plot: return
 run_seconds += delta
 $Forces.apply_to(compiler)
 super._physics_process(delta)
 camera_controls(delta)
 update_view(delta)
 update_props(delta)
 for piece in $CustomPieces.get_children():
  if piece.get("kind") == "Tree" and piece.has_node("Visual"):
   piece.get_node("Visual").rotation.z = sin(elapsed)*.025*float(current.weather.get("wind_strength",1)) if current.weather.wind_enabled else 0.0
 $Forces.update_values()
 update_safe_position(delta)
 check_wheel_cell(delta)
 var title = str(compiler.world.get("title","My condition"))
 $HUD/Label.text = "%s · %02d:%02d" % [title,int(hour),int(fmod(hour,1)*60)]
 if ignored_cell_count > 0:
  $HUD/Label.text += "\n%d cells ignored" % ignored_cell_count
 if arrival_seconds >= 0:
  $HUD/Label.text += "\nArrived · %02d:%02d" % [int(arrival_seconds)/60,int(arrival_seconds)%60]
func reset_wheel() -> void:
 if wheel == null: return
 arrival_seconds = -1
 run_seconds = 0
 reset_count += 1
 wheel.freeze = not active_plot
 last_safe_position = A
 wheel.reset_to(to_global(A))
 view_direction = Vector3.RIGHT
 view_yaw = 0
 update_view(0)
func refresh_painted_bounds() -> void:
 # Derive the playable envelope before validation or prop conversion removes cells.
 # Separate painted islands share one rectangle; sand and void still recover.
 has_painted_bounds = false
 cloud_altitude = 26.0
 for grid in [$Terrain,$Things]:
  for cell in grid.get_used_cells():
   var point = grid_point(grid,cell)
   var flat = Vector2(point.x,point.z)
   if not has_painted_bounds:
    painted_bounds = Rect2(flat,Vector2.ZERO)
    has_painted_bounds = true
   else: painted_bounds = painted_bounds.expand(flat)
   cloud_altitude = maxf(cloud_altitude,point.y+12.0)
 if has_painted_bounds: painted_bounds = painted_bounds.grow(2.0)
func in_plot(local_position: Vector3) -> bool:
 return $Dunes.allows($Dunes.to_local(to_global(local_position))) or (has_painted_bounds and painted_bounds.has_point(Vector2(local_position.x,local_position.z)))
# Convert through both node transforms: painted tiles and editor grid share cell edges.
func grid_point(grid: GridMap,cell: Vector3i) -> Vector3:
 return to_local(grid.to_global(grid.map_to_local(cell)))
func grid_cell(grid: GridMap,point: Vector3) -> Vector3i:
 var local_point = grid.to_local(to_global(point))
 # Preserve older uncentred project files as well as the aligned template.
 if not grid.cell_center_x: local_point.x += grid.cell_size.x*.5
 if not grid.cell_center_z: local_point.z += grid.cell_size.z*.5
 return grid.local_to_map(local_point)
func surface_height(cell: Vector3i,tile: int,pos: Vector3) -> float:
 if tile == RAMP:
  var basis = $Terrain.get_basis_with_orthogonal_index($Terrain.get_cell_item_orientation(cell))
  var point = basis.inverse()*(pos-grid_point($Terrain,cell))
  return float(cell.y)+clampf(point.x+.5,0,1)
 return float(cell.y)+(2.0 if tile == WALL else 1.0 if tile == RAISED else 0.0)
func surface_cell(local_position: Vector3) -> Vector3i:
 var cell = grid_cell($Terrain,local_position)
 # The surface below this body, not the highest tile anywhere in its column.
 for probe in terrain_columns.get(Vector2i(cell.x,cell.z),[]):
  var tile = $Terrain.get_cell_item(probe)
  if tile in [0,1,2,3,4,5,10] and surface_height(probe,tile,local_position)<=local_position.y+.1: return probe
 return Vector3i(cell.x,-1,cell.z)
func tile_under(local_position: Vector3) -> int:
 return $Terrain.get_cell_item(surface_cell(local_position))
func check_wheel_cell(delta: float) -> void:
 if wheel.pending_reset: return
 var pos: Vector3 = wheel.position
 # A checkpoint is a return address, not a height limit: allow full ramp arcs.
 # Recover only below the world's dunes, rather than two metres below a ramp.
 var dune_point = $Dunes.to_local(wheel.global_position)
 var void_point = Vector3(dune_point.x,$Dunes.height_at(dune_point.x,dune_point.z)-12.0,dune_point.z)
 var void_floor = to_local($Dunes.to_global(void_point)).y
 if not in_plot(pos) or pos.y < void_floor:
  recover_wheel()
  return
 var tile = tile_under(pos)
 if tile == WATER: wheel.water_level = surface_cell(pos).y
 var cell = grid_cell($Terrain,pos)
 var under_water = wheel.sinking and $Terrain.get_cell_item(Vector3i(cell.x,wheel.water_level,cell.z)) == WATER
 if under_water or (tile == WATER and pos.y < float(wheel.water_level)+.6):
  wheel.sinking = true
  wheel.sink_age += delta
  if wheel.sink_age > .75: recover_wheel()
 elif tile != WATER:
  wheel.sinking = false
  wheel.sink_age = 0
 if at_destination(pos) and arrival_seconds < 0:
  arrival_seconds = run_seconds
  wheel.set_deferred("freeze",true)
  arrived.emit(self)
func destination_point() -> Vector3:
 var orb = get_node_or_null("Beacons/BOrb")
 return to_local(orb.global_position)-Vector3(0,1.5,0) if orb != null else B
func at_destination(point: Vector3) -> bool:
 var destination = destination_point()
 return Vector2(point.x-destination.x,point.z-destination.z).length() < .7 and absf(point.y-destination.y-.32) < .65
func validate_plot() -> Array[String]:
 # The editor stays unrestricted. These changes affect only the running copy.
 refresh_painted_bounds()
 plot_errors.clear()
 ignored_cell_count = 0
 for grid in [$Terrain,$Things]:
  grid.straighten_tiles()
  for cell in grid.get_used_cells():
   if not in_plot(grid_point(grid,cell)):
    grid.set_cell_item(cell,-1)
    ignored_cell_count += 1
 $Terrain.set_cell_item(Vector3i.ZERO,GROUND)
 # Keep headroom immediately above A; higher roofs and platforms remain editable.
 for level in range(1,3): $Terrain.set_cell_item(Vector3i(0,level,0),-1)
 # Older projects used a Goal tile. Keep their destination and turn it into floor.
 var goals = $Terrain.get_used_cells_by_item(GOAL)
 if not goals.is_empty():
  if has_node("Beacons/BOrb"):
   $Beacons/BOrb.position = $Beacons.to_local(to_global(grid_point($Terrain,goals[0])+Vector3(0,1.5,0)))
  for cell in goals: $Terrain.set_cell_item(cell,GROUND)
 rebuild_terrain_columns()
 return plot_errors
func rebuild_terrain_columns() -> void:
 # Index actual painted layers, including negative and widely separated floors.
 terrain_columns.clear()
 for cell in $Terrain.get_used_cells():
  var column = Vector2i(cell.x,cell.z)
  if not terrain_columns.has(column): terrain_columns[column] = []
  terrain_columns[column].append(cell)
 for cells in terrain_columns.values():
  cells.sort_custom(func(a,b): return a.y>b.y)
func ground_at(world_position: Vector3) -> float:
 # Look below the body: a roof above it must never become its ground plane.
 var hit = get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(world_position+Vector3.UP*.05,world_position+Vector3.DOWN*12,5))
 return float(hit.position.y) if not hit.is_empty() else global_position.y-20
func wheel_support(origin: Vector3) -> Dictionary:
 var query = PhysicsRayQueryParameters3D.create(origin+Vector3.UP*.02,origin+Vector3.DOWN*.72,1)
 query.exclude = [wheel.get_rid()]
 return get_world_3d().direct_space_state.intersect_ray(query)
func wheel_barrier(origin: Vector3,direction: Vector3) -> Dictionary:
 var query = PhysicsRayQueryParameters3D.create(origin,origin+direction*.62,5)
 query.exclude = [wheel.get_rid()]
 var hit = get_world_3d().direct_space_state.intersect_ray(query)
 return hit if not hit.is_empty() and hit.normal.dot(Vector3.UP)<.45 else {}
func wrap_body(body) -> bool:
 if body == wheel: return false
 var local = $Dunes.to_local(body.global_position)
 var sand_y = $Dunes.to_global(Vector3(local.x,$Dunes.height_at(local.x,local.z),local.z)).y
 var visible_bounds = local.x>=-14 and local.x<$Dunes.route_length+24 and absf(local.z-$Dunes.center_at(local.x).z)<$Dunes.width_at(local.x)/2+$Dunes.bank_width if body.data.get("visual_only",false) else in_plot(body.position)
 if not visible_bounds or body.global_position.y < sand_y-2 or elapsed-float(body.data.get("born",elapsed))>45:
  remove_body(body)
  return true
 return false
func remove_body(body) -> void:
 if body == wheel: return
 super.remove_body(body)
func emit_weather(delta: float) -> void:
 observation_accumulator = minf(2,observation_accumulator+delta*observation_rate)
 while observation_accumulator>=1 and bodies.size()<compiler.numbers.body.cap:
  observation_accumulator -= 1
  spawn_observation(false)
 if not current.weather.emitting:
  rain_accumulator = 0
  return
 var rate = compiler.numbers.bench.cloud_rate*current.weather.get("rain_rate",1.0)
 rain_accumulator = minf(2,rain_accumulator+delta*rate)
 while rain_accumulator>=1 and bodies.size()<compiler.numbers.body.cap:
  rain_accumulator -= 1
  var kind = current.weather.cloud_things
  if not compiler.numbers.bench.precipitation.has(kind): kind = "things"
  var material = compiler.numbers.bench.precipitation[kind]
  var x = clampf(wheel.position.x+6+compiler.noise(next_id,1)*22,0,$Dunes.route_length)
  var z = $Dunes.center_at(x).z+(compiler.noise(next_id,9)-.5)*minf(24,$Dunes.width_at(x))
  var up = current.weather.cloud_verb == "rise"
  var y = $Dunes.height_at(x,z)+.4 if up else maxf(4,$Dunes.height_at(x,z))+20+compiler.noise(next_id,21)*8
  var body = spawn(kind,Vector3(x,y,z),Vector3.UP*material.launch*(1 if up else -1),true)
  if body != null: rain_spawned[kind] = int(rain_spawned.get(kind,0))+1
func create_clouds() -> void:
 var clouds = Node3D.new()
 clouds.name = "CloudMarkers"
 add_child(clouds)
 for i in range(3):
  var mesh = MeshInstance3D.new()
  var shape = SphereMesh.new()
  shape.radius = 1.2
  shape.height = 2.4
  shape.radial_segments = 12
  shape.rings = 6
  mesh.mesh = shape
  mesh.scale = Vector3(1.5,.12,.65)
  var mat = StandardMaterial3D.new()
  mat.albedo_color = Color(.65,.68,.7,.5)
  mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
  mesh.material_override = mat
  clouds.add_child(mesh)
func update_clouds() -> void:
 var count = $CloudMarkers.get_child_count()
 for i in range(count):
  var x = lerpf(28.0,$Dunes.route_length-20.0,float(i)/maxi(1,count-1))
  var cloud = $CloudMarkers.get_child(i)
  cloud.position = Vector3(x,cloud_altitude,$Dunes.center_at(x).z+(8.0 if i%2 else -8.0))
  cloud.visible = current.weather.emitting
func compatibility_report() -> Array:
 var report = []
 for card in compiler.world.forces:
  for law in report_entries(card):
   var status = "honoured"
   var instead = "The scheduled law acts on matching things inside this plot."
   var ignored = []
   var approx = []
   for gap in partial_support:
    if gap.law == law.id and (gap.get("slot","").is_empty() or gap.get("options",[]).has(law.slots.get(gap.slot))):
     approx.append(gap.reason)
   for planned in compiler.planned:
    if planned.law == law.id and planned.from_hour == law.from_hour: ignored.append(str(planned.key)+" is not simulated.")
   if law.id == "sound.fade":
    status = "ignored"
    instead = "Ordinary distance attenuation and impact-dependent volume; authored increasing/selective fade is not simulated."
   elif law.id == "sound.travel" and law.slots.get("vector","straight") != "straight":
    status = "approximated"
    instead = "Positional sound and radial impact rings; wave/zigzag travel and propagation delay are not simulated."
   elif law.id == "matter.solid" and law.slots.get("meeting") == "attract":
    status = "approximated"
    instead = "Touching bodies bond; distant bodies do not attract."
   elif law.id == "motion.heavier":
    status = "approximated"
    instead = "Relative qualities adjust wind/contact response; loud means last-impact sonority, not continuously measured audio."
   elif law.id == "weather.rain":
    status = "approximated"
    instead = "Rain uses elongated droplets with brief flattened splashes; ash uses thin fluttering flakes; snow uses six-armed flakes. Meteors are faceted stones that glow with speed. Collision remains a simplified sphere; no melting, growth or combustion."
   elif law.id == "light.glow":
    instead = "The sun and sky take this colour; the law does not recolour every object."
   elif law.id == "gravity.rise":
    instead = "A rising body can stay at its apex; grounded things are not lifted by this law."
   if not approx.is_empty() and status == "honoured":
    status = "approximated"
    instead = "; ".join(approx)
   if not ignored.is_empty():
    status = "ignored"
    instead = " ".join(ignored)
   report.append({"force":card.name,"law":law.id,"from_hour":law.from_hour,"implicit":law.get("implicit",false),"status":status,"student_sees":instead})
  for change in card.get("parameter_changes",[]):
   report.append({"force":card.name,"parameter":change.key,"from_hour":change.from_hour,"value":change.value,"status":"honoured","student_sees":"A bounded numeric change begins at this hour and persists until replaced."})
 report.append({"system":"Wheel controls","status":"approximated","student_sees":("Assisted on: arrows target a steady speed, brake at idle, grip build surfaces and cap horizontal speed at 3 m/s, including under zero or upward gravity. " if wheel.assisted else "Assisted off: arrows apply force (4 N grounded; 0.5 N airborne), with no controller braking, adhesion, velocity targeting or speed cap. Linear and angular damping use condition resistance without added project damping. Ramp takeoff preserves momentum. ")+"Both modes use condition gravity, wind and rebound. The Wheel retains its standard size and does not implement every generic Thing rest/apex/size law; falling things demonstrate those laws."})
 report.append({"system":"Observation things","status":"approximated","student_sees":"A sparse stream of glowing generic Things demonstrates the condition on the dune slopes between A and B, independently of timed weather. They land and roll on the sand, never push the Wheel and expire after 45 seconds."})
 report.append({"system":"Placed props","status":"approximated","student_sees":"Stones are generic Things using the same law and numeric-parameter runtime as precipitation. Trees stay rooted and sway with wind; Lamps cast their own light throughout the day, including in sunless conditions. Nearby lights illuminate the map; distant bulbs and flames keep their glow. Neither is a new wheel vocabulary option."})
 report.append({"system":"Plot boundary","status":"approximated","student_sees":"Painted routes extend the permitted X/Z region beyond the dune corridor, with a two-metre margin. Separated painted areas share one rectangular envelope. Sand contact, water and the void still return the Wheel to its last safe build surface; crossing the former corridor boundary alone does not. Precipitation expires outside the permitted region."})
 if has_node("Forces") and not $Forces.overrides().is_empty():
  report.append({"system":"Godot numeric overrides","status":"approximated","values":$Forces.overrides(),"student_sees":"Each named card's Inspector values replace its imported numeric schedule only when that card supplies the resolved parameter, across its matching bodies. Imported law words, eligibility and timing of other parameters remain in Condition.json."})
 if has_node("Forces") and $Forces.preview_clock_enabled:
  report.append({"system":"Godot day duration","status":"approximated","student_sees":"Day duration is %s base seconds; the imported Condition remains %s base seconds. Time rate and the imported clock laws still apply."%[$Forces.preview_day_seconds,compiler.world.day_length_seconds]})
 return report

func report_entries(card: Dictionary) -> Array:
 var entries = []
 for definition in compiler.laws:
  if definition.bundle != card.template or definition.tier == "name": continue
  var explicit = card.laws.filter(func(entry): return entry.id == definition.id)
  if not explicit.is_empty(): entries.append_array(explicit)
  else:
   var at = 6 if definition.id == "light.sunrise" else 18 if definition.id == "light.sunset" else 14 if definition.id == "weather.rain" else 0
   entries.append({"id":definition.id,"from_hour":at,"slots":compiler.defaults(definition),"implicit":true})
 return entries

func create_props() -> void:
 # A second GridMap lets a thing share a cell with the ground beneath it.
 for grid in [$Terrain,$Things]:
  for cell in grid.get_used_cells():
   var item = grid.get_cell_item(cell)
   if item not in [6,7,8,9]: continue
   var point = grid_point(grid,cell)
   var orientation = grid.get_basis_with_orthogonal_index(grid.get_cell_item_orientation(cell))
   grid.set_cell_item(cell,-1) # Remove the static palette preview in this running copy.
   var kind = "Tree" if item == 6 else "Lamp" if item == 7 else "Stone"
   if item == 9:
    var fire = load("res://pieces/fire.tscn").instantiate()
    $CustomPieces.add_child(fire)
    fire.position = point
   elif item == 8:
    var stone = spawn("things",point+Vector3(0,.34,0),Vector3.ZERO,false,2)
    if stone == null: continue
    stone.name = "Stone%d" % stone.data.id
    stone.data.scale = .9
    stone.data.mass = 1.5
    stone.data.brightness = 0
    stone.configure_scale()
    placed_props.append(stone)
   else:
    var prop = Node3D.new()
    prop.name = kind+str(placed_props.size())
    $Bodies.add_child(prop)
    prop.position = point
    prop.basis = orientation
    var mesh = MeshInstance3D.new()
    mesh.mesh = $Terrain.mesh_library.get_item_mesh(item)
    mesh.transform = $Terrain.mesh_library.get_item_mesh_transform(item)
    prop.add_child(mesh)
    var solid = StaticBody3D.new()
    var shape = CollisionShape3D.new()
    var cylinder = CylinderShape3D.new()
    cylinder.radius = .08
    cylinder.height = 1.5 if item == 7 else .8
    shape.shape = cylinder
    shape.position.y = cylinder.height/2
    solid.add_child(shape)
    prop.add_child(solid)
    prop.set_meta("kind",kind)
    placed_props.append(prop)
    if item == 7:
     var lamp = Node3D.new()
     lamp.set_script(load("res://shared/grid_lamp.gd"))
     prop.add_child(lamp)
     lamps.append(lamp)
 # Keep all painted objects; budget their real lights together with glowing Things.
 for fire in $CustomPieces.get_children():
  if fire.get_script() == load("res://shared/fire.gd") and fire.has_node("Light"):
   fire_lights.append(fire.get_node("Light"))
 update_local_lights()
func update_local_lights() -> void:
 var camera = get_viewport().get_camera_3d()
 if camera == null: return
 # Compatibility has a small per-mesh light limit. Reserve two slots for A/B.
 # A row viewed end-on must not crowd out the lights around the Wheel.
 var lights: Array = fire_lights.duplicate()
 for lamp in lamps: lights.append(lamp.get_node("Light"))
 for body in bodies:
  if not is_instance_valid(body): continue
  for child in body.get_children():
   if child is OmniLight3D: lights.append(child)
 lights.sort_custom(func(a,b): return a.global_position.distance_squared_to(camera.global_position)<b.global_position.distance_squared_to(camera.global_position))
 var used = 0
 var fires = 0
 for light in lights:
  var is_fire = light in fire_lights
  var enabled = used < 6 and (not is_fire or fires < 4)
  light.visible = enabled
  if enabled:
   used += 1
   if is_fire: fires += 1
func update_fire_lights() -> void:
 # Retain the old entry point for existing test tools.
 update_local_lights()
func update_props(_delta: float) -> void:
 lighting_age += _delta
 if lighting_age >= .25:
  lighting_age = 0.0
  update_local_lights()
 # A placed lamp is a light source, independent of the sun's strength or schedule.
 for lamp in lamps: lamp.set_strength(1.0)
 for prop in placed_props:
  if not is_instance_valid(prop) or prop is RigidBody3D: continue
  if prop.get_meta("kind","") == "Tree":
   prop.get_child(0).rotation.z = sin(elapsed*1.4+prop.position.x)*.025*float(current.weather.get("wind_strength",1.0)) if current.weather.wind_enabled else 0.0

func update_safe_position(delta: float) -> void:
 safe_age += delta
 if safe_age < .25 or wheel.pending_reset or wheel.sinking or arrival_seconds>=0: return
 safe_age = 0
 # Only a real build surface can become a checkpoint; the dunes use layer 4.
 var origin = wheel.global_position
 var query = PhysicsRayQueryParameters3D.create(origin,origin+Vector3.DOWN*.65,1)
 var hit = get_world_3d().direct_space_state.intersect_ray(query)
 if hit.is_empty() or hit.normal.dot(Vector3.UP)<.75 or absf(wheel.linear_velocity.dot(hit.normal))>.5: return
 var pos = to_local(hit.position)+Vector3.UP*.4
 if in_plot(pos) and tile_under(wheel.position) != WATER: last_safe_position = pos
func recover_wheel() -> void:
 recovery_count += 1
 wheel.freeze = not active_plot
 wheel.reset_to(to_global(last_safe_position))
 update_view(0)

func update_view(delta: float) -> void:
 if wheel == null: return
 var hidden = follow and first_person and not free_view
 for name_ in ["Sphere","RimStripe"]: wheel.get_node(name_).visible = not hidden
 if not follow or free_view: return
 var target_yaw = atan2(view_direction.z,view_direction.x)
 view_yaw = target_yaw if delta<=0 else lerp_angle(view_yaw,target_yaw,1-exp(-delta*12))
 var heading = Vector3(cos(view_yaw),0,sin(view_yaw))
 if first_person:
  $Follow.position = wheel.position+Vector3.UP*.18
  $Follow.look_at($Follow.global_position+heading*5,Vector3.UP)
 else:
  # A fixed forward view: arrows move the Wheel without steering this camera.
  heading = global_basis*Vector3.RIGHT
  var focus = wheel.global_position+Vector3.UP*.5
  var desired = wheel.global_position-heading*chase_distance+Vector3.UP*1.6
  if is_inside_tree() and get_world_3d()!=null:
   var query = PhysicsRayQueryParameters3D.create(focus,desired,5)
   query.exclude = [wheel.get_rid()]
   var hit = get_world_3d().direct_space_state.intersect_ray(query)
   if not hit.is_empty(): desired = hit.position+hit.normal*.2
  $Follow.global_position = desired if delta<=0 else $Follow.global_position.lerp(desired,1-exp(-delta*12))
  $Follow.look_at($Follow.global_position+heading*(chase_distance+.7)-Vector3.UP*1.25,Vector3.UP)
func spawn(kind: String,pos: Vector3,velocity: Vector3,weather: bool,index: int=0):
 var body = super.spawn(kind,pos,velocity,weather,index)
 if body != null and weather:
  body.data.visual_only = true
  body.data.born = elapsed
  body.collision_layer = 8
  body.collision_mask = 5
 return body
func spawn_observation(initial: bool) -> void:
 observation_count += 1
 var nearby = observation_count%3 != 0
 var x = clampf(wheel.position.x+14+compiler.noise(observation_count,41)*22,4,$Dunes.route_length) if nearby else lerpf(8,$Dunes.route_length,compiler.noise(observation_count,31))
 var center = $Dunes.center_at(x)
 var side = -1 if observation_count%2==0 else 1
 var z = center.z+side*($Dunes.width_at(x)/2+$Dunes.bank_width*(.32+compiler.noise(observation_count,44)*.25))
 var y = $Dunes.height_at(x,z)+20+compiler.noise(observation_count,47)*10
 if initial: y -= compiler.noise(observation_count,51)*8
 var body = spawn("things",Vector3(x,y,z),Vector3.DOWN*.3,true)
 if body != null:
  body.data.observation = true
  body.data.ground_lifetime = 24
  if observation_count%3==0:
   var light = OmniLight3D.new()
   light.light_color = Color("ffe1aa")
   light.light_energy = .7
   light.omni_range = 6
   body.add_child(light)
func create_beacons() -> void:
 var beacons = get_node_or_null("Beacons")
 if beacons == null:
  beacons = Node3D.new()
  beacons.name = "Beacons"
  add_child(beacons)
 var destination = destination_point()
 for item in [["AOrb",Vector3(0,3,0),Color("ffe0a3")],["BOrb",destination+Vector3(0,1.5,0),Color("72aeff")]]:
  var orb = beacons.get_node_or_null(item[0])
  if orb == null:
   orb = Node3D.new()
   orb.name = item[0]
   orb.set_script(load("res://shared/beacon.gd"))
   orb.colour = item[2]
   if item[0]=="BOrb":
    orb.brightness = 5.2
    orb.reach = 28
    orb.pulse = true
   beacons.add_child(orb)
  orb.position = item[1]
