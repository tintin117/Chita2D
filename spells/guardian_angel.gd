class_name GuardianAngel extends Spell
## Paladin ult: for DURATION seconds nothing can hurt you (Player.guardian), and every hit you land heals you for half
## its damage (Player.ANGEL_STEAL). The wings fold into a guard for the full status duration.
## No target needed: it is a self-buff, so it always fires.

const DURATION := 3.0
const FEATHERS := preload("res://assets/isometric_projecttile/Spells/Paladin/GuardianFeathers.png")
const SPARK := preload("res://assets/isometric_projecttile/Spells/Paladin/HolySpark.png")

static func show_mantle(caster: Player, duration: float) -> void:
	var mantle := caster.get_node_or_null(^"GuardianMantle") as Mantle
	if mantle == null:
		mantle = Mantle.new()
		mantle.name = "GuardianMantle"
		mantle.caster = caster
		mantle.duration = duration
		caster.add_child(mantle)
	else:
		mantle.duration = duration

## Bots: save it for when it saves you (hurt, with a foe close).
func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	if "hp" in caster and caster.hp > caster.max_hp * 0.45:
		return false
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) < 450.0:
			return true
	return false

func _init() -> void:
	display_name = "Guardian Grace"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "crown"
	cast_pitch = 0.8

func ult_lock() -> float:
	return DURATION + 0.5

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	if caster.has_method("guardian"):
		caster.guardian(DURATION)
	return cooldown

