@tool
extends GridMap
const Lamp = preload("res://shared/grid_lamp.gd")
@export var keep_tiles_upright = true
@export var preview_lamp_lights = true
var inspection_age = 0.0
var lamp_previews = {}
func _process(delta: float) -> void:
 if not Engine.is_editor_hint(): return
 inspection_age += delta
 if inspection_age < .2: return
 inspection_age = 0
 if keep_tiles_upright: straighten_tiles()
 refresh_lamp_previews()
func refresh_lamp_previews() -> void:
 # Unowned children are editor previews, never saved into the student's scene.
 var cells = get_used_cells_by_item(7) if preview_lamp_lights else []
 for cell in lamp_previews.keys():
  if cell not in cells:
   if is_instance_valid(lamp_previews[cell]):
    remove_child(lamp_previews[cell])
    lamp_previews[cell].queue_free()
   lamp_previews.erase(cell)
 for cell in cells:
  if not lamp_previews.has(cell) or not is_instance_valid(lamp_previews[cell]):
   var lamp = Node3D.new()
   lamp.name = "LampPreview"
   lamp.set_script(Lamp)
   add_child(lamp)
   lamp_previews[cell] = lamp
  var lamp = lamp_previews[cell]
  lamp.position = map_to_local(cell)
  lamp.basis = get_basis_with_orthogonal_index(get_cell_item_orientation(cell))
func upright_index(original: Basis) -> int:
 var best = 0
 var score = -INF
 for turn in range(4):
  var candidate = Basis(Vector3.UP,turn*PI/2)
  var agreement = candidate.x.dot(original.x)+candidate.z.dot(original.z)
  if agreement > score:
   score = agreement
   best = get_orthogonal_index_from_basis(candidate)
 return best
func straighten_tiles() -> int:
 var changed = 0
 for cell in get_used_cells():
  var index = get_cell_item_orientation(cell)
  var original = get_basis_with_orthogonal_index(index)
  if original.y.dot(Vector3.UP) > .99: continue
  set_cell_item(cell,get_cell_item(cell),upright_index(original))
  changed += 1
 return changed
