class_name ColosseumArt extends Node2D
## Placeholder art for the Colosseum, drawn from the same shapes as its collision (Colosseum), so what you see is
## exactly where the water, rails and braziers are. Swap for real art later: keep the shapes, replace the drawing.
## Sits at the map's centre, under everything (WorldMap puts it in the ground layer).

const SAND := Color("#d98f45")
const SAND_LINE := Color("#c47c38")
const STONE := Color("#cfc6b4")
const STONE_LINE := Color("#b0a690")
const RIM := Color("#4a4440")
const STANDS := Color("#33251f")
const TENT := Color("#b8302a")
const WATER := Color("#1d5a75")
const WATER_EDGE := Color("#2d7d9c")
const RAIL := Color("#5c564e")
const POST := Color("#77706a")
const FIRE := Color("#ffa53a")

var shape: Colosseum
var _rng := RandomNumberGenerator.new()
const TILE := 50.0   ## image px: the floor's tile grid

## Image px -> this node's local px.
func w(img: Vector2) -> Vector2:
	return (img - Colosseum.IMG_C) * Colosseum.S

func wr(r: Rect2) -> Rect2:
	return Rect2(w(r.position), r.size * Colosseum.S)

## A rounded rectangle as a polygon (image space in, local out).
func round_rect(r: Rect2, radius: float, steps := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(r.end.x - radius, r.position.y + radius), Vector2(r.end.x - radius, r.end.y - radius),
		Vector2(r.position.x + radius, r.end.y - radius), Vector2(r.position.x + radius, r.position.y + radius)]
	var start := [-PI / 2.0, 0.0, PI / 2.0, PI]
	for i in 4:
		for k in steps + 1:
			var a: float = start[i] + PI / 2.0 * k / steps
			pts.append(w(corners[i] + Vector2.from_angle(a) * radius))
	return pts

