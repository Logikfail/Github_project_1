class_name DraftUI
extends Control
## Tower Draft panel — placement phase, selection hint, gated Rouse.
## Phases:
##   PLACEMENT: pending_draft > 0 → show "Place Tower" button
##   SELECTION: all placed, not yet resolved → show hint to click a tower
##   READY: draft resolved → Rouse button enabled


# === Signals ===

signal rouse_confirmed()
## Emitted when player clicks "Place Tower" — WorldRoot grabs pending_draft[0] and arms placement.
signal request_next_tower_placement()


# === Onready ===

@onready var _placement_section: VBoxContainer = %PlacementSection
@onready var _towers_label: Label = %TowersLabel
@onready var _place_tower_button: Button = %PlaceTowerButton
@onready var _selection_hint: Label = %SelectionHint
@onready var _rouse_button: Button = %RouseButton
@onready var _resistance_overlay: Control = %ResistanceOverlay


# === Private Variables ===

var _resolved: bool = false


# === Lifecycle ===

func _ready() -> void:
	DraftManager.pending_draft_non_empty.connect(_on_pending_draft_non_empty)
	DraftManager.tower_placed_from_draft.connect(_on_tower_placed)
	DraftManager.draft_resolved.connect(_on_draft_resolved)
	_place_tower_button.pressed.connect(_on_place_tower_pressed)
	_rouse_button.pressed.connect(_on_rouse_pressed)
	_resistance_overlay.visible = false
	_refresh()


# === Private — Signal Handlers ===

func _on_pending_draft_non_empty() -> void:
	print("[DraftUI] _on_pending_draft_non_empty fired — was _resolved=", _resolved)
	_resolved = false
	_refresh()


func _on_tower_placed() -> void:
	print("[DraftUI] _on_tower_placed — pending now=", DraftManager.get_pending_draft().size())
	_refresh()


func _on_draft_resolved() -> void:
	print("[DraftUI] _on_draft_resolved")
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

	print("[DraftUI] _refresh — pending=", pending_count, " placed=", placed.size(),
			" _resolved=", _resolved, " in_placement=", in_placement,
			" placement_section.visible=", _placement_section.visible,
			" rouse_disabled=", _rouse_button.disabled)

	if in_placement:
		_towers_label.text = "Towers to place: %d" % pending_count
