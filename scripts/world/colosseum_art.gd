class_name ColosseumArt extends Node2D
## Visuals share the pool, bridge and rail geometry used by Colosseum.

const SAND := Color("#967e5b")
const STONE := Color("#a49b82")
const RIM := Color("#514b47")
const WATER := Color("#244655")
const WATER_EDGE := Color("#426978")
const RAIL := Color("#44463f")
const POST := Color("#938066")
const GOLD := Color("#c49859")
const FIRE := Color("#ffa53a")
const HALF_TILE := Vector2(32.0, 16.0)

var shape: Colosseum
var _rng := RandomNumberGenerator.new()

func w(img: Vector2) -> Vector2:
	return (img - Colosseum.IMG_C) * Colosseum.S

func _rect(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([w(r.position), w(Vector2(r.end.x, r.position.y)), w(r.end), w(Vector2(r.position.x, r.end.y))])

func _round_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(r.end.x - radius, r.position.y + radius), Vector2(r.end.x - radius, r.end.y - radius),
		Vector2(r.position.x + radius, r.end.y - radius), Vector2(r.position.x + radius, r.position.y + radius)]
	for i in 4:
		for k in 13:
			var a := (i - 1) * PI * 0.5 + PI * 0.5 * k / 12.0
			pts.append(w(corners[i] + Vector2.from_angle(a) * radius))
	return pts

func _ellipse(center: Vector2, radius: Vector2, steps := 64) -> PackedVector2Array:
	var rim := PackedVector2Array()
	for step in steps:
		rim.append(center + Vector2.from_angle(TAU * step / steps) * radius)
	return rim

func _outline(polygon: PackedVector2Array, color: Color, width: float) -> void:
	draw_polyline(polygon + PackedVector2Array([polygon[0]]), color, width)

func _draw() -> void:
	var f := Colosseum.FLOOR
	var floor := _round_rect(f, Colosseum.CORNER)
	draw_rect(Rect2(w(f.grow(760.0).position), f.grow(760.0).size * Colosseum.S), Color("#232427"))
	_stands(f)
	_rng.seed = 4242
	_masonry(floor, SAND, false)
	for pool: Rect2 in Colosseum.POOLS:
		for clipped in Geometry2D.intersect_polygons(floor, _rect(pool)):
			draw_colored_polygon(clipped, WATER)
			_outline(clipped, WATER_EDGE, 3.0)
		_ripples(pool, 12, func(at: Vector2) -> bool:
			return shape.water_at(shape.to_world(at)) and at.distance_to(Colosseum.IMG_C) > Colosseum.POOL_CUT + 24.0)
	# The inner corners of the pools are cut out by this dry band.
	var cut := Colosseum.POOL_CUT * Colosseum.S
	_masonry(_ellipse(Vector2.ZERO, Vector2.ONE * cut), SAND, false)
	var moat := Colosseum.MOAT.y * Colosseum.S
	var dais := Colosseum.MOAT.x * Colosseum.S
	var rim := _ellipse(Vector2.ZERO, Vector2.ONE * moat)
	draw_colored_polygon(rim, WATER)
	_outline(rim, WATER_EDGE, 4.0)
	_ripples(Rect2(Colosseum.IMG_C - Vector2.ONE * Colosseum.MOAT.y, Vector2.ONE * Colosseum.MOAT.y * 2.0), 85,
		func(at: Vector2) -> bool:
			var radius := at.distance_to(Colosseum.IMG_C)
			return radius > Colosseum.MOAT.x + 20.0 and radius < Colosseum.MOAT.y - 14.0)
	var terrace := _ellipse(Vector2.ZERO, Vector2.ONE * dais)
	draw_colored_polygon(Transform2D(0.0, Vector2(0, 11)) * terrace, STONE.darkened(0.42))
	_masonry(terrace, STONE, true)
	_outline(terrace, STONE.lightened(0.15), 3.0)
	_crown_mosaic()
	for causeway: Rect2 in Colosseum.POOL_CAUSEWAYS:
		var deck := _rect(causeway)
		draw_colored_polygon(Transform2D(0.0, Vector2(0, 8)) * deck, RIM.darkened(0.25))
		_masonry(deck, Color("#8d765b"), true)
	for bridge: Rect2 in Colosseum.BRIDGES:
		var deck := _rect(bridge)
		draw_colored_polygon(Transform2D(0.0, Vector2(0, 12)) * deck, RIM.darkened(0.25))
		_masonry(deck, STONE, true)
	for platform: Rect2 in Colosseum.PLATFORMS:
		var deck := _rect(platform)
		draw_colored_polygon(Transform2D(0.0, Vector2(0, 10)) * deck, RIM.darkened(0.30))
		_masonry(deck, STONE, true)
		_outline(deck, STONE.lightened(0.14), 3.0)
	for stair: Rect2 in Colosseum.STAIRS:
		draw_colored_polygon(_rect(stair), STONE.darkened(0.14))
		for step in range(1, 7):
			var y := lerpf(stair.position.y, stair.end.y, step / 7.0)
			var from := w(Vector2(stair.position.x, y))
			var to := w(Vector2(stair.end.x, y))
			draw_line(from + Vector2(0, 3), to + Vector2(0, 3), RIM, 5.0)
			draw_line(from, to, STONE.lightened(0.13), 2.0)
	_rails()

