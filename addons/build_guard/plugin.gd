@tool
extends EditorPlugin
var grid: GridMap
var day_clock_inspector: EditorInspectorPlugin
func _enter_tree() -> void:
 day_clock_inspector = preload("res://addons/build_guard/day_clock_inspector.gd").new()
 add_inspector_plugin(day_clock_inspector)
func _exit_tree() -> void:
 remove_inspector_plugin(day_clock_inspector)
func _handles(object: Object) -> bool: return object is GridMap
func _edit(object: Object) -> void: grid = object as GridMap
func _forward_3d_gui_input(_camera: Camera3D,event: InputEvent) -> int:
 if not is_instance_valid(grid) or not grid.get("keep_tiles_upright"): return EditorPlugin.AFTER_GUI_INPUT_PASS
 if event is InputEventKey and event.pressed and not event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed:
  # S remains the horizontal turn. Both mouse and keyboard freelook allow A/D.
  if event.keycode in [KEY_A,KEY_D] and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
   return EditorPlugin.AFTER_GUI_INPUT_STOP
 return EditorPlugin.AFTER_GUI_INPUT_PASS
