@tool
extends EditorPlugin
const Shape = preload("shape.gd")
var palette: ItemList
var palette_age=0.0
var toolbar: HBoxContainer
var grid: GridMap
var dialog: ConfirmationDialog
var name_field: LineEdit
var collection: OptionButton
var part_list: ItemList
var fields={}
var colour: ColorPickerButton
var solid: CheckBox
var status: Label
var viewport: SubViewport
var model: MeshInstance3D
var camera: Camera3D
var parts: Array=[]
var selected=0
var editing=-1
var updating=false
var view_turn=.65
var canvas: BuilderCanvas
var focus_part: CheckBox
var snap: CheckBox
var history: Array=[]
var future: Array=[]
var view_mode="3D"
var drag_corner=-1
var drag_start=Vector3.ZERO
var drag_part: Dictionary={}
var drag_plane: Plane
var drag_changed=false
class BuilderCanvas extends Control:
 var builder
 func _draw() -> void:
  if builder:builder.draw_handles(self)
 func _gui_input(event: InputEvent) -> void:
  if builder:builder.preview_input(event)

func _enter_tree() -> void:
 toolbar=HBoxContainer.new()
 var button=Button.new();button.text="Make tile";button.tooltip_text="Build a custom shape and add it to this GridMap's tile palette."
 button.pressed.connect(open_builder);toolbar.add_child(button)
 add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU,toolbar)
 toolbar.hide()
 var filesystem=EditorInterface.get_resource_filesystem()
 filesystem.filesystem_changed.connect(restore_saved_tiles)
 call_deferred("restore_saved_tiles")
func _exit_tree() -> void:
 var filesystem=EditorInterface.get_resource_filesystem()
 if filesystem.filesystem_changed.is_connected(restore_saved_tiles):filesystem.filesystem_changed.disconnect(restore_saved_tiles)
 remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU,toolbar);toolbar.queue_free()
 if is_instance_valid(dialog):dialog.queue_free()
func _handles(object: Object) -> bool:return object is GridMap
func _edit(object: Object) -> void:grid=object as GridMap
func _make_visible(value: bool) -> void:
 if is_instance_valid(toolbar):toolbar.visible=value
func label(text: String,parent: Node) -> Label:
 var node=Label.new();node.text=text;parent.add_child(node);return node
func action(text: String,parent: Node,callback: Callable) -> Button:
 var node=Button.new();node.text=text;node.pressed.connect(callback);parent.add_child(node);return node
