@tool  # ponytail: only so the in-editor test runner can read it
class_name Arenas extends RefCounted
## Every map a match can be played on. To add a hand-made level, save its scene in scenes/levels and add a row.
## The index travels over the network (Net.arena), so every peer must have the same list in the same order.

const LIST := [
	{"name": "Four Quarters", "scene": "res://scenes/levels/iso_arena.tscn",
		"blurb": "All-round. A moated crown circle, four bridges, four pools."},
	{"name": "Pillar Court", "scene": "res://scenes/levels/pillar_court.tscn",
		"blurb": "Tight duels. Four big pillars to break line of sight."},
	{"name": "Three Bridges", "scene": "res://scenes/levels/three_bridges.tscn",
		"blurb": "Team lanes. Two home islands, three ways across."},
	{"name": "The Wheel", "scene": "res://scenes/levels/wheel.tscn",
		"blurb": "Ring-outs. A loop round the water, four spokes to the hub."},
	{"name": "Archipelago", "scene": "res://scenes/levels/archipelago.tscn",
		"blurb": "Mobility. Walk the bridges or dash the gaps."},
	{"name": "Colosseum", "scene": "",
		"blurb": "The current main-game map, for comparison."},
]

static func info(index: int) -> Dictionary:
	return LIST[clampi(index, 0, LIST.size() - 1)]

## A new map node, not generated yet: add it to the tree, then call generate_arena().
static func create(index: int) -> WorldMap:
	var path: String = info(index).scene
	return WorldMap.new() if path == "" else (load(path) as PackedScene).instantiate()
