extends RefCounted
# Only keys, allowed subsets and catalogue writes enter the resolver. No sentences.
var laws: Array = []
var families: Dictionary = {}
var numbers: Dictionary = {}
var world: Dictionary = {}
# Explicit Godot Inspector overrides; empty preserves the imported timeline.
var numeric_overrides: Dictionary = {}
# Keyed by the imported card ID; preserves the winner of overlapping laws.
var card_numeric_overrides: Dictionary = {}
var errors: Array = []
var planned: Array = []
var by_id: Dictionary = {}
var default_entries: Array = []
var cached_sun_events: Array = []
var honoured_keys: Dictionary = {}
func read_json(path: String):
 if not FileAccess.file_exists(path): return null
 return JSON.parse_string(FileAccess.get_file_as_string(path))
func load_catalogue() -> bool:
 laws = read_json("res://catalogue/laws.json")
 families = read_json("res://catalogue/families.json")
 numbers = read_json("res://catalogue/lowering.json")
 honoured_keys.clear()
 for family in families:
  honoured_keys[family] = {}
  for option in families[family]: honoured_keys[family][option.key] = option.status == "honoured"
 for law in laws: by_id[law.id] = law
 for law in laws:
  if law.tier == "name": continue
  var slots = defaults(law)
  if not silent(law,slots): default_entries.append({"law":law,"slots":slots,"implicit":true,"hour":0,"index":-1,"writes":writes(law,slots)})
 return not laws.is_empty()
func defaults(law: Dictionary) -> Dictionary:
 var result = {}
 for slot in law.slots: result[slot.key] = slot.default.duplicate() if slot.default is Array else slot.default
 return result
func honoured(family: String,key: String) -> bool:
 return honoured_keys.get(family,{}).get(key,false)
func silent(law: Dictionary,slots: Dictionary) -> bool:
 if law.status != "honoured": return true
 for slot in law.slots:
  if slot.get("selection","") != "multiple" and not honoured(slot.family,str(slots.get(slot.key,slot.default))): return true
 return false
func set_world(data) -> bool:
 errors.clear()
 planned.clear()
 if not data is Dictionary:
  errors.append("Condition must be an object.")
  return false
 if data.get("format") != "world-as-is/2": errors.append("Requires a v2 condition.")
 if not (data.get("day_length_seconds") is float or data.get("day_length_seconds") is int) or data.day_length_seconds <= 0: errors.append("Day length must be a positive number of seconds.")
 if not data.get("forces") is Array:
  errors.append("Forces must be an array.")
  return false
 data = data.duplicate(true)
 for card in data.forces:
  if not card is Dictionary or card.get("template") != "light" or not card.get("laws") is Array or card.get("sun_timing") == 1: continue
  for id in ["light.sunrise","light.sunset"]:
   var existing = card.laws.filter(func(fill):return fill is Dictionary and fill.get("id") == id)
   for fill in existing:
    if fill.get("slots") is Dictionary and not fill.slots.has("at_hour"): fill.slots.at_hour = "%02d" % int(fill.get("from_hour",0))
   if existing.is_empty(): card.laws.append({"id":id,"from_hour":0,"slots":{"verb":"rise" if id == "light.sunrise" else "fall","relative_location":"above" if id == "light.sunrise" else "below","at_hour":"06" if id == "light.sunrise" else "18"}})
  card.sun_timing = 1
 var ids = {}
 for card in data.forces:
  if not card is Dictionary or not card.get("laws") is Array:
   errors.append("Invalid force.")
   continue
  if ids.has(card.get("card","")) or str(card.get("card","")).is_empty(): errors.append("Force IDs must be unique.")
  ids[card.get("card","")] = true
  validate_parameters(card)
  var scheduled = {}
  for fill in card.laws:
   if not fill is Dictionary or not by_id.has(fill.get("id","")):
    errors.append("Unknown law.")
    continue
   var law = by_id[fill.id]
   if law.bundle != card.get("template") or law.tier == "name": errors.append("Law belongs to another force.")
   var h = fill.get("from_hour",-1)
   if not (h is float or h is int) or h < 0 or h > 23 or floor(h) != h: errors.append("Invalid scheduled hour.")
   var signature = str(fill.id)+"@"+str(h)
   if scheduled.has(signature): errors.append("Duplicate schedule.")
   scheduled[signature] = true
   if not fill.get("slots") is Dictionary:
    errors.append("Slots must be an object.")
    continue
   var keys = []
   for slot in law.slots:
    keys.append(slot.key)
    var value = fill.slots.get(slot.key,slot.default)
    if (slot.get("selection","") == "multiple" and not value is Array) or (slot.get("selection","") != "multiple" and not value is String):
     errors.append("Wrong slot type: "+slot.key)
     continue
    for key in value if value is Array else [value]:
     if not slot.allowed.has(key): errors.append("%s: %s outside allowed subset %s" % [law.id,str(key),str(slot.allowed)])
     elif not honoured(slot.family,key): planned.append({"law":law.id,"key":key,"from_hour":h,"status":"planned"})
   for key in fill.slots:
    if not keys.has(key): errors.append("Unknown slot: "+key)
   if law.status != "honoured": planned.append({"law":law.id,"key":law.id,"from_hour":h,"status":"planned"})
 if not errors.is_empty(): return false
 world = data.duplicate(true)
 cached_sun_events.clear()
 return true