func build_dialog() -> void:
 dialog=ConfirmationDialog.new();dialog.title="Make tile";dialog.size=Vector2i(1000,640)
 dialog.ok_button_text="Add to GridMap";dialog.confirmed.connect(save_tile);dialog.dialog_hide_on_ok=false
 EditorInterface.get_base_control().add_child(dialog)
 var main=VBoxContainer.new();dialog.add_child(main)
 var heading=HBoxContainer.new();main.add_child(heading)
 label("Tile",heading);collection=OptionButton.new();collection.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(collection);collection.item_selected.connect(load_choice)
 var columns=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;main.add_child(columns)
 var left=VBoxContainer.new();left.custom_minimum_size.x=180;columns.add_child(left)
 label("Combine shapes",left)
 var row=HBoxContainer.new();left.add_child(row)
 action("+ Box",row,func():add_part("Box"));action("+ Sphere",row,func():add_part("Sphere"))
 row=HBoxContainer.new();left.add_child(row)
 action("+ Cylinder",row,func():add_part("Cylinder"));action("+ Ramp",row,func():add_part("Ramp"))
 part_list=ItemList.new();part_list.custom_minimum_size.y=320;part_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(part_list);part_list.item_selected.connect(select_part)
 action("Duplicate shape",left,duplicate_part)
 action("Remove shape",left,remove_part)
 focus_part=CheckBox.new();focus_part.text="Focus selected shape";focus_part.toggled.connect(func(_v):refresh_preview());left.add_child(focus_part)
 label("Select a shape here if another\none covers it in the preview.",left)
 var centre=VBoxContainer.new();centre.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(centre)
 var container=SubViewportContainer.new();container.stretch=true;container.custom_minimum_size=Vector2(360,440);container.size_flags_vertical=Control.SIZE_EXPAND_FILL;container.size_flags_horizontal=Control.SIZE_EXPAND_FILL;centre.add_child(container)
 viewport=SubViewport.new();viewport.size=Vector2i(440,440);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;container.add_child(viewport)
 var world=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("303437");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.55;world.environment=env;viewport.add_child(world)
 var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-25,0);sun.light_energy=1.2;viewport.add_child(sun)
 model=MeshInstance3D.new();viewport.add_child(model)
 # A line grid provides scale without hiding shapes moved below the floor.
 var grid_mesh=ImmediateMesh.new();grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
 for i in range(-12,13):
  grid_mesh.surface_add_vertex(Vector3(i+.5,0,-12.5));grid_mesh.surface_add_vertex(Vector3(i+.5,0,12.5))
  grid_mesh.surface_add_vertex(Vector3(-12.5,0,i+.5));grid_mesh.surface_add_vertex(Vector3(12.5,0,i+.5))
 grid_mesh.surface_end()
 var floor_mesh=MeshInstance3D.new();floor_mesh.mesh=grid_mesh
 var floor_mat=StandardMaterial3D.new();floor_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;floor_mat.albedo_color=Color("536168");floor_mesh.material_override=floor_mat;viewport.add_child(floor_mesh)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;viewport.add_child(camera)
 canvas=BuilderCanvas.new();canvas.builder=self;canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);canvas.mouse_filter=Control.MOUSE_FILTER_STOP;canvas.focus_mode=Control.FOCUS_ALL;container.add_child(canvas)
 canvas.resized.connect(func():canvas.queue_redraw())
 row=HBoxContainer.new();centre.add_child(row)
 for mode in ["3D","Front","Top","Side"]:
  var mode_name=mode
  action(mode,row,func():view_mode=mode_name;frame_preview())
 row=HBoxContainer.new();centre.add_child(row)
 action("Turn left",row,func():view_mode="3D";view_turn-=PI/8;frame_preview());action("Turn right",row,func():view_mode="3D";view_turn+=PI/8;frame_preview())
 action("Frame all",row,frame_preview)
 action("−",row,func():camera.size*=1.2;canvas.queue_redraw())
 action("+",row,func():camera.size=maxf(.2,camera.size/1.2);canvas.queue_redraw())
 label("Drag a shape to move · drag a gold corner to resize",centre)
 row=HBoxContainer.new();centre.add_child(row)
 action("Undo",row,undo_edit);action("Redo",row,redo_edit)
 snap=CheckBox.new();snap.text="Snap 0.1 m";snap.button_pressed=true;row.add_child(snap)
 var right=VBoxContainer.new();right.custom_minimum_size.x=270;columns.add_child(right)
 label("Name",right);name_field=LineEdit.new();name_field.placeholder_text="My tile";right.add_child(name_field)
 for group in ["Size","Position"]:
  label(group+" · metres",right)
  row=HBoxContainer.new();right.add_child(row)
  for axis in ["X","Y","Z"]:
   var column=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(column);label(axis,column)
   var spin=SpinBox.new();spin.min_value=.05 if group=="Size" else -24;spin.max_value=24;spin.step=.05;spin.custom_minimum_size.x=80;column.add_child(spin)
   fields[group+axis]=spin;spin.value_changed.connect(func(_value):write_part())
 label("Turn · degrees",right);var turn=SpinBox.new();turn.min_value=-360;turn.max_value=360;turn.step=15;right.add_child(turn);fields.Turn=turn;turn.value_changed.connect(func(_value):write_part())
 label("Colour",right);colour=ColorPickerButton.new();colour.custom_minimum_size.y=32;colour.edit_alpha=false;right.add_child(colour);colour.color_changed.connect(func(_value):refresh_preview())
 solid=CheckBox.new();solid.text="Solid · Wheel collides with it";solid.button_pressed=true;right.add_child(solid)
 var help=label("One grid cell is 1 metre wide.\nPosition Y is the bottom of the shape.\nY = 0 sits on the floor.\nLarger shapes can span several cells.",right);help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.custom_minimum_size.x=270
 status=label("",main);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
