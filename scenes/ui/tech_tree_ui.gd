class_name TechTreeUI
extends Control
## Tech Tree panel — branch viewer, available node buttons, point count.
## Requires scene children: %PointsLabel, %BranchContainer.
## Node choice selection (pick 1 of N stat options) is presented inline as sub-buttons
## inside each branch row.


# === Onready ===

@onready var _points_label: Label = %PointsLabel
@onready var _branch_container: VBoxContainer = %BranchContainer


# === Lifecycle ===

func _ready() -> void:
	TechTreeManager.node_purchased.connect(_on_node_purchased)
	TechTreeManager.synthesis_tower_unlocked.connect(_on_synthesis_unlocked)
	_refresh()


# === Private — Refresh ===

func _refresh() -> void:
	_points_label.text = "Tech Points: %d" % TechTreeManager.get_points()
	_refresh_branches()


func _refresh_branches() -> void:
	for child: Node in _branch_container.get_children():
		child.queue_free()
	for branch: StringName in GameConfig.BASE_TOWER_TYPES:
		_branch_container.add_child(_build_branch_row(branch))


func _build_branch_row(branch: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = str(branch).capitalize()
	name_label.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(name_label)
	for node: TechNode in TechTreeManager.get_available_nodes(branch):
		row.add_child(_build_node_button(node))
	return row


func _build_node_button(node: TechNode) -> Button:
	var btn := Button.new()
	var cost_str: String = "(%d pts)" % node.cost
	if node.node_type == &"stat":
		btn.text = "Stat %s" % cost_str
	else:
		btn.text = "Discovery %s" % cost_str
	btn.disabled = TechTreeManager.get_points() < node.cost
	btn.pressed.connect(_on_node_pressed.bind(node))
	return btn


func _on_node_pressed(node: TechNode) -> void:
	# Opens a choice sub-menu. Currently auto-selects index 0 as a placeholder;
	# the visual pass will replace this with a proper choice picker popup.
	_show_choice_popup(node)


func _show_choice_popup(node: TechNode) -> void:
	# Placeholder: create a transient popup with one button per choice.
	var popup := PopupMenu.new()
	add_child(popup)
	var choices: Array[StringName] = node.stat_options if node.node_type == &"stat" \
		else node.synthesis_options
	for i: int in choices.size():
		popup.add_item(str(choices[i]), i)
	popup.id_pressed.connect(_on_choice_selected.bind(node, popup))
	popup.popup_centered()


func _on_choice_selected(id: int, node: TechNode, popup: PopupMenu) -> void:
	TechTreeManager.purchase_node(node, id)
	popup.queue_free()


# === Private — Signal Handlers ===

func _on_node_purchased(_node: TechNode) -> void:
	_refresh()


func _on_synthesis_unlocked(_tower_type: StringName) -> void:
	_refresh()