func writes(law: Dictionary,slots: Dictionary) -> Array:
 var out = law.get("writes",[]).duplicate()
 for slot in law.get("option_writes",{}):
  var value = slots.get(slot)
  for key in value if value is Array else [value]: out.append_array(law.option_writes[slot].get(key,[]))
 return out
func rank(c: Dictionary) -> Array:
 return [c.get("source_hour",c.hour),{"constant":0,"relation":1,"gate":2}.get(c.law.tier,-1),c.law.order,c.index]
func later(a: Dictionary,b: Dictionary) -> bool:
 var x = rank(a)
 var y = rank(b)
 for i in range(4):
  if x[i] != y[i]: return x[i] > y[i]
 return false
func force_start(card: Dictionary) -> int:
 return int(card.get("active_from_hour",card.get("timing_anchor_hour",0)))
func force_active(card: Dictionary,hour: float) -> bool:
 if hour >= force_start(card): return true
 if card.has("timing_wraps_midnight"): return bool(card.timing_wraps_midnight)
 var synthetic = card.get("timing_synthetic",{})
 if not synthetic.get("laws",[]).is_empty() or not synthetic.get("parameters",[]).is_empty(): return true
 for row in card.get("laws",[])+card.get("parameter_changes",[]):
  if row.from_hour > 0 and row.from_hour < force_start(card): return true
 return false
func family_active(family: String,hour: float) -> bool:
 for card in world.forces:
  if card.template == family and force_active(card,hour): return true
 return false
func entries(hour: float) -> Array:
 var out = []
 for i in range(world.forces.size()):
  var card = world.forces[i]
  if not force_active(card,hour): continue
  for fill in card.laws:
   if fill.from_hour > hour: continue
   var law = by_id[fill.id]
   var slots = defaults(law)
   slots.merge(fill.slots,true)
   if not silent(law,slots): out.append({"law":law,"slots":slots,"hour":fill.from_hour,"index":i,"card":card,"implicit":false,"writes":writes(law,slots)})
  if card.has("active_from_hour"):
   for law in laws:
    if law.bundle != card.template or law.tier == "name": continue
    var present = false
    for row in card.laws:
     if row.id == law.id and row.from_hour <= hour: present = true
    if present: continue
    var slots = defaults(law)
    if not silent(law,slots): out.append({"law":law,"slots":slots,"hour":force_start(card),"index":i,"card":card,"implicit":true,"writes":writes(law,slots)})
 return out
func scalar(b: Dictionary,key: String) -> float:
 return b.get("velocity",Vector3.ZERO).length() if key == "speed" else float(b.get(key,1 if key == "scale" else 0))
