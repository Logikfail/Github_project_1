class_name CampaignMap
extends Control
## Campaign world map — full-screen village selector between battles.
## Green = cleared, yellow = active/available, grey = locked.
## Calls CampaignManager.start_campaign() on first visit; subsequent visits
## resume from the current completed count.

# === Onready ===

@onready var _villages_container: VBoxContainer = %VillagesContainer
@onready var _back_button: Button = %BackButton


# === Lifecycle ===

func _ready() -> void:
	if not CampaignManager.is_active():
		CampaignManager.start_campaign()
	_back_button.pressed.connect(_on_back_pressed)
	_refresh()


# === Private ===

func _refresh() -> void:
	for child: Node in _villages_container.get_children():
		child.queue_free()
	var completed: int = CampaignManager.get_villages_completed()
	for i: int in GameConfig.VILLAGES_PER_CAMPAIGN:
		_villages_container.add_child(_build_village_entry(i, completed))


func _build_village_entry(village_index: int, completed: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	var btn := Button.new()
	btn.text = "Village %d" % (village_index + 1)
	btn.custom_minimum_size = Vector2(220.0, 52.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if village_index < completed:
		btn.modulate = Color(0.2, 0.8, 0.2)
		btn.disabled = true
	elif village_index == completed:
		btn.modulate = Color(1.0, 0.9, 0.2)
		btn.disabled = false
		btn.pressed.connect(_on_village_selected.bind(village_index))
	else:
		btn.modulate = Color(0.5, 0.5, 0.5)
		btn.disabled = true
	hbox.add_child(btn)

	var cards: Array[ModifierCard] = CampaignManager.get_modifier_cards_for_village(village_index)
	for card: ModifierCard in cards:
		hbox.add_child(_build_modifier_chip(card))

	return hbox


func _build_modifier_chip(card: ModifierCard) -> Control:
	var btn := Button.new()
	btn.text = card.get_short_label()
	btn.tooltip_text = card.get_label()
	btn.custom_minimum_size = Vector2(52.0, 52.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	return btn


func _on_village_selected(_village_index: int) -> void:
	# world_root._ready() calls enter_village(get_villages_completed()) on load
	get_tree().change_scene_to_file("res://scenes/world/main.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
