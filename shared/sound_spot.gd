@tool
extends AudioStreamPlayer3D
@export var loop_sound = true
func _ready() -> void:
 if Engine.is_editor_hint(): return
 if stream == null: stream = load("res://sounds/atmosphere.wav")
 stream = stream.duplicate()
 if stream is AudioStreamWAV and loop_sound:
  stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
  stream.loop_begin = 0
  stream.loop_end = int(stream.get_length()*stream.mix_rate)
 elif stream is AudioStreamOggVorbis: stream.loop = loop_sound
 if DisplayServer.get_name() != "headless": play()