func _stands(floor: Rect2) -> void:
	for tier in range(4, 0, -1):
		var width := 48.0 * tier
		var rim := _round_rect(floor.grow(width), Colosseum.CORNER + width)
		var rise := Vector2(0.0, -9.0 * tier)
		draw_colored_polygon(Transform2D(0.0, rise) * rim, RIM.lightened(tier * 0.035))
		_outline(Transform2D(0.0, rise) * rim, Color("#302b2a"), 9.0)
		_outline(Transform2D(0.0, rise + Vector2(0, -6)) * rim, Color("#797065"), 3.0)
	var points := _round_rect(floor.grow(35.0), Colosseum.CORNER + 35.0)
	for i in range(0, points.size(), 3):
		var foot := points[i]
		draw_line(foot, foot + Vector2(0, -23), POST, 5.0)
		draw_circle(foot + Vector2(0, -25), 4.0, FIRE)
	for gate: Vector2 in [Vector2(1000, 175), Vector2(1000, 1228), Vector2(105, 707), Vector2(1895, 707)]:
		var at := w(gate)
		for side: float in [-1.0, 1.0]:
			var foot := at + Vector2(side * 42.0, 0.0)
			draw_colored_polygon(_ellipse(foot, Vector2(16, 8), 8), RIM.darkened(0.4))
			draw_line(foot, foot + Vector2(0, -49), POST, 15.0)
			draw_line(foot + Vector2(-4, -7), foot + Vector2(-4, -47), STONE, 3.0)
		var pennant := PackedVector2Array([at + Vector2(-28, -44), at + Vector2(28, -44),
			at + Vector2(28, -6), at + Vector2(0, 8), at + Vector2(-28, -6)])
		draw_colored_polygon(pennant, Color("#723f3a"))
		draw_line(pennant[0], pennant[1], GOLD, 4.0)

func _masonry(outline: PackedVector2Array, base: Color, joints: bool) -> void:
	draw_colored_polygon(outline, base)
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		bounds = bounds.expand(p)
	for y in range(floori(bounds.position.y / HALF_TILE.y), ceili(bounds.end.y / HALF_TILE.y) + 1):
		for x in range(floori(bounds.position.x / 64.0) - 1, ceili(bounds.end.x / 64.0) + 1):
			var at := Vector2(64 * x + 32 * posmod(y, 2), HALF_TILE.y * y)
			var diamond := PackedVector2Array([at - Vector2(0, HALF_TILE.y),
				at + Vector2(HALF_TILE.x, 0), at + Vector2(0, HALF_TILE.y), at - Vector2(HALF_TILE.x, 0)])
			# Sample by coordinates so the sand inside the cut matches the surrounding floor.
			var noise := posmod(x * 239 + y * 97 + x * y * 11, 17) / 100.0 - 0.08
			var color := base.lightened(noise) if noise > 0.0 else base.darkened(-noise)
			for polygon in Geometry2D.intersect_polygons(outline, diamond):
				draw_colored_polygon(polygon, color)
				if joints:
					_outline(polygon, base.darkened(0.15), 1.5)
				elif posmod(x * 13 + y * 17, 7) == 0 and Geometry2D.is_point_in_polygon(at, polygon):
					draw_line(at + Vector2(-3, 1), at + Vector2(3, -2), base.darkened(0.16), 2.0)

