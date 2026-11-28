class_name ChaosFx extends Node2D
## Chaos Lord's effects share the 32x16 arena tile projection and a common set of painted textures.

const CLEAVE := "chaos_cleave"
const BLAST := "chaos_blast"
const GROUND_SCALE := Vector2(1.0, 0.5)
const ART := "res://assets/isometric_projecttile/Spells/ChaosLord/"
const BAND := preload(ART + "CleaveBand.png")
const BOLT := preload(ART + "BlastBolt.png")
const BLAST_RELEASE := preload(ART + "BlastRelease.png")
const CLEAVE_IMPACT := preload(ART + "CleaveImpact.png")
const BLAST_IMPACT := preload(ART + "BlastImpact.png")
const EDGE := Color("#b642cb")
const ECHO := Color("#7155cc")
const LIGHT := Color("#f4d6ff")
const VOID := Color("#231633")

enum Shape { STRIKE, BURST, RELEASE, FIZZLE }

var _shape := Shape.STRIKE
var _power := 0.0
var _age := 0.0
var _life := 0.25
var _direction := Vector2.RIGHT

static func is_impact(cause: String) -> bool:
	return cause == CLEAVE or cause == BLAST

static func ground_distance(offset: Vector2) -> float:
	return (offset / GROUND_SCALE).length()

static func victim_impact(victim: Node2D, cause: String, direction: Vector2, power: float) -> void:
	var at := victim.global_position + Vector2(0, -25)
	_spawn(victim.get_parent(), at, direction, power, Shape.STRIKE if cause == CLEAVE else Shape.BURST)

static func release(parent: Node, origin: Vector2, direction: Vector2, power: float, behind := false) -> void:
	var aperture := _spawn(parent, origin, direction, power, Shape.RELEASE)
	if behind:
		aperture.z_index = -1

static func fizzle(parent: Node, at: Vector2, direction: Vector2, power: float) -> void:
	_spawn(parent, at + Vector2(0, -28), direction, power, Shape.FIZZLE)

static func _spawn(parent: Node, at: Vector2, direction: Vector2, power: float, shape: Shape) -> ChaosFx:
	var node := ChaosFx.new()
	node._shape = shape
	node._power = clampf(power, 0.0, 1.0)
	node._direction = direction
	node._life = 0.30 if shape == Shape.BURST else (0.25 if shape == Shape.STRIKE else 0.16)
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.z_index = 18 if shape == Shape.STRIKE or shape == Shape.BURST else 4
	parent.add_child(node)
	node.global_position = at
	return node

static func draw_boundary(canvas: CanvasItem, direction: Vector2, angle: float, reach: float,
		age: float, windup: float, active: float, power: float) -> void:
	var base := (direction / GROUND_SCALE).angle() - angle * 0.5
	if age < windup:
		var warning := smoothstep(0.0, windup, age)
		draw_ribbon(canvas, base, angle, reach, 10.0, 0.0, Color(1, 1, 1, 0.24 + 0.28 * warning))
		return
	var t := clampf((age - windup) / (active + 0.08), 0.0, 1.0)
	var alpha := 1.0 - smoothstep(0.12, 1.0, t)
	draw_ribbon(canvas, base, angle, reach, lerpf(46.0, 60.0, power), 0.0, Color(0.85, 0.70, 1.0, 0.75 * alpha))
	draw_ribbon(canvas, base, angle, reach, lerpf(35.0, 48.0, power), 9.0 + 6.0 * t,
		Color(1, 1, 1, alpha))

static func draw_ribbon(canvas: CanvasItem, base: float, angle: float, radius: float,
		width: float, height: float, tint: Color) -> void:
	if tint.a <= 0.0 or angle <= 0.001:
		return
	var cut := Vector2(0, -height)
	var inner := radius - width
	var color := PackedColorArray([tint])
	const STRIPS := 32
	for i in STRIPS:
		var u0 := float(i) / STRIPS
		var u1 := float(i + 1) / STRIPS
		var next := Vector2.from_angle(base + angle * u1) * GROUND_SCALE
		var prior := Vector2.from_angle(base + angle * u0) * GROUND_SCALE
		var outer_start := prior * radius + cut
		var outer_end := next * radius + cut
		var inner_end := next * inner + cut
		var inner_start := prior * inner + cut
		canvas.draw_primitive(PackedVector2Array([outer_start, outer_end, inner_end]), color,
			PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1)]), BAND)
		canvas.draw_primitive(PackedVector2Array([outer_start, inner_end, inner_start]), color,
			PackedVector2Array([Vector2(u0, 0), Vector2(u1, 1), Vector2(u0, 1)]), BAND)

static func draw_bolt(canvas: CanvasItem, at: Vector2, heading: Vector2, age: float, power: float, echo := 0.0) -> void:
	const CELLS := Vector2(144, 112)
	var row := SheetFrames.facing_index(heading)
	var frame := posmod(floori(age * 34.0), 6)
	var k := lerpf(1.06, 1.38, power) * lerpf(1.0, 0.38, echo)
	var origin := at - CELLS * k * 0.5
	var tint := Color.WHITE.lerp(Color(0.86, 0.65, 1.0, 0.0), echo)
	canvas.draw_texture_rect_region(BOLT, Rect2(origin, CELLS * k), Rect2(Vector2(frame, row) * CELLS, CELLS), tint)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := lerpf(0.69, 1.13, _power)
	var t := clampf(_age / _life, 0.0, 1.0)
	const CELL := Vector2(96, 96)
	if _shape == Shape.RELEASE:
		var row := SheetFrames.facing_index(_direction)
		var phase := mini(floori(8.0 * t), 7)
		var size := CELL * k
		draw_texture_rect_region(BLAST_RELEASE, Rect2(-size * 0.5, size), Rect2(Vector2(phase, row) * CELL, CELL))
		return
	var art := CLEAVE_IMPACT if _shape == Shape.STRIKE else BLAST_IMPACT
	if _shape == Shape.FIZZLE:
		k *= 0.57
		t = 0.23 + 0.77 * t
	var flip := -1.0 if _direction.x < 0.0 else 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(flip, 1.0))
	var frame := mini(floori(8.0 * t), 7)
	draw_texture_rect_region(art, Rect2(-CELL * k * 0.5, CELL * k), Rect2(Vector2(CELL.x * frame, 0), CELL),
		Color(1, 1, 1, 1.0 - smoothstep(0.75, 1.0, t)))
