@tool
extends Node
const Compiler = preload("res://shared/compiler.gd")
const Controls = preload("res://shared/force_controls.gd")
@export_range(0,23,.25) var preview_hour = 0.0
# Retain adjustments to cards temporarily absent from a replacement Condition.
@export_storage var saved_card_overrides: Dictionary = {}
var synced_stamp = -2
var check_age = 0.0
@export_group("Day clock")
## Use Day duration as the base day length. Time force laws and Time rate still apply.
@export var use_godot_duration = false
## Seconds for one full day at a consistent Time rate of 1x.
@export_range(30,1800,30,"suffix:s") var day_duration = 240.0
# Read legacy scenes without dropping their saved clock settings.
@export_storage var preview_clock_enabled: bool:
 get: return use_godot_duration
 set(value): use_godot_duration = value
@export_storage var preview_day_seconds: float:
 get: return day_duration
 set(value): day_duration = value
var plot
var panel: PanelContainer
var readout: Label
var source_compiler
var source_stamp = -1
func _get_property_list() -> Array[Dictionary]:
 return [{"name":"How to adjust forces","type":TYPE_STRING,"usage":PROPERTY_USAGE_EDITOR|PROPERTY_USAGE_READ_ONLY}]
func _get(property: StringName):
 if property=="How to adjust forces":return "Expand Forces in the Scene tree. Each entry uses its imported card name. Its laws are read-only; supported numbers have bounded controls. Tick Use Godot Value to adjust a number. Save the scene before Play to keep it. Remote Inspector edits last only for that run."
 return null
func source() -> Object:
 var root = get_parent()
 var path = root.scene_file_path.get_base_dir().path_join("Condition.json") if root!=null and not root.scene_file_path.is_empty() else "res://Condition.json"
 var stamp=FileAccess.get_modified_time(path)
 if source_compiler==null or source_stamp!=stamp:
  source_compiler=Compiler.new()
  source_compiler.load_catalogue()
  source_compiler.set_world(source_compiler.read_json(path))
  source_stamp=stamp
 return source_compiler
func _ready() -> void:
 sync_cards()
 set_process(Engine.is_editor_hint())
func _process(delta: float) -> void:
 check_age+=delta
 if check_age<.5:return
 check_age=0
 source()
 if synced_stamp!=source_stamp:sync_cards()
func card_data(id: String) -> Dictionary:
 for card in source().world.get("forces",[]):
  if str(card.card)==id:return card
 return {}
func sync_cards() -> void:
 var c=source()
 if not c.errors.is_empty() or c.world.is_empty():return
 var available=get_children().filter(func(child):return child.get_script()==Controls)
 var used=[]
 var serial={}
 for card in c.world.forces:
  var id=str(card.card)
  var family=str(card.template).capitalize()
  var control=null
  for child in available:
   if child.card_id==id:control=child;break
  if control==null:
   # Migrate the seven legacy family entries without resetting their values.
   for child in available:
    if child.card_id.is_empty() and child.family==family and not used.has(child):control=child;break
  if control==null:
   control=Controls.new()
   control.family=family
   control.card_id=id
   control.overrides=saved_card_overrides.get(id,{}).duplicate(true)
   add_child(control)
   control.owner=get_parent().owner if get_parent().owner!=null else get_parent()
  control.card_id=id
  control.family=family
  var title=str(card.get("name",family)).validate_node_name().strip_edges()
  if title.is_empty():title=family
  serial[title]=int(serial.get(title,0))+1
  control.name=title if serial[title]==1 else title+" · "+str(serial[title])
  control.notify_property_list_changed()
  used.append(control)
 for child in available:
  if used.has(child):continue
  if not child.card_id.is_empty():saved_card_overrides[child.card_id]=child.overrides.duplicate(true)
  remove_child(child)
  child.queue_free()
 for index in range(used.size()):move_child(used[index],index)
 synced_stamp=source_stamp
func scheduled_value(key: String,id: String="") -> float:
 var c=source()
 if c.world.is_empty():return float(Controls.SPECS[key][5])
 var at=plot.hour if plot!=null and not Engine.is_editor_hint() else preview_hour
 if not id.is_empty():return c.card_tuned(key,card_data(id),at)
 var spec=c.TUNING[key]
 var properties={"gravity_strength":"gravity.vector","motion_resistance":"body.causes","matter_rebound":"body.meeting","light_strength":"sun.colour","sound_strength":"sound.propagates","wind_strength":"wind.path","rain_rate":"cloud.verb","time_rate":"clock.rate_pattern"}
 return c.tuned(key,spec[0],properties[key],at)
func word(family: String,key) -> String:
 if key is Array:
  var words=[]
  for value in key:words.append(word(family,value))
  return ", ".join(words)
 for option in source().families.get(family,[]):
  if str(option.key)==str(key):return str(option.get("label",key)).to_lower()
 return str(key).replace("_"," ")
