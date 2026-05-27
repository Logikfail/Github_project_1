class_name WorldMap
extends Control
## World Map panel — linear 5-node map showing village cleared/active/locked states.
## Requires scene child: %NodesContainer (HBoxContainer).
## Each village node is a Button: green = cleared, yellow = active, grey = locked.


# === Onready ===

@onready var _nodes_container: HBoxContainer = %NodesContainer


# === Lifecycle ===

func _ready() -> void:
	CampaignManager.village_complete.connect(_on_village_complete)
	CampaignManager.campaign_won.connect(_on_campaign_won)
	CampaignManager.campaign_failed.connect(_on_campaign_failed)
	_refresh()


# === Private — Refresh ===

func _refresh() -> void:
	for child: Node in _nodes_container.get_children():
		child.queue_free()
	var current: int = CampaignManager.get_current_village_index()
	for i: int in GameConfig.VILLAGES_PER_CAMPAIGN:
		_nodes_container.add_child(_build_village_node(i, current))


func _build_village_node(village_index: int, current_index: int) -> Button:
	var btn := Button.new()
	btn.text = "Village %d" % (village_index + 1)
	if village_index < current_index:
		btn.modulate = Color(0.2, 0.8, 0.2)   # cleared — green
		btn.disabled = true
	elif village_index == current_index:
		btn.modulate = Color(1.0, 0.9, 0.2)   # active — yellow
		btn.disabled = false
	else:
		btn.modulate = Color(0.5, 0.5, 0.5)   # locked — grey
		btn.disabled = true
	return btn


# === Private — Signal Handlers ===

func _on_village_complete(_village_index: int) -> void:
	_refresh()


func _on_campaign_won() -> void:
	for child: Node in _nodes_container.get_children():
		child.modulate = Color(0.2, 0.8, 0.2)  # all green on win


func _on_campaign_failed(_reason: StringName) -> void:
	# Dim the active node red to indicate failure
	var current: int = CampaignManager.get_current_village_index()
	var btn: Button = _nodes_container.get_child(current) as Button
	if is_instance_valid(btn):
		btn.modulate = Color(0.9, 0.2, 0.2)