func open_builder() -> void:
 if not is_instance_valid(grid) or grid.mesh_library==null:return
 if not is_instance_valid(dialog):build_dialog()
 collection.clear();collection.add_item("New tile");collection.set_item_metadata(0,-1)
 var saved=grid.mesh_library.get_meta("custom_shapes",{})
 for id in saved:
  collection.add_item(grid.mesh_library.get_item_name(int(id)),int(id));collection.set_item_metadata(collection.item_count-1,int(id))
 load_choice(0);dialog.popup_centered_clamped(Vector2i(Vector2(1100,680)*EditorInterface.get_editor_scale()),.9)
func load_choice(index: int) -> void:
 editing=int(collection.get_item_metadata(index))
 if editing<0:
  parts=[];name_field.text="";colour.color=Color("b4bca9");solid.button_pressed=true;add_part("Box")
 else:
  var saved=grid.mesh_library.get_meta("custom_shapes",{})[str(editing)]
  parts=saved.parts.duplicate(true);name_field.text=grid.mesh_library.get_item_name(editing);colour.color=Color(saved.colour);solid.button_pressed=saved.solid;selected=0;refresh_list();read_part()
 dialog.ok_button_text="Add to GridMap" if editing<0 else "Update tile"
 history.clear();future.clear();status.text="";focus_part.button_pressed=false;refresh_preview();frame_preview()
func remember() -> void:
 history.append({"parts":parts.duplicate(true),"selected":selected})
 if history.size()>60:history.pop_front()
 future.clear()
func restore_state(state: Dictionary) -> void:
 parts=state.parts.duplicate(true);selected=state.selected;refresh_list();read_part();refresh_preview()
func undo_edit() -> void:
 if history.is_empty():return
 future.append({"parts":parts.duplicate(true),"selected":selected});restore_state(history.pop_back())
func redo_edit() -> void:
 if future.is_empty():return
 history.append({"parts":parts.duplicate(true),"selected":selected});restore_state(future.pop_back())
func add_part(kind: String) -> void:
 if not parts.is_empty():remember()
 var x=0.0
 if not parts.is_empty():x=Shape.mesh(parts,colour.color).get_aabb().end.x+.75
 parts.append({"kind":kind,"size":[1.0,1.0,1.0],"position":[x,.5,0.0],"turn":0.0})
 selected=parts.size()-1;refresh_list();read_part();refresh_preview();frame_preview()
func duplicate_part() -> void:
 if parts.is_empty():return
 remember();var copy=parts[selected].duplicate(true);copy.position[0]+=copy.size[0]+.25;parts.append(copy)
 selected=parts.size()-1;refresh_list();read_part();refresh_preview();frame_preview()
func remove_part() -> void:
 if parts.size()<2:status.text="Keep at least one shape in the tile.";return
 remember();parts.remove_at(selected);selected=mini(selected,parts.size()-1);refresh_list();read_part();refresh_preview()
func select_part(index: int) -> void:selected=index;read_part();refresh_preview()
func refresh_list() -> void:
 part_list.clear()
 for i in parts.size():part_list.add_item(str(i+1)+" · "+parts[i].kind)
 part_list.select(selected)
func read_part() -> void:
 updating=true
 for i in 3:
  var axis=["X","Y","Z"][i]
  fields["Size"+axis].value=parts[selected].size[i]
  fields["Position"+axis].value=parts[selected].position[i]-(float(parts[selected].size[1])*.5 if i==1 else 0.0)
 fields.Turn.value=parts[selected].turn;updating=false
