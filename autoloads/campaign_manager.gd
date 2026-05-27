extends Node
## Top-level run orchestrator — village progression, modifier deck, win/fail conditions.
## Wires WaveManager and MoraleManager events into campaign-level state transitions.


# === Signals ===

signal village_started(village_data: VillageData)
signal village_complete(village_index: int)
signal campaign_won()
signal campaign_failed(reason: StringName)


# === Constants ===

const _MODIFIER_CARD_TYPES: Array[StringName] = [
	&"quarantine_edict",
	&"apothecaries_tincture",
	&"holy_consecration",
	&"smoke_warding",
	&"flight_preparation",
]

# Number of copies of each card type in the deck (5 types × 5 copies = 25 total).
const _COPIES_PER_TYPE: int = 5


# === Private Variables ===

var _current_village_index: int = -1
# How many villages have been fully cleared in the current run.
var _villages_completed: int = 0
# All VILLAGES_PER_CAMPAIGN villages pre-generated at campaign start.
var _villages: Array[VillageData] = []
# village_index → Array[ModifierCard]
var _modifier_assignments: Dictionary = {}
var _houses_cleared: int = 0
var _active: bool = false


# === Lifecycle ===

func _ready() -> void:
	WaveManager.wave_complete.connect(_on_wave_complete)
	MoraleManager.fail_state_reached.connect(_on_fail_state_reached)


# === Public API ===

func start_campaign() -> void:
	_active = true
	_villages_completed = 0
	_villages.clear()
	_modifier_assignments.clear()

	for i: int in GameConfig.VILLAGES_PER_CAMPAIGN:
		var village: VillageData = VillageGenerator.generate_village(i, randi())
		_villages.append(village)

	_assign_modifier_deck()
	TechTreeManager.reset()


func enter_village(village_index: int) -> void:
	_begin_village(village_index)
	if village_index == 0:
		DraftManager.generate_starter_draft()


func get_current_village_index() -> int:
	return _current_village_index


func get_villages_completed() -> int:
	return _villages_completed


func get_houses_cleared_this_village() -> int:
	return _houses_cleared


func is_active() -> bool:
	return _active


func get_modifier_cards_for_village(village_index: int) -> Array[ModifierCard]:
	var cards: Array = _modifier_assignments.get(village_index, [])
	var result: Array[ModifierCard] = []
	for card: ModifierCard in cards:
		result.append(card)
	return result


# === Private — Village Lifecycle ===

func get_current_village_data() -> VillageData:
	if _current_village_index < 0 or _current_village_index >= _villages.size():
		return null
	return _villages[_current_village_index]


func _begin_village(village_index: int) -> void:
	_current_village_index = village_index
	_houses_cleared = 0

	var village: VillageData = _villages[village_index]
	village.modifier_cards = get_modifier_cards_for_village(village_index)

	NavigationManager.setup(village.exit_tiles)
	MoraleManager.reset()
	village_started.emit(village)


func _on_wave_complete(
	_house: Node,
	_all_infected: bool,
	_escaped_count: int,
	_infected_count: int
) -> void:
	print("[CampaignManager] _on_wave_complete — active=", _active,
			" houses_cleared(prev)=", _houses_cleared,
			" HOUSES_PER_VILLAGE=", GameConfig.HOUSES_PER_VILLAGE)
	if not _active:
		push_warning("[CampaignManager] wave_complete fired but _active is FALSE — draft will NOT be generated")
		return

	_houses_cleared += 1

	if _houses_cleared >= GameConfig.HOUSES_PER_VILLAGE:
		_complete_village()
	else:
		var pool: Array[StringName] = GameConfig.BASE_TOWER_TYPES.duplicate()
		pool.append_array(TechTreeManager.get_unlocked_synthesis_towers())
		print("[CampaignManager] generating post-wave draft, pool size=", pool.size())
		DraftManager.generate_draft(pool)
		TechTreeManager.add_points(GameConfig.TECH_POINTS_PER_WAVE)


func _complete_village() -> void:
	DraftManager.reset()
	TowerManager.clear_all()
	EntityManager.despawn_all_of_type(&"villager")

	_villages_completed += 1
	var finished_index: int = _current_village_index
	village_complete.emit(finished_index)

	if finished_index >= GameConfig.VILLAGES_PER_CAMPAIGN - 1:
		_active = false
		campaign_won.emit()


func _on_fail_state_reached() -> void:
	if not _active:
		return
	_active = false
	WaveManager.reset()
	TowerManager.clear_all()
	EntityManager.despawn_all_of_type(&"villager")
	campaign_failed.emit(&"morale_fail")


# === Private — Modifier Deck ===

func _assign_modifier_deck() -> void:
	var deck: Array[ModifierCard] = _build_deck()
	# Shuffle using the built-in (global RNG — campaign starts are player-driven, not seeded)
	deck.shuffle()

	var draw_index: int = 0
	for village_index: int in GameConfig.VILLAGES_PER_CAMPAIGN:
		var cards_for_village: Array[ModifierCard] = []
		var card_count: int = GameConfig.MODIFIER_CARDS_PER_VILLAGE[village_index]
		for _i: int in card_count:
			if draw_index < deck.size():
				cards_for_village.append(deck[draw_index])
				draw_index += 1
		_modifier_assignments[village_index] = cards_for_village


func _build_deck() -> Array[ModifierCard]:
	var deck: Array[ModifierCard] = []
	for card_type: StringName in _MODIFIER_CARD_TYPES:
		for _i: int in _COPIES_PER_TYPE:
			var card := ModifierCard.new()
			card.card_type = card_type
			deck.append(card)
	return deck