func law_summary(id: String) -> String:
 var c=source()
 var card=card_data(id)
 if card.is_empty():return "Imported laws are kept in Condition.json."
 var at=plot.hour if plot!=null and not Engine.is_editor_hint() else preview_hour
 var lines=["At %02d:%02d · %s"%[int(at),int(fmod(at,1)*60),str(card.template).capitalize()]]
 for law in c.laws:
  if law.bundle!=card.template or law.tier=="name":continue
  var chosen={}
  for entry in card.laws:
   if entry.id==law.id and entry.from_hour<=at and (chosen.is_empty() or entry.from_hour>=chosen.from_hour):chosen=entry
  var slots=c.defaults(law) if chosen.is_empty() else chosen.slots
  var sentence=str(law.sentence)
  for slot in law.slots:
   var start=sentence.find("[")
   var end=sentence.find("]",start)
   if start<0 or end<0:break
   sentence=sentence.left(start)+word(slot.family,slots.get(slot.key,slot.default))+sentence.substr(end+1)
  lines.append(sentence.capitalize().substr(0,1)+sentence.substr(1))
 lines.append("All imported law changes and parameter keyframes are retained.")
 return "\n".join(lines)
func overrides() -> Dictionary:
 var out={}
 for child in get_children():
  if child.has_method("active_overrides") and not child.card_id.is_empty():
   var values=child.active_overrides()
   if not values.is_empty():out[child.card_id]=values
 return out
func apply_to(compiler) -> void:
 if synced_stamp==-2:sync_cards()
 var next=overrides()
 var changed=compiler.card_numeric_overrides!=next
 compiler.card_numeric_overrides=next
 if plot!=null:
  plot.preview_seconds=day_duration if use_godot_duration else float(compiler.world.day_length_seconds)
  if changed and not plot.compiled_report.is_empty():plot.compiled_report=plot.compatibility_report()
func bind_plot(value) -> void:
 plot=value
 apply_to(plot.compiler)
 var button=Button.new()
 button.text="Forces"
 button.focus_mode=Control.FOCUS_NONE
 button.position=Vector2(1116,20)
 button.size=Vector2(140,38)
 button.tooltip_text="Live values. Select the named cards under Forces in the Inspector to adjust supported numbers."
 plot.get_node("HUD").add_child(button)
 panel=PanelContainer.new()
 panel.position=Vector2(864,66)
 panel.custom_minimum_size=Vector2(392,0)
 var style=StyleBoxFlat.new()
 style.bg_color=Color(.07,.09,.11,.88)
 style.set_corner_radius_all(12)
 style.content_margin_left=18
 style.content_margin_right=18
 style.content_margin_top=16
 style.content_margin_bottom=16
 panel.add_theme_stylebox_override("panel",style)
 readout=Label.new()
 readout.add_theme_font_size_override("font_size",16)
 panel.add_child(readout)
 panel.hide()
 plot.get_node("HUD").add_child(panel)
 button.pressed.connect(func():panel.visible=not panel.visible)
func update_values() -> void:
 if plot==null or plot.current.is_empty():return
 var p=plot.wheel.parameters
 if p.is_empty():return
 var wind="off"
 if p.weather.wind_enabled:wind="%s · %.2f×"%[str(p.weather.wind_path).capitalize(),float(p.weather.wind_strength)]
 var gravity="off"
 if p.gravity.enabled:
  var dir:Vector3=p.gravity.vector
  gravity="%.2f m/s² · %s"%[float(p.gravity.strength),"down" if dir.y<-.9 else "up" if dir.y>.9 else str(dir)]
 var local_values=overrides()
 var origin="Condition timeline" if local_values.is_empty() else "Cards with Godot overrides: "+str(local_values.size())
 if use_godot_duration:origin+="\nDay duration: %ds · Imported base: %ds"%[int(day_duration),int(plot.compiler.world.day_length_seconds)]
 readout.text="FORCES · %02d:%02d\n\nGravity    %s\nWind       %s\nResistance %.2f\nRebound    %.2f\nLight      %.2f×\nSound      %.2f×\nRainfall   %.2f×\nTime       %.2f×\n\n%s\n\nWheel Assisted: %s\nFalling things use the full condition.\n\nAdjust under Forces in the Inspector.\nSave Local scene edits before Play.\nRemote edits last for this run only."%[int(plot.hour),int(fmod(plot.hour,1)*60),gravity,wind,float(p.body.motion_resistance),float(p.body.rebound),float(plot.compiler.tuned("light_strength","light","sun.colour",plot.hour)),float(p.sound.strength),float(p.weather.rain_rate),float(p.clock.pace),origin,"on" if plot.wheel.ground_adhesion else "off"]