func write_part() -> void:
 if updating or parts.is_empty():return
 remember()
 for i in 3:
  var axis=["X","Y","Z"][i]
  parts[selected].size[i]=fields["Size"+axis].value
  parts[selected].position[i]=fields["Position"+axis].value+(float(fields.SizeY.value)*.5 if i==1 else 0.0)
 parts[selected].turn=fields.Turn.value;refresh_preview()
func refresh_preview() -> void:
 if parts.is_empty() or not is_instance_valid(model):return
 model.mesh=Shape.mesh([parts[selected]] if focus_part.button_pressed else parts,colour.color)
 if is_instance_valid(canvas):canvas.queue_redraw()
func frame_preview() -> void:
 if parts.is_empty():return
 var bounds=Shape.mesh(parts,colour.color).get_aabb();var centre=bounds.get_center();var span=maxf(1.5,bounds.size.length())
 camera.size=span*1.25
 var direction=Vector3(cos(view_turn),.8,sin(view_turn))
 if view_mode=="Front":direction=Vector3(0,0,1)
 elif view_mode=="Side":direction=Vector3(1,0,0)
 elif view_mode=="Top":direction=Vector3(0,1,.0001)
 camera.position=centre+direction.normalized()*span*3;camera.look_at(centre)
 canvas.queue_redraw()
func corner_point(part: Dictionary,index: int) -> Vector3:
 var point=Vector3(1 if index&1 else -1,1 if index&2 else -1,1 if index&4 else -1)*.5
 return Shape.transform(part)*point
func screen_point(point: Vector3) -> Vector2:
 return camera.unproject_position(point)*canvas.size/Vector2(viewport.size)
func ray_point(point: Vector2) -> Vector3:
 var pixel=point*Vector2(viewport.size)/canvas.size
 var hit=drag_plane.intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))
 return hit if hit!=null else drag_start
func draw_handles(control: Control) -> void:
 if parts.is_empty() or not is_instance_valid(camera):return
 # The outlined origin cell matches the painted GridMap footprint.
 var footprint=[Vector3(-.5,0,-.5),Vector3(.5,0,-.5),Vector3(.5,0,.5),Vector3(-.5,0,.5)]
 for i in 4:control.draw_line(screen_point(footprint[i]),screen_point(footprint[(i+1)%4]),Color("80b6c2"),2,true)
 var points=[]
 for i in 8:points.append(screen_point(corner_point(parts[selected],i)))
 for i in 8:
  for bit in [1,2,4]:
   if not i&bit:control.draw_line(points[i],points[i|bit],Color("ffd271"),2,true)
 for point in points:
  control.draw_circle(point,6,Color("ffd271"));control.draw_arc(point,6,0,TAU,16,Color("453718"),1,true)
