class_name GameMode extends RefCounted
## Match modes. Classic: everyone picks a hero, a few drops now and then. Friendslop: everyone is the same modest Bonker
## (LMB bonk + RMB shove) and the power comes from the drops, which fall often and in numbers.
## The host picks the mode (Net.mode) and it travels with the match start, so every peer reads the same CONFIG row.

const CLASSIC := "classic"
const FRIENDSLOP := "friendslop"
const MODES := [CLASSIC, FRIENDSLOP]

## pickup_every / first_pickup: seconds between drops / until the first one. max_pickups: drops lying around at once.
## spawn_clear / apart: how far a drop stays from player spawns / other drops (smaller spawn_clear = drops spread over the whole arena).
const CONFIG := {
	CLASSIC: {"name": "Classic", "blurb": "Pick a hero, fight it out.", "hero_pick": true, "hero": "",
		"pickup_every": 12.0, "first_pickup": 6.0, "max_pickups": 3, "spawn_clear": 380.0, "apart": 300.0,
		"kill_limit": 15, "time_limit": 300.0, "weapons": false},
	FRIENDSLOP: {"name": "Friendslop", "blurb": "Same hero for all. Loot the drops, wreck your friends.", "hero_pick": false, "hero": "bonker",
		"pickup_every": 4.5, "first_pickup": 1.5, "max_pickups": 5, "spawn_clear": 250.0, "apart": 350.0,
		"kill_limit": 20, "time_limit": 300.0, "weapons": true},
}

static func valid(mode: String) -> bool:
	return CONFIG.has(mode)

## The config row of a mode (unknown ids fall back to Classic).
static func cfg(mode: String) -> Dictionary:
	return CONFIG.get(mode, CONFIG[CLASSIC])

static func is_friendslop(mode: String) -> bool:
	return mode == FRIENDSLOP

static func next(mode: String) -> String:
	return MODES[(MODES.find(mode) + 1) % MODES.size()]

static func title(mode: String) -> String:
	return cfg(mode).name