func quality_matches(key: String,b: Dictionary,bodies: Array,medians: Dictionary={}) -> bool:
 var comparative = {"heavier":["mass",1],"lighter":["mass",-1],"bigger":["scale",1],"smaller":["scale",-1],"faster":["speed",1],"slower":["speed",-1],"loud":["sonority",1],"quiet":["sonority",-1]}
 if comparative.has(key):
  var property = comparative[key][0]
  if not medians.has(property):
   var values = []
   for body in bodies: values.append(scalar(body,property))
   values.sort()
   medians[property] = 0.0 if values.is_empty() else (values[int((values.size()-1)/2)]+values[int(values.size()/2)])/2.0
  var middle = medians[property]
  return comparative[key][1]*(scalar(b,comparative[key][0])-middle) > 0.000000001
 match key:
  "all": return true
  "solid","liquid","vaporous": return b.get("state","solid") == key
  "mobile": return b.get("mobility",1)>0
  "immobile": return b.get("mobility",1)<=0
  "visible": return b.get("visibility",1)>0
  "invisible": return b.get("visibility",1)<=0
  "glowing": return b.get("brightness",0)>0
  "shaded": return not b.get("sunlit",true)
  "round": return b.get("shape","round") == "round"
 return false
func matches(c: Dictionary,b: Dictionary,ctx: Dictionary) -> bool:
 if not ["gravity","motion","matter"].has(c.law.bundle) or b.is_empty(): return true
 var things = c.slots.get("things","things")
 var rq = c.slots.get("relative_quality_1",c.slots.get("relative_quality","all"))
 return honoured("things",things) and honoured("relative quality",rq) and (things == "things" or b.get("kind") == things) and quality_matches(rq,b,ctx.get("bodies",[]),ctx.get("_medians",{}))
# A context lives for one snapshot/frame. Index laws once, and cache only
# properties without body-scoped candidates. Body predicates still run per body.
func prepare_context(hour: float,ctx: Dictionary) -> void:
 if ctx.get("_hour",-1.0) == hour: return
 ctx._hour = hour
 ctx._medians = {}
 ctx._resolved = {}
 ctx._by_property = {}
 ctx._sun = {}
 ctx._environment = {}
 for c in (ctx.entries if ctx.has("entries") else entries(hour)):
  for property in c.writes:
   if not ctx._by_property.has(property): ctx._by_property[property] = []
   ctx._by_property[property].append(c)
func resolve(property: String,hour: float,b: Dictionary={},ctx: Dictionary={}) -> Dictionary:
 prepare_context(hour,ctx)
 if ctx._resolved.has(property): return ctx._resolved[property]
 var winner = {}
 var scoped = false
 for c in ctx._by_property.get(property,[]):
  if ["gravity","motion","matter"].has(c.law.bundle): scoped = true
  if matches(c,b,ctx) and (winner.is_empty() or later(c,winner)): winner = c
 if winner.is_empty():
  for c in default_entries:
   if family_active(c.law.bundle,hour) and c.writes.has(property) and (winner.is_empty() or c.law.order < winner.law.order): winner = c
 if not scoped: ctx._resolved[property] = winner
 return winner
func fill(property: String,hour: float,b: Dictionary={},ctx: Dictionary={}) -> Dictionary:
 return resolve(property,hour,b,ctx).get("slots",{})
func noise(seed: int,tick: int) -> float:
 var n = ((seed ^ 0x45d9f3b)*(tick ^ 0x27d4eb2d)) & 0xffffffff
 n = (n ^ (n >> 16)) & 0xffffffff
 n = (n*0x45d9f3b) & 0xffffffff
 n = (n ^ (n >> 16)) & 0xffffffff
 return float(n)/4294967296.0
func location(key: String,b: Dictionary,ctx: Dictionary) -> Vector3:
 var toward = (ctx.get("listener",Vector3(0,1,0))-b.get("position",Vector3.ZERO)).normalized()
 var right = ctx.get("right",Vector3.RIGHT)
 var forward = ctx.get("forward",Vector3.FORWARD)
 return {"above":Vector3.UP,"below":Vector3.DOWN,"left":-right,"right":right,"forward":forward,"behind":-forward,"nearby":toward,"far_away":-toward,"in_earshot":toward}.get(key,Vector3.ZERO)
