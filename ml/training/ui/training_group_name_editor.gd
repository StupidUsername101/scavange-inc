class_name TrainingGroupNameEditor
extends RefCounted

#######################################################
# Shared worker-group rename widget state. Group owners still decide naming rules and persistence
# lineage; this helper only keeps the LineEdit/card-button transition identical across body types.
#######################################################


static func begin(group: Dictionary) -> LineEdit:
	if group.is_empty():
		return null
	var name_edit: LineEdit = group.get("name_edit") as LineEdit
	var select_button: Button = group.get("card_button") as Button
	if name_edit == null or select_button == null:
		return null
	name_edit.text = str(group.get("name", "Worker group"))
	select_button.visible = false
	name_edit.visible = true
	name_edit.modulate.a = 1.0
	name_edit.grab_focus()
	name_edit.select_all()
	return name_edit


static func cancel(group: Dictionary) -> void:
	if group.is_empty():
		return
	var name_edit: LineEdit = group.get("name_edit") as LineEdit
	var select_button: Button = group.get("card_button") as Button
	if name_edit != null:
		name_edit.text = str(group.get("name", "Worker group"))
		name_edit.visible = false
		name_edit.modulate.a = 1.0
		name_edit.release_focus()
	if select_button != null:
		select_button.visible = true


static func finish(group: Dictionary, committed_name: String) -> void:
	if group.is_empty():
		return
	var name_edit: LineEdit = group.get("name_edit") as LineEdit
	var select_button: Button = group.get("card_button") as Button
	if name_edit != null:
		name_edit.text = committed_name
		name_edit.visible = false
		name_edit.modulate.a = 1.0
		name_edit.release_focus()
	if select_button != null:
		select_button.visible = true
