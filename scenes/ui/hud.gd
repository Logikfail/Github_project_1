class_name HUD
extends Control
## In-game HUD — morale bar + village/house progress.


# === Signals ===

signal menu_button_pressed


# === Constants ===

const COLOR_GOOD: Color = Color(0.2, 0.8, 0.2)
const COLOR_NEUTRAL: Color = Color(0.9, 0.9, 0.9)
const COLOR_BAD: Color = Color(0.9, 0.2, 0.2)


# === Onready ===

@onready var _morale_bar: ProgressBar = %MoraleBar
@onready var _village_label: Label = %VillageLabel
@onready var _houses_label: Label = %HousesLabel
@onready var _modifiers_label: Label = %ModifiersLabel
@onready var _speed_1x: Button = %Speed1x
@onready var _speed_2x: Button = %Speed2x
@onready var _speed_3x: Button = %Speed3x
@onready var _menu_button: Button = %MenuButton
@onready var _status_label: Label = %StatusLabel


# === Private Variables ===

var _total_houses: int = 0
var _cleared_houses: int = 0


# === Lifecycle ===

func _ready() -> void:
	_morale_bar.min_value = 0.0
	_morale_bar.max_value = 1.0
	MoraleManager.morale_changed.connect(_on_morale_changed)
	CampaignManager.village_started.connect(_on_village_started)
	WaveManager.wave_complete.connect(_on_wave_complete)
	_refresh_morale()
	_village_label.text = ""
	_houses_label.text = ""
	_modifiers_label.text = ""
	_modifiers_label.get_parent().get_parent().visible = false
	_speed_1x.pressed.connect(_on_speed_pressed.bind(1.0))
	_speed_2x.pressed.connect(_on_speed_pressed.bind(2.0))
	_speed_3x.pressed.connect(_on_speed_pressed.bind(3.0))
	_menu_button.pressed.connect(func() -> void: menu_button_pressed.emit())


# === Private — Morale ===

func _refresh_morale() -> void:
	var morale: int = MoraleManager.get_morale()
	var range_width: float = float(GameConfig.MORALE_MAX - GameConfig.MORALE_MIN)
	var normalised: float = (morale - GameConfig.MORALE_MIN) / range_width
	_morale_bar.value = normalised

	if morale <= GameConfig.MORALE_MIN:
		_morale_bar.modulate = COLOR_BAD
	elif morale >= GameConfig.MORALE_MAX:
		_morale_bar.modulate = COLOR_GOOD
	else:
		_morale_bar.modulate = COLOR_NEUTRAL


func _on_morale_changed(_new_value: int) -> void:
	_refresh_morale()


# === Private — Village Progress ===

func _on_village_started(village_data: VillageData) -> void:
	_total_houses = village_data.houses.size()
	_cleared_houses = 0
	var village_num: int = village_data.village_index + 1
	_village_label.text = "Village %d / %d" % [village_num, GameConfig.VILLAGES_PER_CAMPAIGN]
	_refresh_houses()
	_refresh_modifiers(village_data)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		Engine.time_scale = 1.0


func _on_speed_pressed(scale: float) -> void:
	Engine.time_scale = scale
	_speed_1x.button_pressed = (scale == 1.0)
	_speed_2x.button_pressed = (scale == 2.0)
	_speed_3x.button_pressed = (scale == 3.0)


func _refresh_modifiers(village_data: VillageData) -> void:
	var cards: Array[ModifierCard] = village_data.modifier_cards
	if cards.is_empty():
		_modifiers_label.text = ""
		_modifiers_label.get_parent().get_parent().visible = false
		return
	_modifiers_label.get_parent().get_parent().visible = true
	var lines: PackedStringArray = []
	for card: ModifierCard in cards:
		lines.append("⚠ " + card.get_label())
	_modifiers_label.text = "\n".join(lines)


func _on_wave_complete(
	_house: Node, _all_infected: bool, _escaped_count: int, _infected_count: int
) -> void:
	_cleared_houses += 1
	_refresh_houses()


func _refresh_houses() -> void:
	_houses_label.text = "Houses: %d / %d" % [_cleared_houses, _total_houses]


# === Public — Status ===

func set_status(text: String) -> void:
	_status_label.text = text
