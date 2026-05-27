class_name MainMenu
extends Control
## Main menu — entry point for all game modes.

# === Onready ===

@onready var _campaign_button: Button = %CampaignButton
@onready var _endless_button: Button = %EndlessButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


# === Lifecycle ===

func _ready() -> void:
	_campaign_button.pressed.connect(_on_campaign_pressed)
	_endless_button.pressed.connect(_on_endless_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_endless_button.disabled = true
	_settings_button.disabled = true


# === Private ===

func _on_campaign_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/campaign_map.tscn")


func _on_endless_pressed() -> void:
	pass


func _on_settings_pressed() -> void:
	pass


func _on_quit_pressed() -> void:
	get_tree().quit()
