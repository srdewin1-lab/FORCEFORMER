@tool
extends EditorProperty
var slider = HSlider.new()
var seconds = SpinBox.new()
var duration = Label.new()
func _init() -> void:
 var content = VBoxContainer.new()
 var row = HBoxContainer.new()
 slider.min_value = 30
 slider.max_value = 1800
 slider.step = 30
 slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 slider.custom_minimum_size.x = 110
 slider.tooltip_text = "Base length of a 24-hour day. The imported Time rate and clock laws still apply."
 seconds.min_value = 30
 seconds.max_value = 1800
 seconds.step = 30
 seconds.suffix = "s"
 seconds.custom_minimum_size.x = 90
 row.add_child(slider)
 row.add_child(seconds)
 content.add_child(row)
 content.add_child(duration)
 add_child(content)
 set_bottom_editor(content)
 add_focusable(slider)
 add_focusable(seconds.get_line_edit())
 slider.value_changed.connect(change_value)
 seconds.value_changed.connect(change_value)
func change_value(value: float) -> void:
 slider.set_value_no_signal(value)
 seconds.set_value_no_signal(value)
 describe(value)
 emit_changed(get_edited_property(),value)
func describe(value: float) -> void:
 duration.text = "%.1f min at Time rate 1×" % (value/60.0)
func _update_property() -> void:
 var object = get_edited_object()
 if object == null: return
 var value = float(object.get(get_edited_property()))
 slider.set_value_no_signal(value)
 seconds.set_value_no_signal(value)
 describe(value)
func _set_read_only(value: bool) -> void:
 slider.editable = not value
 seconds.editable = not value
