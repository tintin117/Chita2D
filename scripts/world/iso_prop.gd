@tool
extends Sprite2D
## A tileset sprite placed freely (off the grid). Drag iso_prop.tscn under a level's FreeProps node, pick `tile`,
## move it anywhere. The node's position is the spot on the ground it stands on.

@export_range(0, 120) var tile := 53:
	set(v):
		tile = v
		region_rect = Rect2((v % 11) * 32, floori(v / 11.0) * 32, 32, 32)
@export var solid_radius := 0.0   ## > 0: blocks walking and shots (world px)
