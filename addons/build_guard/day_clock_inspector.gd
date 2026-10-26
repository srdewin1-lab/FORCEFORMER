@tool
extends EditorInspectorPlugin
const Forces = preload("res://shared/forces.gd")
const DayDuration = preload("res://addons/build_guard/day_duration.gd")
func _can_handle(object: Object) -> bool:
 return object.get_script() == Forces
func _parse_property(_object: Object,_type: Variant.Type,property: String,_hint: PropertyHint,_hint_text: String,_usage: int,_wide: bool) -> bool:
 if property != "day_duration": return false
 add_property_editor(property,DayDuration.new(),false,"Day duration")
 return true
