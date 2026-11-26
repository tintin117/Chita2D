class_name Colosseum extends RefCounted
## The main PvP map, laid out from the reference arena image (docs: design_pillars_and_crown_mode.md, Map).
## Every shape is written in the image's pixel space (2000 x 1414, centre IMG_C) and scaled by S into the world, so
## the collision, the deadly water, the spawns and the placeholder art all come from this one list.
##
## Layout: a stadium-shaped sand floor walled in by the stands. Deadly water: four corner pools and a moat ring round
## the centre. The centre is a stone circle (the crown spawns there) with a low rail round it, reached by two bridges
## from raised side platforms; each platform has stairs at both ends. Low rails block walking but not shots, and a
## dash or a leap goes over them (Player.LOW_MASK). Four braziers are solid cover.

const S := 1.44                                 ## image px -> world px (1.44: the floor is ~2450 x 1450 px)
const IMG_C := Vector2(1000, 707)
const FLOOR := Rect2(150, 205, 1700, 1005)      ## the sand inside the stands
const CORNER := 330.0                           ## its corner radius
const POOLS := [Rect2(548, 205, 252, 285), Rect2(1200, 205, 252, 285), Rect2(548, 925, 252, 285), Rect2(1200, 925, 252, 285)]
const POOL_CUT := 400.0                         ## the pools' inner corners are cut by this circle round the centre
const MOAT := Vector2(230, 310)                 ## inner / outer radius of the moat ring
const BRIDGE_HALF := 60.0                       ## the bridges cross the moat where |y| < this
const PLATFORMS := [Rect2(290, 545, 140, 325), Rect2(1570, 545, 140, 325)]
const STAIRS := [Rect2(330, 450, 95, 95), Rect2(330, 870, 95, 90), Rect2(1575, 450, 95, 95), Rect2(1575, 870, 95, 90)]
const BRIDGES := [Rect2(430, 647, 346, 120), Rect2(1224, 647, 346, 120)]
const RING_RAIL := 232.0
## The braziers stand in the pools' inner corners, so the sand band between the pools and the moat stays walkable.
const BRAZIERS := [Vector2(709, 377), Vector2(1291, 377), Vector2(709, 1037), Vector2(1291, 1037)]
const SPAWNS := [Vector2(1000, 290), Vector2(1765, 707), Vector2(1000, 1125), Vector2(235, 707),
	Vector2(320, 320), Vector2(1680, 320), Vector2(1680, 1095), Vector2(320, 1095)]
const RAIL_W := 18.0                            ## world px
const BRAZIER_HALF := 48.0                      ## image px: half the brazier's side (its collision radius is this x S)

var center := Vector2.ZERO   ## world position of IMG_C

func _init(world_center: Vector2) -> void:
	center = world_center

func to_world(img: Vector2) -> Vector2:
	return center + (img - IMG_C) * S

func to_img(world: Vector2) -> Vector2:
	return (world - center) / S + IMG_C

## True inside a rect with rounded corners (image space).
static func in_round_rect(p: Vector2, r: Rect2, radius: float) -> bool:
	if not r.has_point(p):
		return false
	var cx := clampf(p.x, r.position.x + radius, r.end.x - radius)
	var cy := clampf(p.y, r.position.y + radius, r.end.y - radius)
	return p.distance_to(Vector2(cx, cy)) <= radius

## Inside the stands (sand, stone or water alike).
func inside(world: Vector2) -> bool:
	return in_round_rect(to_img(world), FLOOR, CORNER)

## Deadly water inside the arena (pools, moat). Outside the stands is not water: that is wall.
func water_at(world: Vector2) -> bool:
	var p := to_img(world)
	if not in_round_rect(p, FLOOR, CORNER):
		return false
	var d := p.distance_to(IMG_C)
	if d >= MOAT.x and d <= MOAT.y and absf(p.y - IMG_C.y) > BRIDGE_HALF:
		return true
	if d > POOL_CUT:
		for r: Rect2 in POOLS:
			if r.has_point(p):
				return true
	return false

## Standing ground: inside the stands and not water.
func floor_at(world: Vector2) -> bool:
	return inside(world) and not water_at(world)

func spawns() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p: Vector2 in SPAWNS:
		out.append(to_world(p))
	return out

func braziers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p: Vector2 in BRAZIERS:
		out.append(to_world(p))
	return out

## The low rails as world segments [a, b]: round the centre circle (open where the bridges join), along both sides of
## each bridge, and round the side platforms (open at the stairs and where the bridge leaves).
func rails() -> Array[PackedVector2Array]:
	var img: Array[PackedVector2Array] = []
	var gap := asin(BRIDGE_HALF / RING_RAIL)
	for arc: Vector2 in [Vector2(gap, PI - gap), Vector2(PI + gap, TAU - gap)]:
		var steps := 12
		for i in steps:
			var a0 := lerpf(arc.x, arc.y, float(i) / steps)
			var a1 := lerpf(arc.x, arc.y, float(i + 1) / steps)
			img.append(PackedVector2Array([IMG_C + Vector2.from_angle(a0) * RING_RAIL, IMG_C + Vector2.from_angle(a1) * RING_RAIL]))
	for b: Rect2 in BRIDGES:
		img.append(PackedVector2Array([Vector2(b.position.x, b.position.y), Vector2(b.end.x, b.position.y)]))
		img.append(PackedVector2Array([Vector2(b.position.x, b.end.y), Vector2(b.end.x, b.end.y)]))
	var first: Rect2 = BRIDGES[0]
	var top := first.position.y
	var bot := first.end.y
	for i in PLATFORMS.size():
		var r: Rect2 = PLATFORMS[i]
		var outer := r.position.x if i == 0 else r.end.x
		var inner := r.end.x if i == 0 else r.position.x
		img.append(PackedVector2Array([Vector2(outer, r.position.y), Vector2(outer, r.end.y)]))
		img.append(PackedVector2Array([Vector2(inner, r.position.y), Vector2(inner, top)]))
		img.append(PackedVector2Array([Vector2(inner, bot), Vector2(inner, r.end.y)]))
		var stair: Rect2 = STAIRS[i * 2]
		var near := stair.position.x if i == 0 else stair.end.x   # the short ledge beside the stairs, on the outer side
		for y: float in [r.position.y, r.end.y]:
			img.append(PackedVector2Array([Vector2(outer, y), Vector2(near, y)]))
	var out: Array[PackedVector2Array] = []
	for seg in img:
		out.append(PackedVector2Array([to_world(seg[0]), to_world(seg[1])]))
	return out