class Mantle extends Node2D:
	const SPREAD_END := 0.18
	const WRAP_START := 0.22
	const WRAP_END := 0.46
	const STRIPS := 16
	const GUARD_SIZE := Vector2(0.84, 0.77)
	const GUARD_ALPHA := 0.88
	const GROUND_SQUASH := 0.58
	const WING_VERTICES := STRIPS + 1
	const FACINGS: Array[Vector2] = [Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1), Vector2.LEFT,
		Vector2(-1, -1), Vector2.UP, Vector2(1, -1), Vector2.RIGHT]
	## Upper-back anchors from the spread beat of Paladin's ShieldBlockStart sheet.
	const WING_ROOTS: Array[Vector2] = [Vector2(64, 60), Vector2(62, 60), Vector2(62, 58), Vector2(60, 59),
		Vector2(52, 55), Vector2(59, 56), Vector2(63, 53), Vector2(76, 58)]
	## Top left, top right and lower point of the painted shield in the first 4Paladin idle frame.
	## Coordinates are in the native 128 px cell. The painted shield is canted relative to the facing row.
	const SHIELD_PINS := [
		[Vector2(78, 47), Vector2(81, 56), Vector2(79, 83)], # SE
		[Vector2(69, 66), Vector2(82, 55), Vector2(74, 85)], # S
		[Vector2(52, 64), Vector2(75, 65), Vector2(63, 86)], # SW
		[Vector2(43, 56), Vector2(62, 66), Vector2(54, 84)], # W
		[Vector2(44, 46), Vector2(49, 57), Vector2(45, 78)], # NW
		[Vector2(44, 44), Vector2(59, 39), Vector2(46, 69)], # N
		[Vector2(53, 41), Vector2(73, 40), Vector2(64, 63)], # NE
		[Vector2(67, 39), Vector2(82, 50), Vector2(80, 69)], # E
	]

	var caster: Player
	var duration := DURATION
	var _back := Node2D.new()
	var _age := 0.0
	var _spread := 0.0
	var _wrap := 0.0
	var _opacity := 0.0
	var _facing_row := 1
	var _wing_across := Vector2.RIGHT
	var _wing_back := Vector2.UP * GROUND_SQUASH
	var _guard_across := Vector2.RIGHT
	var _guard_down := Vector2.DOWN
	var _upper := PackedVector2Array()
	var _lower := PackedVector2Array()
	var _strip_uvs: Array[PackedVector2Array] = []

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_back)
		_back.draw.connect(_draw_back)
		_upper.resize(2 * WING_VERTICES)
		_lower.resize(2 * WING_VERTICES)
		var size := FEATHERS.get_size()
		var top := 0.5 / size.y
		var bottom := 1.0 - top
		for i in STRIPS:
			var start := (0.5 + (size.x - 1.0) * float(i) / STRIPS) / size.x
			var end := (0.5 + (size.x - 1.0) * float(i + 1) / STRIPS) / size.x
			_strip_uvs.append(PackedVector2Array([Vector2(start, top), Vector2(end, top), Vector2(end, bottom), Vector2(start, bottom)]))
		_align_to_sprite()
		_shape_feathers()

	func _process(_delta: float) -> void:
		var left := caster._angel_left
		if caster.down or left <= 0.0:
			queue_free()
			return
		_age = maxf(0.0, duration - left)
		_spread = smoothstep(0.0, SPREAD_END, _age)
		_wrap = smoothstep(WRAP_START, WRAP_END, _age)
		_opacity = smoothstep(0.0, 0.06, _age) * smoothstep(0.0, 0.28, left)
		_align_to_sprite()
		_shape_feathers()
		_back.queue_redraw()
		queue_redraw()

	## Align the open wings to Paladin's back and the folded guard to his front.
	func _align_to_sprite() -> void:
		var body := caster._sprite
		# SheetFrames order is SE, S, SW, W, NW, N, NE, E.
		_facing_row = caster._dirs.find(body.sprite_frames)
		if _facing_row < 0:
			_facing_row = 1
		var facing := FACINGS[_facing_row].normalized()
		var heading := Vector2(facing.x, facing.y / GROUND_SQUASH).normalized()
		_wing_across = Vector2(heading.y, -heading.x * GROUND_SQUASH)
		_wing_back = Vector2(-heading.x, -heading.y * GROUND_SQUASH)
		var pins: Array = SHIELD_PINS[_facing_row]
		var rim_left: Vector2 = pins[0]
		var rim_right: Vector2 = pins[1]
		var tip: Vector2 = pins[2]
		var rim_center := rim_left.lerp(rim_right, 0.5)
		var spine := tip - rim_center
		_guard_across = (rim_right - rim_left) / 23.0
		_guard_down = spine.normalized() * clampf(spine.length() / 27.0, 0.82, 1.12)
		var cell_origin := body.offset - Vector2(64, 64)
		var opening := WING_ROOTS[_facing_row] + cell_origin
		var folded := rim_center.lerp(tip, 0.5) + cell_origin
		scale = body.scale / Player.SPRITE_SCALE
		rotation = body.rotation
		position = body.position + (opening.lerp(folded, _wrap) * body.scale).rotated(rotation)
		var shield_behind := _facing_row >= 4
		z_index = -1 if shield_behind else 1
		_back.z_index = -2 * z_index

	## The same leading edge that extends from the shoulder becomes one half of the front seam.
	func _shape_feathers() -> void:
		var reach := lerpf(0.22, 1.0, _spread)
		var lift := lerpf(-0.83, 0.0, _spread)
		var pivot := Vector2(5, -2)
		for i in WING_VERTICES:
			var u := float(i) / STRIPS
			var spine := Vector2(82.0 * u, -36.0 * u)
			var edge := spine + Vector2(-8.0 * u, 10.0 + 32.0 * sin(PI * u) + 4.0 * u)
			spine = pivot + (spine * reach).rotated(lift)
			edge = pivot + (edge * reach).rotated(lift)
			var backsweep := (2.0 + 31.0 * u) * reach
			var shoulder := smoothstep(0.0, 0.21, u)
			var taper := smoothstep(0.28, 1.0, u)
			var y := lerpf(-43.0, 43.0, u)
			var seam := lerpf(lerpf(12.0, -3.0, shoulder), 0.0, smoothstep(0.92, 1.0, u))
			var guard_spine := Vector2(seam, y) * GUARD_SIZE
			var guard_edge := Vector2(lerpf(32.0, 49.0, shoulder) - 42.0 * taper, y + lerpf(-7.0, 2.0, u)) * GUARD_SIZE
			var fold := smoothstep(0.0, 1.0, clampf(_wrap * 1.14 - 0.14 * u, 0.0, 1.0))
			for wing in 2:
				var side := float(wing * 2 - 1)
				var mirror := Vector2(side, 1.0)
				var index := wing * WING_VERTICES + i
				_upper[index] = _project_wing(spine * mirror, backsweep).lerp(_project_guard(guard_spine * mirror), fold)
				_lower[index] = _project_wing(edge * mirror, backsweep + 10.0 * u * reach).lerp(_project_guard(guard_edge * mirror), fold)

	func _project_wing(point: Vector2, backsweep: float) -> Vector2:
		return _wing_across * point.x + _wing_back * backsweep + Vector2(0, point.y)

	func _project_guard(point: Vector2) -> Vector2:
		return _guard_across * point.x + _guard_down * point.y

	## Every strip belongs to one depth layer. The tips come forward first as the wing curls.
	func _draw_feathers(canvas: Node2D, in_front: bool) -> void:
		var front_start := STRIPS - floori(_wrap * STRIPS)
		var first := front_start if in_front else 0
		var end := STRIPS if in_front else front_start
		var depth_skew := lerpf(_wing_across.y, _guard_across.y, _wrap)
		var far_wing := int(depth_skew < 0.0)
		for depth in 2:
			var offset := (far_wing if depth == 0 else 1 - far_wing) * WING_VERTICES
			var shade := 1.0 - absf(depth_skew) * 0.32 if depth == 0 else 1.0
			var tint := PackedColorArray([Color(1.05 * shade, 0.98 * shade, 0.90 * shade, _opacity * lerpf(0.80, GUARD_ALPHA, _wrap))])
			for i in range(first, end):
				var top_root := _upper[offset + i]
				var top_tip := _upper[offset + i + 1]
				var bottom_tip := _lower[offset + i + 1]
				var bottom_root := _lower[offset + i]
				var uv := _strip_uvs[i]
				# Draw explicit triangles to keep the strips continuous as the wing swings forward.
				canvas.draw_primitive(PackedVector2Array([top_root, top_tip, bottom_tip]), tint,
					PackedVector2Array([uv[0], uv[1], uv[2]]), FEATHERS)
				canvas.draw_primitive(PackedVector2Array([top_root, bottom_tip, bottom_root]), tint,
					PackedVector2Array([uv[0], uv[2], uv[3]]), FEATHERS)

	func _draw_back() -> void:
		_draw_feathers(_back, false)

	func _draw() -> void:
		_draw_feathers(self, true)
		var facing_tips := PackedVector2Array([_upper[STRIPS - 1], _upper[2 * STRIPS]]) if _wrap < 0.99 else PackedVector2Array([_upper[STRIPS]])
		for at in facing_tips:
			var glint := (0.25 + 0.14 * sin(_age * 8.0)) * _opacity
			draw_texture_rect(SPARK, Rect2(at - Vector2(7, 7), Vector2(14, 14)), false, Color(1.0, 0.92, 0.70, glint))
