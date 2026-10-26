@tool
extends Node
# Each control is an explicit, saved numeric override of a Condition parameter.
const SPECS = {
 "gravity_strength":["Gravity","Pull strength",0.0,19.6,.1,9.8,"m/s²"],
 "motion_resistance":["Motion","Resistance",0.0,1.2,.01,0.0,"/s"],
 "matter_rebound":["Matter","Rebound",0.0,1.0,.01,.35,""],
 "light_strength":["Light","Light strength",0.0,2.0,.05,1.0,"×"],
 "sound_strength":["Sound","Signal strength",0.0,2.0,.05,1.0,"×"],
 "wind_strength":["Weather","Wind strength",0.0,2.0,.05,1.0,"×"],
 "rain_rate":["Weather","Rainfall rate",0.0,2.0,.05,1.0,"×"],
 "time_rate":["Time","Time rate",.25,2.0,.05,1.0,"×"]
}
@export_storage var family = "Gravity"
@export_storage var card_id = ""
@export_multiline var imported_laws: String:
 get:
  if get_parent()!=null and get_parent().has_method("law_summary"):return get_parent().law_summary(card_id)
  return "Imported laws are kept in Condition.json."
@export_storage var overrides: Dictionary = {}
@export_group("Pull strength","gravity_strength_")
## Replace this card's imported numeric schedule. Untick to restore it. Law words are unchanged.
@export var gravity_strength_use_godot_value: bool:
 get: return overrides.has("gravity_strength")
 set(value): set_enabled("gravity_strength",value)
@export_range(0,19.6,0.1,"suffix:m/s²") var gravity_strength_value: float:
 get: return float(overrides.get("gravity_strength",scheduled_value("gravity_strength")))
 set(value): set_value("gravity_strength",value)
@export_group("Resistance","motion_resistance_")
@export var motion_resistance_use_godot_value: bool:
 get: return overrides.has("motion_resistance")
 set(value): set_enabled("motion_resistance",value)
@export_range(0,1.2,0.01,"suffix:/s") var motion_resistance_value: float:
 get: return float(overrides.get("motion_resistance",scheduled_value("motion_resistance")))
 set(value): set_value("motion_resistance",value)
@export_group("Rebound","matter_rebound_")
@export var matter_rebound_use_godot_value: bool:
 get: return overrides.has("matter_rebound")
 set(value): set_enabled("matter_rebound",value)
@export_range(0,1,0.01,"suffix:") var matter_rebound_value: float:
 get: return float(overrides.get("matter_rebound",scheduled_value("matter_rebound")))
 set(value): set_value("matter_rebound",value)
@export_group("Light strength","light_strength_")
@export var light_strength_use_godot_value: bool:
 get: return overrides.has("light_strength")
 set(value): set_enabled("light_strength",value)
@export_range(0,2,0.05,"suffix:×") var light_strength_value: float:
 get: return float(overrides.get("light_strength",scheduled_value("light_strength")))
 set(value): set_value("light_strength",value)
@export_group("Signal strength","sound_strength_")
@export var sound_strength_use_godot_value: bool:
 get: return overrides.has("sound_strength")
 set(value): set_enabled("sound_strength",value)
@export_range(0,2,0.05,"suffix:×") var sound_strength_value: float:
 get: return float(overrides.get("sound_strength",scheduled_value("sound_strength")))
 set(value): set_value("sound_strength",value)
@export_group("Wind strength","wind_strength_")
@export var wind_strength_use_godot_value: bool:
 get: return overrides.has("wind_strength")
 set(value): set_enabled("wind_strength",value)
@export_range(0,2,0.05,"suffix:×") var wind_strength_value: float:
 get: return float(overrides.get("wind_strength",scheduled_value("wind_strength")))
 set(value): set_value("wind_strength",value)
@export_group("Rainfall rate","rain_rate_")
@export var rain_rate_use_godot_value: bool:
 get: return overrides.has("rain_rate")
 set(value): set_enabled("rain_rate",value)
@export_range(0,2,0.05,"suffix:×") var rain_rate_value: float:
 get: return float(overrides.get("rain_rate",scheduled_value("rain_rate")))
 set(value): set_value("rain_rate",value)
@export_group("Time rate","time_rate_")
@export var time_rate_use_godot_value: bool:
 get: return overrides.has("time_rate")
 set(value): set_enabled("time_rate",value)
@export_range(0.25,2,0.05,"suffix:×") var time_rate_value: float:
 get: return float(overrides.get("time_rate",scheduled_value("time_rate")))
 set(value): set_value("time_rate",value)
func keys() -> Array:
 return SPECS.keys().filter(func(key):return SPECS[key][0]==family)
func scheduled_value(key: String) -> float:
 if get_parent()!=null and get_parent().has_method("scheduled_value"): return get_parent().scheduled_value(key,card_id)
 return float(SPECS[key][5])
func set_enabled(key: String,value: bool) -> void:
 if value:
  if not overrides.has(key):overrides[key]=scheduled_value(key)
 else: overrides.erase(key)
 notify_property_list_changed()
func set_value(key: String,value: float) -> void:
 if overrides.has(key) and is_finite(value):overrides[key]=clampf(value,SPECS[key][2],SPECS[key][3])
func _validate_property(property: Dictionary) -> void:
 if property.name in ["imported_laws"]:
  property.usage=PROPERTY_USAGE_EDITOR|PROPERTY_USAGE_READ_ONLY
 for key in SPECS:
  if property.name.begins_with(key+"_"):
   if SPECS[key][0]!=family:property.usage=PROPERTY_USAGE_NONE
   elif property.name==key+"_value" and not overrides.has(key):property.usage|=PROPERTY_USAGE_READ_ONLY
func active_overrides() -> Dictionary:
 var out = {}
 for key in keys():
  if overrides.has(key) and is_finite(float(overrides[key])):out[key]=clampf(float(overrides[key]),SPECS[key][2],SPECS[key][3])
 return out