func preview_input(event: InputEvent) -> void:
 if parts.is_empty():return
 if event is InputEventKey and event.pressed:
  if event.keycode==KEY_Z and (event.ctrl_pressed or event.meta_pressed):
   if event.shift_pressed:redo_edit()
   else:undo_edit()
   canvas.accept_event()
  elif event.keycode==KEY_DELETE or event.keycode==KEY_BACKSPACE:remove_part();canvas.accept_event()
 if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  if event.pressed:
   canvas.grab_focus();drag_corner=-1
   var nearest=12.0
   for i in 8:
    var distance=screen_point(corner_point(parts[selected],i)).distance_to(event.position)
    if distance<nearest:nearest=distance;drag_corner=i
   if drag_corner<0:
    var pixel=event.position*Vector2(viewport.size)/canvas.size
    var origin=camera.project_ray_origin(pixel);var direction=camera.project_ray_normal(pixel)
    var hit_index=-1;var best=INF
    for i in parts.size():
     if focus_part.button_pressed and i!=selected:continue
     var inverse=Shape.transform(parts[i]).affine_inverse()
     var local_origin=inverse*origin;var local_direction=inverse.basis*direction
     var hit=AABB(Vector3.ONE*-.5,Vector3.ONE).intersects_ray(local_origin,local_direction)
     if hit!=null:
      var distance=(Shape.transform(parts[i])*hit).distance_squared_to(origin)
      if distance<best:best=distance;hit_index=i
    if hit_index<0:return
    selected=hit_index;refresh_list();read_part();refresh_preview()
   drag_part=parts[selected].duplicate(true)
   var centre=Vector3(drag_part.position[0],drag_part.position[1],drag_part.position[2])
   drag_plane=Plane(camera.global_basis.z,centre);drag_start=ray_point(event.position);drag_changed=false
   canvas.accept_event()
  else:
   drag_part={};drag_corner=-1;canvas.accept_event()
 elif event is InputEventMouseMotion and not drag_part.is_empty():
  var delta=ray_point(event.position)-drag_start
  if delta.length()<.001:return
  if not drag_changed:remember();drag_changed=true
  var centre=Vector3(drag_part.position[0],drag_part.position[1],drag_part.position[2])
  var size=Vector3(drag_part.size[0],drag_part.size[1],drag_part.size[2])
  if drag_corner<0:
   centre+=delta
   if snap.button_pressed:centre=centre.snapped(Vector3.ONE*.1)
  else:
   var basis=Basis(Vector3.UP,deg_to_rad(drag_part.turn))
   var local_delta=basis.inverse()*delta
   var sign=Vector3(1 if drag_corner&1 else -1,1 if drag_corner&2 else -1,1 if drag_corner&4 else -1)
   var next_size=(size+local_delta*sign).max(Vector3.ONE*.05).min(Vector3.ONE*24)
   # Keep depth unchanged in the flat views; resize relative to the opposite corner.
   if view_mode=="Front":next_size.z=size.z
   elif view_mode=="Side":next_size.x=size.x
   elif view_mode=="Top":next_size.y=size.y
   if snap.button_pressed:next_size=next_size.snapped(Vector3.ONE*.1).max(Vector3.ONE*.1)
   centre+=basis*((next_size-size)*sign*.5);size=next_size
  parts[selected].position=[centre.x,centre.y,centre.z];parts[selected].size=[size.x,size.y,size.z]
  read_part();refresh_preview();canvas.accept_event()
func save_tile() -> void:
 if not is_instance_valid(grid):status.text="Select your GridMap and open Make tile again.";return
 var tile_name=name_field.text.strip_edges()
 if tile_name.is_empty():status.text="Give your tile a name first.";return
 var library=grid.mesh_library
 var duplicate=library.find_item_by_name(tile_name)
 if duplicate>=0 and duplicate!=editing:status.text="That name is already in the palette. Choose a different name.";return
 var path=library.resource_path
 if not path.begins_with("res://") or not path.ends_with(".tres"):status.text="This GridMap needs a saved MeshLibrary (.tres).";return
 var updated=library.duplicate(true)
 var id=editing if editing>=0 else maxi(11,updated.get_last_unused_item_id())
 if editing<0:updated.create_item(id)
 updated.set_item_name(id,tile_name);updated.set_item_mesh(id,Shape.mesh(parts,colour.color));updated.set_item_mesh_transform(id,Transform3D.IDENTITY)
 updated.set_item_shapes(id,Shape.shapes(parts) if solid.button_pressed else [])
 var saved=updated.get_meta("custom_shapes",{}).duplicate(true)
 saved[str(id)]={"parts":parts.duplicate(true),"colour":colour.color.to_html(false),"solid":solid.button_pressed};updated.set_meta("custom_shapes",saved)
 var error=ResourceSaver.save(updated,path)
 if error!=OK:status.text="The tile could not be saved: "+error_string(error);return
 # Keep both Terrain and Things on the same library, including scenes opened later.
 updated.take_over_path(path)
 var root=EditorInterface.get_edited_scene_root()
 for node in root.find_children("*","GridMap",true,false):
  if node.mesh_library==library:node.mesh_library=updated
 EditorInterface.mark_scene_as_unsaved()
 EditorInterface.get_resource_filesystem().scan_sources()
 dialog.call_deferred("hide")

