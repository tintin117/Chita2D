@tool  # ponytail: only so the in-editor test runner can read it
class_name Arenas extends RefCounted
## Every map a match can be played on. To add a hand-made level, save its scene in scenes/levels and add a row.
## The index travels over the network (Net.arena), so every peer must have the same list in the same order.

const LIST := [
	{"name": "Four Quarters", "scene": "res://scenes/levels/iso_arena.tscn",
		"blurb": "Four crown approaches, with cover and paths around the offset ponds."},
	{"name": "Pillar Court", "scene": "res://scenes/levels/pillar_court.tscn",
		"blurb": "An open court with four pillar terraces and narrow lanes beside the pools."},
	{"name": "Three Bridges", "scene": "res://scenes/levels/three_bridges.tscn",
		"blurb": "Push the short stone bridge or flank through two bent timber crossings."},
	{"name": "The Wheel", "scene": "res://scenes/levels/wheel.tscn",
		"blurb": "Fight around the outer track or cut across four spokes with cover at the landings."},
	{"name": "Archipelago", "scene": "res://scenes/levels/archipelago.tscn",
		"blurb": "Follow the docks to the crown or dash across the stepping islands."},
	{"name": "Colosseum", "scene": "res://scenes/levels/colosseum.tscn",
		"blurb": "An open fighting bowl framed by ruined sandstone arcades and braziers."},
	{"name": "Brookside Village", "scene": "res://scenes/levels/market_square.tscn",
		"blurb": "Clash at the market bend or flank through the orchard and back lane."},
	{"name": "Forest Shrine", "scene": "res://scenes/levels/forest_shrine.tscn",
		"blurb": "Fight across ruined stone terraces or circle through the pines."},
]

static func info(index: int) -> Dictionary:
	return LIST[clampi(index, 0, LIST.size() - 1)]

## A new map node, not generated yet: add it to the tree, then call generate_arena().
static func create(index: int) -> WorldMap:
	var path: String = info(index).scene
	return WorldMap.new() if path == "" else (load(path) as PackedScene).instantiate()
