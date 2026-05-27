class_name TechTreeScreen
extends Control
## Post-village screen — spend tech points, then continue to world map (or main menu if campaign won).


# === Onready ===

@onready var _title_label: Label = %TitleLabel
@onready var _continue_button: Button = %ContinueButton


# === Lifecycle ===

func _ready() -> void:
	_continue_button.pressed.connect(_on_continue_pressed)
	if CampaignManager.is_active():
		_title_label.text = "VILLAGE CLEARED"
		_continue_button.text = "Continue to World Map"
	else:
		_title_label.text = "CAMPAIGN COMPLETE"
		_continue_button.text = "Return to Main Menu"


# === Private ===

func _on_continue_pressed() -> void:
	if CampaignManager.is_active():
		get_tree().change_scene_to_file("res://scenes/ui/campaign_map.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
