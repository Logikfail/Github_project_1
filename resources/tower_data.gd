class_name TowerData
extends Resource
## Stats and configuration for one tower type.
## Instances stored as .tres in data/towers/; all balancing values live there.


# === Exports ===

@export var tower_type: StringName = &""
## Shape constant: single | circle_aoe | cone | line | chain | targeted_aoe | expanding_aoe
@export var attack_shape: StringName = &"single"
@export var default_targeting_mode: StringName = &"closest"
@export var fire_rate: float = 1.0           # seconds between fire cycles
@export var range_radius: float = 128.0      # max targeting range (world units)
@export var aoe_radius: float = 64.0         # circle_aoe / targeted_aoe / expanding_aoe max radius
@export var cone_angle: float = 60.0         # degrees; cone shape only
@export var chain_count: int = 3             # total targets hit per fire cycle; chain shape only
@export var expanding_speed: float = 80.0   # world units per second; expanding_aoe only
@export var infection_effects: Array[InfectionEffect] = []
