class_name ModifierCard
extends Resource
## A village-wide modifier drawn from the campaign modifier deck.


# === Constants ===

const LABELS: Dictionary = {
	&"quarantine_edict":      "Quarantine Edict — fewer exits",
	&"apothecaries_tincture": "Apothecary's Tincture — +infection resistance",
	&"holy_consecration":     "Holy Consecration — priests resist all effects",
	&"smoke_warding":         "Smoke Warding — reduced tower range",
	&"flight_preparation":    "Flight Preparation — villagers move faster",
}

const SHORT_LABELS: Dictionary = {
	&"quarantine_edict":      "QE",
	&"apothecaries_tincture": "AT",
	&"holy_consecration":     "HC",
	&"smoke_warding":         "SW",
	&"flight_preparation":    "FP",
}


# === Exports ===

## "quarantine_edict" | "apothecaries_tincture" | "holy_consecration" |
## "smoke_warding" | "flight_preparation"
@export var card_type: StringName = &""
@export var description: String = ""


func get_label() -> String:
	return LABELS.get(card_type, str(card_type))


func get_short_label() -> String:
	return SHORT_LABELS.get(card_type, "?")