func _draw() -> void:
	var f := Colosseum.FLOOR
	# the stands and the ring of red awnings round them
	draw_rect(wr(f.grow(420.0)), STANDS)
	var tents := round_rect(f.grow(250.0), Colosseum.CORNER + 250.0, 16)
	draw_polyline(tents + PackedVector2Array([tents[0]]), TENT, 150.0 * Colosseum.S)
	for i in range(0, tents.size(), 3):   # seams between awnings
		draw_line(tents[i] * 0.93, tents[i] * 1.07, Color(TENT.darkened(0.45), 0.8), 4.0)
	draw_colored_polygon(round_rect(f.grow(55.0), Colosseum.CORNER + 55.0), RIM)
	# the gates: statues top and bottom, an entrance left and right
	for g: Rect2 in [Rect2(870, 110, 260, 110), Rect2(870, 1195, 260, 110), Rect2(70, 600, 95, 215), Rect2(1835, 600, 95, 215)]:
		draw_rect(wr(g), RIM.darkened(0.3))
		draw_rect(wr(g.grow(-18.0)), Color("#6b625b"))
	# sand and its tile grid
	draw_colored_polygon(round_rect(f, Colosseum.CORNER), SAND)
	_rng.seed = 4242   # the noise is the same on every screen and every run
	_tile_noise(f, SAND, 0.06, func(c: Vector2) -> bool: return Colosseum.in_round_rect(c, f, Colosseum.CORNER - 40.0))
	_speckles(f, 1400, func(c: Vector2) -> bool: return Colosseum.in_round_rect(c, f, Colosseum.CORNER - 10.0))
	var y := f.position.y + 50.0
	while y < f.end.y:
		var x := _half_width(y)
		draw_line(w(Vector2(Colosseum.IMG_C.x - x, y)), w(Vector2(Colosseum.IMG_C.x + x, y)), SAND_LINE, 1.0)
		y += 50.0
	var x0 := f.position.x + 50.0
	while x0 < f.end.x:
		var h := _half_height(x0)
		draw_line(w(Vector2(x0, Colosseum.IMG_C.y - h)), w(Vector2(x0, Colosseum.IMG_C.y + h)), SAND_LINE, 1.0)
		x0 += 50.0
	# torches on the rim
	var rim := round_rect(f.grow(28.0), Colosseum.CORNER + 28.0, 10)
	for i in range(0, 44):
		var p := rim[(i * rim.size()) / 44]
		draw_circle(p, 6.0, FIRE)
	# the corner pools, their inner corners cut by a circle of sand round the centre
	for r: Rect2 in Colosseum.POOLS:
		draw_rect(wr(r), WATER)
		draw_rect(wr(r.grow(-10.0)), WATER_EDGE, false, 3.0)
	for r: Rect2 in Colosseum.POOLS:
		_ripples(r, 14, func(c: Vector2) -> bool: return c.distance_to(Colosseum.IMG_C) > Colosseum.POOL_CUT + 20.0)
	draw_circle(Vector2.ZERO, Colosseum.POOL_CUT * Colosseum.S, SAND)
	var band := Rect2(Colosseum.IMG_C - Vector2.ONE * Colosseum.POOL_CUT, Vector2.ONE * Colosseum.POOL_CUT * 2.0)
	_tile_noise(band, SAND, 0.06, func(c: Vector2) -> bool: return c.distance_to(Colosseum.IMG_C) < Colosseum.POOL_CUT - 40.0)
	_speckles(band, 300, func(c: Vector2) -> bool: return c.distance_to(Colosseum.IMG_C) < Colosseum.POOL_CUT - 8.0)
	draw_arc(Vector2.ZERO, Colosseum.POOL_CUT * Colosseum.S, 0.0, TAU, 64, SAND_LINE, 2.0)
	# the moat and the centre circle
	draw_circle(Vector2.ZERO, Colosseum.MOAT.y * Colosseum.S, WATER)
	draw_arc(Vector2.ZERO, (Colosseum.MOAT.y - 12.0) * Colosseum.S, 0.0, TAU, 64, WATER_EDGE, 3.0)
	var moat := Rect2(Colosseum.IMG_C - Vector2.ONE * Colosseum.MOAT.y, Vector2.ONE * Colosseum.MOAT.y * 2.0)
	_ripples(moat, 22, func(c: Vector2) -> bool:
		var d := c.distance_to(Colosseum.IMG_C)
		return d > Colosseum.MOAT.x + 12.0 and d < Colosseum.MOAT.y - 12.0)
	draw_circle(Vector2.ZERO, Colosseum.MOAT.x * Colosseum.S, STONE)
	var circle := Rect2(Colosseum.IMG_C - Vector2.ONE * Colosseum.MOAT.x, Vector2.ONE * Colosseum.MOAT.x * 2.0)
	_tile_noise(circle, STONE, 0.05, func(c: Vector2) -> bool: return c.distance_to(Colosseum.IMG_C) < Colosseum.MOAT.x - 36.0)
	for k in range(-4, 5):   # floor tiles on the circle
		var off := k * 50.0
		var half := sqrt(maxf(Colosseum.MOAT.x * Colosseum.MOAT.x - off * off, 0.0))
		draw_line(w(Colosseum.IMG_C + Vector2(-half, off)), w(Colosseum.IMG_C + Vector2(half, off)), STONE_LINE, 1.0)
		draw_line(w(Colosseum.IMG_C + Vector2(off, -half)), w(Colosseum.IMG_C + Vector2(off, half)), STONE_LINE, 1.0)
	for rr in [95.0, 75.0, 55.0]:   # the ring in the middle: where the crown appears
		draw_arc(Vector2.ZERO, rr * Colosseum.S, 0.0, TAU, 48, Color("#a5786a"), 7.0)
	# bridges, side platforms and their stairs
	for b: Rect2 in Colosseum.BRIDGES:
		draw_rect(wr(b), STONE)
		_tile_noise(b, STONE, 0.05, func(c: Vector2) -> bool: return b.grow(-25.0).has_point(c))
		var bx := b.position.x + 50.0
		while bx < b.end.x:
			draw_line(w(Vector2(bx, b.position.y)), w(Vector2(bx, b.end.y)), STONE_LINE, 1.0)
			bx += 50.0
	for pl: Rect2 in Colosseum.PLATFORMS:
		draw_rect(wr(pl.grow(6.0)), Color(0, 0, 0, 0.25))   # a drop shadow: it is raised
		draw_rect(wr(pl), STONE)
		_tile_noise(pl, STONE, 0.05, func(c: Vector2) -> bool: return pl.grow(-25.0).has_point(c))
		draw_rect(wr(pl), STONE_LINE, false, 2.0)
	for st: Rect2 in Colosseum.STAIRS:
		draw_rect(wr(st), Color("#a89c8a"))
		var sy := st.position.y + 12.0
		while sy < st.end.y:
			draw_line(w(Vector2(st.position.x, sy)), w(Vector2(st.end.x, sy)), Color("#7d7264"), 2.0)
			sy += 12.0
	# rails with posts
	for seg in shape.rails():
		var a: Vector2 = seg[0] - shape.center
		var b2: Vector2 = seg[1] - shape.center
		draw_line(a, b2, RAIL, Colosseum.RAIL_W)
		draw_line(a, b2, POST, 3.0)
		for p: Vector2 in [a, b2]:
			draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), POST)
			draw_rect(Rect2(p - Vector2(11, 11), Vector2(22, 22)), RAIL, false, 2.0)
	# braziers
	for c: Vector2 in Colosseum.BRAZIERS:
		var at := w(c)
		var half := Colosseum.BRAZIER_HALF * Colosseum.S
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), Color("#3c3836"))
		draw_rect(Rect2(at - Vector2(half, half) * 0.7, Vector2(half, half) * 1.4), Color("#5a524c"))
		draw_circle(at, half * 0.45, FIRE)
		draw_circle(at, half * 0.22, Color("#fff1b0"))