func vector_path(key: String,base: Vector3,time: float,seed: int=1,plane: String="xyz") -> Vector3:
 var axis = base.normalized()
 var side = Vector3(-axis.y,axis.x,0).normalized() if plane == "xy" else axis.cross(Vector3.BACK if abs(axis.y)>.9 else Vector3.UP).normalized()
 var phase = time*PI/2+seed*.37
 var amount = {"straight":0,"zig_zag":.6 if sin(phase)>=0 else -.6,"wave":sin(phase)*.6,"random":(noise(seed,int(floor(time)))-.5)*2}.get(key,0)
 return (axis+side*amount).normalized()
func clock_rate(pattern: String,hour: float,day: int=0) -> float:
 var low = numbers.clock.pattern_rate_range[0]
 var high = numbers.clock.pattern_rate_range[1]
 var t = clamp(hour/23.0,0,1)
 var value = {"consistent":1,"increasing":lerp(low,high,t),"decreasing":lerp(high,low,t),"random":lerp(low,high,noise(day+1,int(floor(hour))))}.get(pattern,1)
 return clamp(value,numbers.clock.speed_limits[0],numbers.clock.speed_limits[1])
func clock_factor(path: String,elapsed: float,seconds: float) -> float:
 var phase = elapsed/seconds*TAU
 return {"straight":1,"zig_zag":1 if sin(phase)>=0 else -1,"wave":cos(phase),"random":-1 if noise(1,int(floor(elapsed)))<.25 else 1}.get(path,1)
func sun_events(hour: float=23.0) -> Array:
 var events = {}
 for source in entries(23):
  if source.law.id not in ["light.sunrise","light.sunset"]: continue
  if source.card.template != "light" or not force_active(source.card,hour): continue
  if source.hour == 0 and source.card.get("timing_synthetic",{}).get("laws",[]).has(source.law.id): continue
  var event = source.duplicate(true)
  event.source_hour = source.hour
  event.hour = int(source.slots.get("at_hour",str(source.hour))) % 24
  if not events.has(event.hour) or later(event,events[event.hour]): events[event.hour] = event
 var keys = events.keys()
 keys.sort()
 var out = []
 for h in keys: out.append(events[h])
 cached_sun_events = out
 return out
func sun(hour: float) -> Dictionary:
 var events = sun_events(hour)
 if events.is_empty():return {"vector":Vector3.DOWN,"height":-1.0,"is_night":true,"predawn":0.0,"next_location":"above"}
 var last = events.back()
 var next = events.front()
 for e in events:
  if e.hour<=hour: last = e
  if e.hour>hour:
   next = e
   break
 var span = fposmod(next.hour-last.hour,24)
 if span == 0: span = 24
 var t = clamp(fposmod(hour-last.hour,24)/span,0,1)
 var day = last.slots.verb in ["rise","move"]
 var loc = last.slots.relative_location
 var v = Vector3(-cos(PI*t)*(1 if day else -1),sin(PI*t)*(1 if day else -1),0)
 if loc == "right": v.x = -v.x
 if loc in ["forward","behind"]:
  v.z = v.x*(-1 if loc == "behind" else 1)
  v.x = 0
 if loc == "nearby": v.y *= 1.3
 if loc == "far_away": v.y *= .7
 if last.slots.verb == "stay": v = Vector3.DOWN if loc == "below" else Vector3.UP
 var predawn = 0.0
 var rise_location = next.slots.relative_location
 for event in events:
  if event.slots.verb != "rise": continue
  var distance = abs(fposmod(hour-event.hour+12,24)-12)
  if distance<1:
   var glow = (1+cos(PI*distance))/2
   if glow>predawn:
    predawn = glow
    rise_location = event.slots.relative_location
 return {"vector":v.normalized(),"height":v.y,"is_night":v.y<=0,"predawn":predawn,"next_location":rise_location}
func enabled(property: String,cause: String,hour: float,b: Dictionary,ctx: Dictionary) -> bool:
 var c = resolve(property,hour,b,ctx)
 if c.is_empty(): return true
 if c.law.id == "motion.moved": return c.slots.verb == "move" and c.slots.mover.has(cause)
 return c.slots.get("verb") != "stay" if cause in ["gravity","wind"] else true
