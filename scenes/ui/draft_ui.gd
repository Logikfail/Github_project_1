class_name DraftUI
extends Control
## Tower Draft panel — placement phase, selection hint, gated Rouse.
## Phases:
##   PLACEMENT: pending_draft > 0 → show "Place Tower" button
##   SELECTION: all placed, not yet resolved → show hint to click a tower
##   READY: draft resolved → Rouse button enabled
## On entering the placement phase, briefly flashes the placement section and
## shows a "New Draft!" banner so the player can't miss the prompt.


# === Signals ===

signal rouse_confirmed()
## Emitted when player clicks "Place Tower" — WorldRoot grabs pending_draft[0] and arms placement.
signal request_next_tower_placement()


# === Constants ===

const _FLASH_DURATION: float = 0.45
const _FLASH_COLOR: Color = Color(1.0, 1.0, 0.6, 1.0)
const _NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const _BANNER_DURATION: float = 2.0
const _BANNER_FADE_DURATION: float = 0.6


# === Onready ===

@onready var _placement_section: VBoxContainer = %PlacementSection
@onready var _towers_label: Label = %TowersLabel
@onready var _place_tower_button: Button = %PlaceTowerButton
@onready var _selection_hint: Label = %SelectionHint
@onready var _rouse_button: Button = %RouseButton
@onready var _resistance_overlay: Control = %ResistanceOverlay


# === Private Variables ===

var _resolved: bool = false
var _banner: Label = null
var _flash_tween: Tween = null
var _banner_tween: Tween = null


# === Lifecycle ===

func _ready() -> void:
	DraftManager.pending_draft_non_empty.connect(_on_pending_draft_non_empty)
	DraftManager.tower_placed_from_draft.connect(_on_tower_placed)
	DraftManager.draft_resolved.connect(_on_draft_resolved)
	_place_tower_button.pressed.connect(_on_place_tower_pressed)
	_rouse_button.pressed.connect(_on_rouse_pressed)
	_resistance_overlay.visible = false
	# Make the placement label legible — the .tscn default of 12 is too small.
	_towers_label.add_theme_font_size_override("font_size", 16)
	_towers_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6, 1.0))
	_build_banner()
	_refresh()


# === Private — Signal Handlers ===

func _on_pending_draft_non_empty() -> void:
	var was_hidden: bool = not _placement_section.visible
	_resolved = false
	_refresh()
	# Only flash when the panel transitions from hidden → visible (new draft arrival).
	if was_hidden:
		_play_new_draft_flash(DraftManager.get_pending_draft().size())


func _on_tower_placed() -> void:
	_refresh()


func _on_draft_resolved() -> void:
	_resolved = true
	_refresh()


func _on_place_tower_pressed() -> void:
	request_next_tower_placement.emit()


func _on_rouse_pressed() -> void:
	rouse_confirmed.emit()


# === Private — Refresh ===

func _refresh() -> void:
	var pending_count: int = DraftManager.get_pending_draft().size()
	var placed: Array[Node] = DraftManager.get_placed_this_round()
	var in_placement: bool = pending_count > 0
	var in_selection: bool = not in_placement and placed.size() > 0 and not _resolved

	_placement_section.visible = in_placement
	_selection_hint.visible = in_selection
	_rouse_button.disabled = not _resolved

	if in_placement:
		_towers_label.text = "New towers in draft: %d" % pending_count


# === Private — New-Draft Visual Prompt ===

func _build_banner() -> void:
	_banner = Label.new()
	_banner.name = "NewDraftBanner"
	_banner.text = ""
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 32)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.95, 0.5, 1.0))
	_banner.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-200.0, 100.0)
	_banner.custom_minimum_size = Vector2(400.0, 60.0)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)


func _play_new_draft_flash(tower_count: int) -> void:
	# Banner: fade in, hold, fade out.
	_banner.text = "New Tower Draft — place %d towers!" % tower_count
	if is_instance_valid(_banner_tween):
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, _BANNER_FADE_DURATION)
	_banner_tween.tween_interval(_BANNER_DURATION)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, _BANNER_FADE_DURATION)

	# Placement section: pulse modulate from highlight back to normal twice.
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_placement_section.modulate = _FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.set_loops(2)
	_flash_tween.tween_property(_placement_section, "modulate", _NORMAL_COLOR, _FLASH_DURATION)
	_flash_tween.tween_property(_placement_section, "modulate", _FLASH_COLOR, _FLASH_DURATION)
	_flash_tween.chain().tween_property(_placement_section, "modulate", _NORMAL_COLOR, _FLASH_DURATION)