# Keep the editor's real palette in teaching order without altering item names
# or IDs. Godot's brush reads each item's metadata, so moves preserve painting.
func _process(delta: float) -> void:
 if not is_instance_valid(toolbar) or not toolbar.visible or not is_instance_valid(grid) or grid.mesh_library==null:return
 palette_age+=delta
 if palette_age<.25:return
 palette_age=0.0
 if not is_instance_valid(palette) or not palette.is_visible_in_tree():
  palette=null
  for candidate in EditorInterface.get_base_control().find_children("*","ItemList",true,false):
   var parent=candidate.get_parent()
   while parent!=null and parent.get_class()!="GridMapEditor":parent=parent.get_parent()
   if parent!=null and candidate.item_count>0:
    palette=candidate;break
 if not is_instance_valid(palette):return
 order_palette(palette,grid.mesh_library)
func palette_rank(id: int,library: MeshLibrary) -> int:
 var ids=[0,1,2,3,10,8,4,6,7,9]
 var labels=["Ground","Raised","Ramp","Wall","Roof","Stone","Water","Tree","Lamp","Fire"]
 var rank=ids.find(id)
 return rank if rank>=0 and library.get_item_name(id)==labels[rank] else 100+id
func order_palette(list: ItemList,library: MeshLibrary) -> void:
 var desired=[]
 for i in list.item_count:
  var id=list.get_item_metadata(i)
  if not id is int or id not in library.get_item_list() or list.get_item_text(i)!=library.get_item_name(id):return
  # Resource previews return by index. Wait until they finish before moving rows.
  if list.get_item_icon(i)==null and library.get_item_mesh(id)!=null:return
  desired.append(id)
 desired.sort_custom(func(a,b):return palette_rank(a,library)<palette_rank(b,library))
 for destination in desired.size():
  for source in range(destination,list.item_count):
   if list.get_item_metadata(source)==desired[destination]:
    if source!=destination:list.move_item(source,destination)
    break

# The browser installs this restorer. Godot reconstructs baked meshes on first
# editor open, using its own mesh API; no student's scene needs to be replaced.
var restored_library_checks={}
func restore_saved_tiles() -> void:
 var filesystem=EditorInterface.get_resource_filesystem()
 if filesystem.is_scanning() or filesystem.is_importing():return
 restore_library_directory(filesystem.get_filesystem())
func restore_library_directory(directory: EditorFileSystemDirectory) -> void:
 if directory==null:return
 for index in range(directory.get_file_count()):
  if directory.get_file_type(index)!="MeshLibrary":continue
  var path=directory.get_file_path(index)
  if not path.ends_with(".tres") or not FileAccess.file_exists(path) or restored_library_checks.has(path):continue
  restored_library_checks[path]=true
  var library=load(path) as MeshLibrary
  if library==null:continue
  var replacements=Shape.ramp_restorations(library)
  if replacements.is_empty():continue
  var hash=FileAccess.get_sha256(path)
  var backup="res://.force-former/tile-mesh-backups/"+path.trim_prefix("res://")+"."+hash+".bak"
  if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup.get_base_dir()))!=OK:continue
  if not FileAccess.file_exists(backup):
   var bytes=FileAccess.get_file_as_bytes(path)
   var copy=FileAccess.open(backup,FileAccess.WRITE)
   if copy==null:continue
   copy.store_buffer(bytes);copy.close()
  var previous={}
  for id in replacements:
   previous[id]=library.get_item_mesh(id)
   library.set_item_mesh(id,replacements[id])
  var temporary=path.get_basename()+".garage-"+str(OS.get_process_id())+".tres"
  var error=ResourceSaver.save(library,temporary)
  if error==OK:error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
  if error!=OK:
   for id in previous:library.set_item_mesh(id,previous[id])
   if FileAccess.file_exists(temporary):DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
   push_warning("ZIP Garage could not save restored tiles in "+path+"; the original library is retained.")
   continue
  print("ZIP Garage restored ",replacements.size()," saved custom tile(s) in ",path,". Original library: ",backup)
 for index in range(directory.get_subdir_count()):
  var child=directory.get_subdir(index)
  if child.get_name().begins_with("."):continue
  restore_library_directory(child)