## Half the floor's width at image row `y` (the rounded ends pull it in near the top and bottom).
func _half_width(y: float) -> float:
	var f := Colosseum.FLOOR
	var r := Colosseum.CORNER
	var half := f.size.x / 2.0
	var dy := 0.0
	if y < f.position.y + r:
		dy = f.position.y + r - y
	elif y > f.end.y - r:
		dy = y - (f.end.y - r)
	return half - r + sqrt(maxf(r * r - dy * dy, 0.0))

## Half the floor's height at image column `x`.
func _half_height(x: float) -> float:
	var f := Colosseum.FLOOR
	var r := Colosseum.CORNER
	var half := f.size.y / 2.0
	var dx := 0.0
	if x < f.position.x + r:
		dx = f.position.x + r - x
	elif x > f.end.x - r:
		dx = x - (f.end.x - r)
	return half - r + sqrt(maxf(r * r - dx * dx, 0.0))

# --- noise (placeholder texture): fixed seed, drawn once ---------------------------------------------------------

## Every TILE square of `area` whose centre passes `keep` gets a slightly lighter or darker shade of `base` (+- amount),
## so the floor reads as laid tiles instead of a flat fill.
func _tile_noise(area: Rect2, base: Color, amount: float, keep: Callable) -> void:
	var y := area.position.y
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			var c := Vector2(x + TILE / 2.0, y + TILE / 2.0)
			if keep.call(c):
				var k := _rng.randf_range(-amount, amount)
				var col := base.lightened(k) if k > 0.0 else base.darkened(-k)
				draw_rect(wr(Rect2(x + 1.0, y + 1.0, TILE - 2.0, TILE - 2.0)), col)
			x += TILE
		y += TILE

## `count` small grains (pebbles, dark sand) scattered over `area`, only where `keep` passes.
func _speckles(area: Rect2, count: int, keep: Callable) -> void:
	for i in count:
		var c := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if not keep.call(c):
			continue
		var dark := _rng.randf() < 0.7
		var col := SAND_LINE.darkened(_rng.randf_range(0.0, 0.25)) if dark else SAND.lightened(_rng.randf_range(0.15, 0.3))
		draw_circle(w(c), _rng.randf_range(1.5, 4.0), Color(col, _rng.randf_range(0.5, 0.9)))

## `count` light ripple arcs on water inside `area`, only where `keep` passes.
func _ripples(area: Rect2, count: int, keep: Callable) -> void:
	for i in count:
		var c := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		if not keep.call(c):
			continue
		var r := _rng.randf_range(10.0, 26.0) * Colosseum.S
		var a := _rng.randf_range(0.0, TAU)
		draw_arc(w(c), r, a, a + _rng.randf_range(0.8, 1.8), 10, Color(WATER_EDGE.lightened(0.25), 0.55), 2.0)
		if _rng.randf() < 0.3:   # a fish shadow now and then
			draw_circle(w(c) + Vector2(r, 0).rotated(a), 5.0, Color(0.05, 0.2, 0.28, 0.5))
