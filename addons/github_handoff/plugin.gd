@tool
extends EditorPlugin

const GITHUB_WORKSHEET = "https://app.notion.com/p/3ffe76ad1e9f8003b283cc0502c37b40"
var button: Button
var panel: AcceptDialog
var status: Label
var folder: LineEdit
var copy_path: Button

func _enter_tree() -> void:
 button=Button.new()
 button.text="Save for GitHub"
 button.tooltip_text="Save scenes and find your complete project folder."
 button.pressed.connect(open_handoff)
 add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,button)
 panel=AcceptDialog.new()
 panel.title="Save for GitHub"
 panel.ok_button_text="Done"
 var scale=EditorInterface.get_editor_scale()
 panel.min_size=Vector2i(int(740*scale),int(300*scale))
 EditorInterface.get_base_control().add_child(panel)
 var box=VBoxContainer.new()
 box.custom_minimum_size=Vector2(700*scale,0)
 box.add_theme_constant_override("separation",12)
 panel.add_child(box)
 status=Label.new()
 box.add_child(status)
 var intro=Label.new()
 intro.text="Use this complete project folder for your GitHub repository."
 box.add_child(intro)
 var folder_label=Label.new()
 folder_label.text="Project folder"
 box.add_child(folder_label)
 folder=LineEdit.new()
 folder.editable=false
 folder.focus_entered.connect(folder.select_all)
 box.add_child(folder)
 var actions=HBoxContainer.new()
 actions.add_theme_constant_override("separation",12)
 box.add_child(actions)
 var show_folder=Button.new()
 show_folder.text="Open project folder"
 show_folder.pressed.connect(open_project_folder)
 actions.add_child(show_folder)
 copy_path=Button.new()
 copy_path.text="Copy path"
 copy_path.pressed.connect(func():
  DisplayServer.clipboard_set(folder.text)
  copy_path.text="Copied"
 )
 actions.add_child(copy_path)
 var guide=Button.new()
 guide.text="GitHub Worksheet"
 guide.pressed.connect(func():OS.shell_open(GITHUB_WORKSHEET))
 actions.add_child(guide)
 var next=Label.new()
 next.text="Mac / Windows: commit and push in GitHub Desktop.\nChromebook: upload through GitHub in Chrome.\nFollow the worksheet for setup and inviting Neven."
 box.add_child(next)
 var note=Label.new()
 note.text="Save any script edits before continuing. This button does not upload."
 box.add_child(note)

func open_project_folder() -> void:
 if OS.shell_open(folder.text)!=OK:
  status.text="Could not open the folder. Copy its path and locate it in your Files app."

func open_handoff() -> void:
 EditorInterface.save_all_scenes()
 status.text="Scenes saved on this computer."
 folder.text=ProjectSettings.globalize_path("res://")
 folder.tooltip_text=folder.text
 folder.caret_column=0
 copy_path.text="Copy path"
 var scale=EditorInterface.get_editor_scale()
 for child in panel.get_children():
  if child is VBoxContainer:child.custom_minimum_size.x=700*scale
 panel.min_size=Vector2i(int(740*scale),int(300*scale))
 panel.popup_centered(panel.min_size)

func _exit_tree() -> void:
 if is_instance_valid(button):
  remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU,button)
  button.queue_free()
 if is_instance_valid(panel):panel.queue_free()
