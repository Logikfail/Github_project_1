class_name TowerInspector
extends Control
## Tower click panel — shows stats and Keep/Combine actions during draft selection phase.
## Opened by WorldRoot when TowerManager emits tower_inspected.
## Shows/hides the range ring on the inspected tower.


# === Constants ===

const _TARGETING_MODES: Array[StringName] = [
	&"closest", &"first", &"last", &"healthiest", &"uninfected", &"most_infected"
]
const _TARGETING_LABELS: Dictionary = {
	&"closest":       "Closest",
	&"first":         "First",
	&"last":          "Last",
	&"healthiest":    "Healthiest",
	&"uninfected":    "Uninfected",
	&"most_infected": "Most Infected",
}

const _TYPE_DESCRIPTION: Dictionary = {
	&"blight":       "Circle AOE — damages all villagers in range",
	&"plague":       "Single Target — stacking plague, damage intensifies per hit",
	&"pestilence":   "Single Target — infection that can spread to nearby villagers",
	&"miasma":       "Circle AOE — reduces all resistances in the area",
	&"festering":    "Single Target — direct wound damage",
	&"wither":       "Targeted AOE — explodes at the target's location",
	&"epidemic":     "Cone AOE — hits multiple villagers in a forward cone",
	&"shroud":       "Circle AOE — large death cloud engulfs the area",
	&"corpse_bloom": "Targeted AOE — flowering infection explodes on target",
	&"virulence":    "Chain x5 — plague jumps between up to 5 targets",
	&"septic":       "Single Target — powerful concentrated toxin",
	&"fester_burst": "Line Pierce — pierces through all villagers in a line",
	&"pandemic":     "Circle AOE — mass infection across the entire range",
	&"plague_pit":   "Single Target — concentrated rot damage",
	&"necrotic":     "Circle AOE — area decay with lingering effect",
}

const _TYPE_SUMMARY: Dictionary = {
	&"blight":       "Area Rot",
	&"plague":       "Direct Infect",
	&"pestilence":   "Single Target",
	&"miasma":       "Toxic Cloud",
	&"festering":    "Wound Strike",
	&"wither":       "Burst Zone",
	&"epidemic":     "Cone Spread",
	&"shroud":       "Death Cloud",
	&"corpse_bloom": "Bloom Burst",
	&"virulence":    "Chain Plague",
	&"septic":       "Toxic Strike",
	&"fester_burst": "Line Pierce",
	&"pandemic":     "Mass Spread",
	&"plague_pit":   "Rot Trap",
	&"necrotic":     "Death Rot",
}


# === Onready ===

@onready var _panel: PanelContainer = $Panel
@onready var _title_label: Label = %TitleLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _targeting_label: Label = %TargetingLabel
@onready var _targeting_container: HFlowContainer = %TargetingContainer
@onready var _keep_button: Button = %KeepButton
@onready var _combine_label: Label = %CombineLabel
@onready var _combine_container: VBoxContainer = %CombineContainer
@onready var _close_button: Button = %CloseButton


# === Private Variables ===

var _current_tower: Node = null


# === Lifecycle ===

func _ready() -> void:
	_keep_button.pressed.connect(_on_keep_pressed)
	_close_button.pressed.connect(_on_close_pressed)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not _panel.get_global_rect().has_point(mb.position):
				_close()


# === Public API ===

func inspect(tower: Node) -> void:
	_hide_current_ring()
	_current_tower = tower
	_populate(tower)
	_show_current_ring()
	visible = true


# === Private — Populate ===

func _populate(tower: Node) -> void:
	var data: TowerData = TowerManager.get_tower_data(tower)
	if data == null:
		_title_label.text = "Unknown Tower"
		_stats_label.text = ""
		_keep_button.visible = false
		_combine_label.visible = false
		_combine_container.visible = false
		return

	var summary: String = _TYPE_SUMMARY.get(data.tower_type, "")
	_title_label.text = "%s — %s" % [str(data.tower_type).capitalize(), summary]
	_stats_label.text = "Shape: %s\nRange: %.0f\nFire Rate: %.1fs" % [
		str(data.attack_shape), data.range_radius, data.fire_rate
	]

	var placed: Array[Node] = DraftManager.get_placed_this_round()
	var in_selection: bool = placed.has(tower)
	_keep_button.visible = in_selection
	_refresh_combine_buttons(tower, in_selection)
	_refresh_targeting_buttons(tower)


func _refresh_targeting_buttons(tower: Node) -> void:
	for child: Node in _targeting_container.get_children():
		child.queue_free()
	var barricade: bool = TowerManager.is_barricade(tower)
	_targeting_label.visible = not barricade
	_targeting_container.visible = not barricade
	if barricade:
		return
	var current_mode: StringName = TowerManager.get_targeting_mode(tower)
	for mode: StringName in _TARGETING_MODES:
		var btn := Button.new()
		btn.text = _TARGETING_LABELS.get(mode, str(mode))
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 28)
		if mode == current_mode:
			btn.modulate = Color(0.3, 1.0, 0.5)
			btn.disabled = true
		btn.pressed.connect(_on_targeting_pressed.bind(tower, mode))
		_targeting_container.add_child(btn)


func _refresh_combine_buttons(tower: Node, in_selection: bool) -> void:
	for child: Node in _combine_container.get_children():
		child.queue_free()

	if not in_selection:
		_combine_label.visible = false
		_combine_container.visible = false
		return

	var pairs: Array[Dictionary] = DraftManager.get_valid_combine_pairs()
	var relevant: Array[Dictionary] = []
	for pair: Dictionary in pairs:
		if pair["tower_a"] == tower or pair["tower_b"] == tower:
			relevant.append(pair)

	_combine_label.visible = not relevant.is_empty()
	_combine_container.visible = not relevant.is_empty()

	for pair: Dictionary in relevant:
		var result_type: StringName = pair["result_type"] as StringName
		var summary: String = _TYPE_SUMMARY.get(result_type, "")
		var desc: String = _TYPE_DESCRIPTION.get(result_type, "")
		var btn := Button.new()
		btn.text = "Combine → %s  [%s]" % [str(result_type).capitalize(), summary]
		btn.tooltip_text = desc
		btn.pressed.connect(_on_combine_pressed.bind(pair))
		_combine_container.add_child(btn)


# === Private — Range Ring ===

func _show_current_ring() -> void:
	if is_instance_valid(_current_tower):
		var tower_node: TowerBase = _current_tower as TowerBase
		if is_instance_valid(tower_node):
			tower_node.show_range_ring()


func _hide_current_ring() -> void:
	if is_instance_valid(_current_tower):
		var tower_node: TowerBase = _current_tower as TowerBase
		if is_instance_valid(tower_node):
			tower_node.hide_range_ring()


# === Private — Close ===

func _close() -> void:
	_hide_current_ring()
	_current_tower = null
	visible = false


# === Private — Handlers ===

func _on_keep_pressed() -> void:
	if is_instance_valid(_current_tower):
		DraftManager.resolve_keep(_current_tower)
	_close()


func _on_combine_pressed(pair: Dictionary) -> void:
	# Always pass _current_tower as tower_a so the result stays at the inspected tower's tile.
	var other: Node = pair["tower_b"] if pair["tower_a"] == _current_tower else pair["tower_a"]
	DraftManager.resolve_combine(_current_tower, other)
	_close()


func _on_close_pressed() -> void:
	_close()


func _on_targeting_pressed(tower: Node, mode: StringName) -> void:
	if not is_instance_valid(tower):
		return
	TowerManager.set_targeting_mode(tower, mode)
	_refresh_targeting_buttons(tower)