# Clock, sky, sound and rain descriptors do not depend on a body.
func environment_parameters(hour: float,ctx: Dictionary) -> Dictionary:
 if not ctx._environment.is_empty(): return ctx._environment
 var rain = resolve("cloud.verb",hour,{},ctx)
 var start = 14.0 if rain.is_empty() or rain.get("implicit",false) and not rain.has("card") else float(rain.hour)
 var end = min(start+numbers.bench.rain_window_hours,24)
 if not rain.is_empty() and not rain.implicit:
  for l in rain.card.laws:
   if l.id == "weather.rain" and l.from_hour>start: end = min(end,l.from_hour)
 var glow = fill("sun.colour",hour,{},ctx)
 var colour_key = glow.get("colour","white")
 if ctx._sun.is_empty(): ctx._sun = sun(hour)
 var sun_data = ctx._sun.duplicate()
 var has_sun = not sun_events(hour).is_empty()
 sun_data.merge({"colour":numbers.light.colours.get(colour_key,[1,1,1]),"energy":0 if not has_sun or fill("sun.energy",hour,{},ctx).get("relative_quality") == "shaded" else numbers.light.bright_energy if colour_key == "white_bright" else numbers.light.energy,"disc_visible":has_sun and fill("sun.disc_visible",hour,{},ctx).get("relative_quality") != "invisible","disc_scale":{"bigger":numbers.light.larger_disc,"smaller":numbers.light.smaller_disc}.get(fill("sun.disc_scale",hour,{},ctx).get("relative_quality"),1)})
 ctx._environment = {"clock":{"running":fill("clock.running",hour,{},ctx).get("verb") != "stay","sign":-1 if fill("clock.sign",hour,{},ctx).get("relative_location") == "behind" else 1,"pattern":fill("clock.rate_pattern",hour,{},ctx).get("pattern","consistent"),"path":fill("clock.path",hour,{},ctx).get("vector","straight")},"light":sun_data,"weather":{"emitting":not rain.is_empty() and hour>=start and hour<end and rain.slots.verb != "stay","window":[start,end],"cloud_verb":rain.get("slots",{}).get("verb","fall"),"cloud_things":fill("cloud.things",hour,{},ctx).get("things","raindrops"),"wind_path":fill("wind.path",hour,{},ctx).get("vector","random")},"sound":{"visible":fill("sound.visibility",hour,{},ctx).get("relative_quality") in ["visible","glowing"],"propagates":not resolve("sound.propagates",hour,{},ctx).is_empty() and fill("sound.propagates",hour,{},ctx).get("verb") != "stay"}}
 return ctx._environment
