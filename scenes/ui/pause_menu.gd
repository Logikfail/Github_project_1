class_name PauseMenu
extends Control
## In-game pause overlay — resume, quit to menu, quit game.
## Handles its own ESC toggle. Caller opens via show_menu().


# === Onready ===

@onready var _resume_button: Button = %ResumeButton
@onready var _quit_menu_button: Button = %QuitToMenuButton
@onready var _quit_game_button: Button = %QuitGameButton


# === Lifecycle ===

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resume_button.pressed.connect(_on_resume_pressed)
	_quit_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	_quit_game_button.pressed.connect(_on_quit_game_pressed)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			_on_resume_pressed()
		else:
			show_menu()
		get_viewport().set_input_as_handled()


# === Public ===

func show_menu() -> void:
	get_tree().paused = true
	show()
	_resume_button.grab_focus()


# === Private ===

func _on_resume_pressed() -> void:
	get_tree().paused = false
	hide()


func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_quit_game_pressed() -> void:
	get_tree().quit()
