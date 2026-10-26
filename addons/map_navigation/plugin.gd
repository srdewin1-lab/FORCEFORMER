@tool
extends EditorPlugin

var toolbar: HBoxContainer
var fly_button: Button
var hint: Label

func _enter_tree() -> void:
 toolbar = HBoxContainer.new()
 toolbar.add_theme_constant_override("separation",4)
 fly_button = add_button("Navigate", "Move the editor camera without holding a mouse button. WASD move; Q down; E up; Escape returns to editing.", start_navigation)
 add_button("A", "Frame the starting platform.", func(): frame_node("Beacons/AOrb"))
 add_button("Map", "Frame the terrain from above.", frame_map)
 add_button("B", "Frame the destination platform.", func(): frame_node("Beacons/BOrb"))
 add_button("−", "Zoom the editor view out.", func(): zoom_view(1.0/1.5))
 add_button("+", "Zoom the editor view in.", func(): zoom_view(1.5))
 add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,toolbar)
 hint = Label.new()
 hint.text = "WASD move · Q down · E up · Shift faster · Esc to edit"
 hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
 hint.add_theme_color_override("font_color",Color.WHITE)
 hint.add_theme_color_override("font_shadow_color",Color.BLACK)
 hint.add_theme_constant_override("shadow_offset_x",2)
 hint.add_theme_constant_override("shadow_offset_y",2)
 hint.position = Vector2(12,64)*EditorInterface.get_editor_scale()
 hint.hide()
 var surface = editor_surface()
 if surface != null: surface.add_child(hint)
 set_process(true)


func add_button(title: String,description: String,action: Callable) -> Button:
 var button = Button.new()
 button.text = title
 button.tooltip_text = description
 button.pressed.connect(action)
 toolbar.add_child(button)
 return button

func editor_surface() -> Control:
 var viewport = EditorInterface.get_editor_viewport_3d(0)
 if viewport == null: return null
 var holder = viewport.get_parent().get_parent()
 for child in holder.get_children():
  if child is Control and child.focus_mode == Control.FOCUS_ALL and not child is SubViewportContainer:
   return child
 return null

func shortcut(path: String) -> void:
 var surface = editor_surface()
 var binding = EditorInterface.get_editor_settings().get_shortcut(path)
 if binding == null and path == "spatial_editor/focus_aabb":
  binding = EditorInterface.get_editor_settings().get_shortcut("spatial_editor/focus_selection")
 if surface == null or binding == null or binding.events.is_empty(): return
 surface.grab_focus()
 var event = binding.events[0].duplicate() as InputEventKey
 if event == null: return
 event.pressed = true
 surface.gui_input.emit(event)
 event = event.duplicate()
 event.pressed = false
 surface.gui_input.emit(event)

func start_navigation() -> void:
 var camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
  var surface = editor_surface()
  var changed = false
  for menu in surface.find_children("*","MenuButton",true,false):
   var popup = menu.get_popup()
   for index in range(popup.item_count):
    if popup.get_item_text(index) == "Perspective":
     popup.id_pressed.emit(popup.get_item_id(index))
     changed = true
     break
   if changed: break
  if not changed: shortcut("spatial_editor/switch_perspective_orthogonal")
  await get_tree().process_frame
  await get_tree().process_frame
 shortcut("spatial_editor/freelook_toggle")

func zoom_view(factor: float) -> void:
 var surface = editor_surface()
 if surface == null: return
 var gesture = InputEventMagnifyGesture.new()
 gesture.factor = factor
 gesture.position = surface.size*.5
 surface.gui_input.emit(gesture)

func frame_bounds(bounds: AABB) -> void:
 var root = EditorInterface.get_edited_scene_root()
 if not root is Node3D: return
 shortcut("spatial_editor/top_view")
 await get_tree().process_frame
 # Temporary, invisible framing points; never saved into the student's scene.
 var helper = MeshInstance3D.new()
 var box = BoxMesh.new()
 box.size = bounds.size.max(Vector3.ONE)
 helper.mesh = box
 var material = StandardMaterial3D.new()
 material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 material.albedo_color = Color(0,0,0,0)
 helper.material_override = material
 helper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 root.add_child(helper)
 helper.owner = root
 helper.global_position = bounds.get_center()
 var selection = EditorInterface.get_selection()
 selection.clear()
 selection.add_node(helper)
 await get_tree().process_frame
 await get_tree().process_frame
 shortcut("spatial_editor/focus_aabb")
 await get_tree().process_frame
 await get_tree().process_frame
 var camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
 var extent = Vector2.ZERO
 var basis = camera.global_basis.inverse()
 for x in [bounds.position.x,bounds.end.x]:
  for y in [bounds.position.y,bounds.end.y]:
   for z in [bounds.position.z,bounds.end.z]:
    var offset = basis*(Vector3(x,y,z)-bounds.get_center())
    extent = extent.max(Vector2(absf(offset.x),absf(offset.y))*2.0)
 var viewport_size = Vector2(EditorInterface.get_editor_viewport_3d(0).size)
 var height = maxf(extent.y,extent.x/maxf(.1,viewport_size.x/viewport_size.y))*1.3
 zoom_view(camera.size/maxf(2.0,height))
 selection.clear()
 var terrain = root.get_node_or_null("Terrain")
 if terrain != null: selection.add_node(terrain)
 helper.queue_free()

func frame_node(path: String) -> void:
 var root = EditorInterface.get_edited_scene_root()
 if root == null: return
 var target = root.get_node_or_null(path) as Node3D
 if target == null: return
 await frame_bounds(AABB(target.global_position-Vector3(4,2,4),Vector3(8,4,8)))

func frame_map() -> void:
 var root = EditorInterface.get_edited_scene_root()
 if root == null: return
 var terrain = root.get_node_or_null("Terrain") as GridMap
 if terrain == null: return
 var bounds = AABB(terrain.global_position,Vector3.ONE)
 var dunes = root.get_node_or_null("Dunes")
 for cell in terrain.get_used_cells():
  var point = terrain.to_global(terrain.map_to_local(cell))
  if dunes != null and not dunes.allows(dunes.to_local(point)): continue
  bounds = bounds.expand(point)
 for path in ["A","B"]:
  var marker = root.get_node_or_null(path) as Node3D
  if marker != null: bounds = bounds.expand(marker.global_position)
 shortcut("spatial_editor/top_view")
 await frame_bounds(bounds.grow(3))

func _process(_delta: float) -> void:
 var flying = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
 if is_instance_valid(hint): hint.visible = flying
 if is_instance_valid(fly_button): fly_button.text = "Esc to edit" if flying else "Navigate"

func _exit_tree() -> void:
 if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
  shortcut("spatial_editor/freelook_toggle")
 if is_instance_valid(hint): hint.queue_free()
 if is_instance_valid(toolbar):
  remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,toolbar)
  toolbar.queue_free()