func parameters(hour: float,b: Dictionary={},ctx: Dictionary={}) -> Dictionary:
 prepare_context(hour,ctx)
 var falling = fill("gravity.vector",hour,b,ctx)
 var base = (location(falling.get("relative_location_2","below"),b,ctx)-location(falling.get("relative_location_1","above"),b,ctx)).normalized()
 var gravity = vector_path(fill("body.path",hour,b,ctx).get("vector","straight"),base,ctx.get("time",0),int(b.get("id",1)),ctx.get("plane","xyz"))
 var response = resolve("body.response",hour,b,ctx)
 var factor = 1.0 if response.is_empty() or response.implicit else float(b.get("mass",1))*2 if response.slots.relative_quality_2 == "faster" else .5
 var environment = environment_parameters(hour,ctx)
 var weather = environment.weather.duplicate()
 weather.wind_strength = tuned("wind_strength","weather","wind.path",hour,b,ctx)
 weather.rain_rate = tuned("rain_rate","weather","cloud.verb",hour,b,ctx)
 weather.wind_enabled = not resolve("wind.path",hour,b,ctx).is_empty() and enabled("wind.enabled","wind",hour,b,ctx)
 var operations = []
 for c in (ctx.entries if ctx.has("entries") else entries(hour)):
  if c.law.id == "gravity.speed" and not c.get("implicit",false) and matches(c,b,ctx):
   var winner = resolve("body."+c.slots.quality,hour,b,ctx)
   if not winner.is_empty() and winner == c: operations.append(c.slots)
 var rest = resolve("body.rest_verb",hour,b,ctx)
 return {"gravity":{"vector":gravity,"enabled":not resolve("gravity.vector",hour,b,ctx).is_empty() and enabled("gravity.enabled","gravity",hour,b,ctx),"strength":tuned("gravity_strength","gravity","gravity.vector",hour,b,ctx)},"body":{"contact_enabled":enabled("contact.enabled","contact",hour,b,ctx),"random_enabled":enabled("random.enabled","random",hour,b,ctx) and fill("body.causes",hour,b,ctx).get("mover",[]).has("random"),"response_factor":factor,"meeting":fill("body.meeting",hour,b,ctx).get("meeting","collide"),"rebound":tuned("matter_rebound","matter","body.meeting",hour,b,ctx),"motion_resistance":tuned("motion_resistance","motion","body.causes",hour,b,ctx),"rest":null if rest.is_empty() or rest.implicit else rest.slots.verb,"apex_verb":fill("body.apex_verb",hour,b,ctx).get("verb_2","fall"),"operations":operations},"clock":environment.clock.merged({"pace":tuned("time_rate","time","clock.rate_pattern",hour,b,ctx)}),"light":environment.light.merged({"energy":environment.light.energy*tuned("light_strength","light","sun.colour",hour,b,ctx)},true),"weather":weather,"sound":environment.sound.merged({"strength":tuned("sound_strength","sound","sound.propagates",hour,b,ctx)})}

const TUNING = {
 "gravity_strength":["gravity",0.0,19.6,9.8], "motion_resistance":["motion",0.0,1.2,0.0],
 "matter_rebound":["matter",0.0,1.0,0.35], "light_strength":["light",0.0,2.0,1.0],
 "sound_strength":["sound",0.0,2.0,1.0], "wind_strength":["weather",0.0,2.0,1.0],
 "rain_rate":["weather",0.0,2.0,1.0], "time_rate":["time",0.25,2.0,1.0]
}
func validate_parameters(card: Dictionary) -> void:
 var seen = {}
 var changes = card.get("parameter_changes",[])
 if not changes is Array:
  errors.append("Parameter changes must be an array.")
  return
 for change in changes:
  if not change is Dictionary or not TUNING.has(change.get("key","")):
   errors.append("Unknown numeric parameter.")
   continue
  var spec = TUNING[change.key]
  var at = change.get("from_hour",-1)
  var value = change.get("value")
  if card.get("template") != spec[0] or not (at is int or at is float) or at < 0 or at > 23 or at != floor(at):
   errors.append("Parameter belongs to another force or has an invalid hour.")
  if not (value is int or value is float) or not is_finite(float(value)) or value < spec[1] or value > spec[2]:
   errors.append("Numeric parameter is outside its bounds.")
  var key = str(change.key)+"@"+str(at)
  if seen.has(key): errors.append("Duplicate numeric parameter schedule.")
  seen[key] = true
func tuned(key: String, family: String, property: String, at: float,b: Dictionary={},ctx: Dictionary={}) -> float:
 if numeric_overrides.has(key): return clampf(float(numeric_overrides[key]),TUNING[key][1],TUNING[key][2])
 var source = resolve(property,at,b,ctx)
 var card = source.get("card",{})
 if card.is_empty():
  for index in range(world.forces.size()-1,-1,-1):
   if world.forces[index].template == family and force_active(world.forces[index],at):
    card = world.forces[index]
    break
 var local = card_numeric_overrides.get(str(card.get("card","")),{})
 if local.has(key): return clampf(float(local[key]),TUNING[key][1],TUNING[key][2])
 return card_tuned(key,card,at)
func card_tuned(key: String,card: Dictionary,at: float) -> float:
 var value = float(TUNING[key][3])
 var latest = -1.0
 for change in card.get("parameter_changes",[]):
  if change.key == key and change.from_hour <= at and change.from_hour >= latest:
   value = float(change.value)
   latest = change.from_hour
 return value