func _crown_mosaic() -> void:
	for radius in [106.0, 139.0]:
		var ring := _ellipse(Vector2.ZERO, Vector2(radius, radius * 0.5))
		_outline(ring, RIM, 6.0)
		_outline(ring, GOLD, 3.0)
	for i in 8:
		var a := Vector2.from_angle(i * TAU / 8.0)
		draw_line(a * Vector2(110, 55), a * Vector2(135, 67.5), GOLD, 3.0)

func _ripples(area: Rect2, count: int, keep: Callable) -> void:
	for i in count:
		var sample := Vector2(_rng.randf_range(area.position.x, area.end.x),
			_rng.randf_range(area.position.y, area.end.y))
		if not keep.call(sample):
			continue
		var at := w(sample)
		var width := _rng.randf_range(10.0, 32.0)
		draw_line(at - Vector2(width, 0), at + Vector2(width, 0), WATER_EDGE, 2.0)
		if i % 3 == 0:
			draw_line(at + Vector2(4, 5), at + Vector2(width + 8, 5), WATER_EDGE.darkened(0.16), 2.0)

func _rails() -> void:
	for segment in shape.rails():
		var a: Vector2 = segment[0] - shape.center
		var b: Vector2 = segment[1] - shape.center
		var rise := Vector2(0.0, -16.0)
		draw_line(a, b, RAIL, Colosseum.RAIL_W)
		if absf(a.x - b.x) > 0.01:
			draw_colored_polygon(PackedVector2Array([a, b, b + rise, a + rise]), RAIL)
		draw_line(a + rise, b + rise, POST, 5.0)
		for foot in [a, b]:
			draw_line(foot, foot + rise, POST.darkened(0.15), 8.0)
			draw_circle(foot + rise, 5.0, STONE)

## A separate y-sorted child of the matching solid body.
class Brazier extends Node2D:
	func _draw() -> void:
		var r := Colosseum.BRAZIER_HALF * Colosseum.S
		var foot := PackedVector2Array([Vector2(0, -r * .45), Vector2(r, 0),
			Vector2(0, r * .45), Vector2(-r, 0)])
		draw_colored_polygon(Transform2D(0.0, Vector2(4, 11)) * foot, Color(0.05, 0.08, 0.1, 0.55))
		draw_colored_polygon(foot, RAIL)
		var bowl := Transform2D(0.0, Vector2(.78, .78), 0.0, Vector2(0, -37)) * foot
		draw_colored_polygon(PackedVector2Array([foot[3], foot[2], bowl[2], bowl[3]]), RIM)
		draw_colored_polygon(PackedVector2Array([foot[2], foot[1], bowl[1], bowl[2]]), RIM.darkened(0.27))
		draw_colored_polygon(bowl, POST)
		draw_colored_polygon(Transform2D(0.0, Vector2(.61, .61), 0.0, Vector2(0, -37)) * foot, Color("#46342d"))
		draw_colored_polygon(PackedVector2Array([Vector2(-20, -43), Vector2(-17, -62), Vector2(-6, -54),
			Vector2(5, -81), Vector2(10, -63), Vector2(21, -68), Vector2(19, -45), Vector2(5, -37)]), FIRE)
		draw_colored_polygon(PackedVector2Array([Vector2(-10, -45), Vector2(-4, -60), Vector2(2, -54),
			Vector2(9, -64), Vector2(12, -47), Vector2(4, -40)]), Color("#ffe1a0"))
