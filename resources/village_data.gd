class_name VillageData
extends Resource
## Complete procedural layout for one village — houses, obstacles, exit, modifier cards.


# === Exports ===

@export var village_index: int = 0
@export var houses: Array[HouseData] = []
@export var obstacle_tiles: Array[Vector2i] = []
@export var exit_tiles: Array[Vector2i] = []
## Filled by CampaignManager after generation; empty when VillageGenerator returns.
@export var modifier_cards: Array[ModifierCard] = []
