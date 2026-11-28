@tool
extends Node2D
## Projected stone bowl. The inner arc is also the hard wall around the fighting floor.

const RADIUS := Vector2(1090, 570)
const FRONT_SECTIONS := 38
const SECTION_COUNT := FRONT_SECTIONS * 2
const OCHRE := Color("#bf8958")
const LIGHT_FACE := Color("#bc895d")
const RED_STONE := Color("#88533a")
const ARCH_DARK := Color("#412823")
const CAP := Color("#dfa972")
const JOINT := Color("#59362b")
const SEAT_ROWS := 5
const SEAT_STEP := Vector2(31, 16)
const FRONT_BRIDGE_DROP := 142.0
const BRIDGE_GATE := Vector2i(24, 27)
const REAR_GATE := Vector2i(65, 68)
const EXTERIOR_ENTRIES := [6, 12]
const BRAZIER_PIERS := [46, 55, 64, 69]
const FLAG_MOUNTS := [38, 48, 54, 62, 73, 11, 30]
const ISO_SOUTHEAST := Vector2(1.0, 0.5)
const ISO_NORTHEAST := Vector2(1.0, -0.5)
const DEBRIS_CLUSTERS := [
	Vector2(-727, -290), Vector2(709, 308), Vector2(-866, -100),
	Vector2(274, -456), Vector2(805, -169), Vector2(-422, 397),
]

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var body := StaticBody2D.new()
	body.name = "ArenaWall"
	body.collision_layer = 1 | Player.WALL_MASK
	body.collision_mask = 0
	var segments := PackedVector2Array()
	for i in SECTION_COUNT:
		segments.append(_rim(i))
		segments.append(_rim(i + 1))
	var outline := ConcavePolygonShape2D.new()
	outline.segments = segments
	var collider := CollisionShape2D.new()
	collider.shape = outline
	body.add_child(collider)
	add_child(body)

func _draw() -> void:
	_draw_ravine()
	_draw_approach()
	_draw_footing_shadows()
	_draw_front_foundation()
	_draw_foundation_stones()
	_draw_dry_shrubs()
	for section: int in EXTERIOR_ENTRIES:
		_draw_exterior_stairs(section)
	_draw_bridge()
	_draw_wall_shadow()
	_draw_stone_fragments()
	for i in range(FRONT_SECTIONS, SECTION_COUNT):
		if i < REAR_GATE.x or i >= REAR_GATE.y:
			_draw_gallery(i)
	_draw_gate_pavilion()
	_draw_portcullis(REAR_GATE, 131.0)
	for pier: int in BRAZIER_PIERS:
		_draw_pier(pier, _pier_height(pier))
	for i in range(FRONT_SECTIONS):
		if i < BRIDGE_GATE.x or i >= BRIDGE_GATE.y:
			_draw_gallery(i)
	_draw_portcullis(BRIDGE_GATE, 102.0)
	_draw_pier(BRIDGE_GATE.x, 112.0)
	_draw_pier(BRIDGE_GATE.y, 112.0)
	for section: int in FLAG_MOUNTS:
		_draw_flag(section)
	_draw_seating_awning(44, Color("#ac5935"), Color("#d8a65b"))
	_draw_seating_awning(51, Color("#964631"), Color("#bc854f"))
	_draw_seating_awning(59, Color("#55747c"), Color("#c6ae86"))
	_draw_seating_awning(9, Color("#768048"), Color("#c49c57"))
	_draw_seating_awning(33, Color("#887442"), Color("#c49c57"))

func _rim(section: int, extra := Vector2.ZERO) -> Vector2:
	return Vector2.from_angle(TAU * section / SECTION_COUNT) * (RADIUS + extra)

func _height(section: int) -> float:
	var depth := sin(TAU * section / SECTION_COUNT)
	return lerpf(22.0, 65.0, clampf(0.20 - depth, 0.0, 1.0))

func _seat_rise(section: int) -> float:
	return lerpf(7.0, 22.0, 1.0 - smoothstep(-0.10, 0.33, sin(TAU * section / SECTION_COUNT)))

func _seat(section: int, row: int) -> Vector2:
	return _rim(section, SEAT_STEP * row) - Vector2(0.0, _height(section) + _seat_rise(section) * row)

func _pier_height(section: int) -> float:
	return _height(section) + _seat_rise(section) * 3.0 + 12.0

func _draw_ravine() -> void:
	var outer := PackedVector2Array([
		Vector2(-1680, -300), Vector2(-1538, -190), Vector2(-1504, -66),
		Vector2(-1450, 26), Vector2(-1390, 161), Vector2(-1335, 190),
		Vector2(-1330, 314), Vector2(-1250, 385), Vector2(-1200, 458),
		Vector2(-1198, 533), Vector2(-1130, 591), Vector2(-1115, 680),
		Vector2(-1032, 730), Vector2(-1015, 836), Vector2(-915, 931),
		Vector2(-840, 1040), Vector2(-827, 1240),
	])
	var inner := PackedVector2Array([
		Vector2(-1580, -290), Vector2(-1490, -200), Vector2(-1452, -84),
		Vector2(-1410, 25), Vector2(-1315, 137), Vector2(-1238, 158),
		Vector2(-1205, 225), Vector2(-1110, 310), Vector2(-1085, 366),
		Vector2(-1015, 438), Vector2(-977, 516), Vector2(-898, 550),
		Vector2(-871, 638), Vector2(-784, 689), Vector2(-748, 789),
		Vector2(-654, 807), Vector2(-583, 868), Vector2(-480, 896),
		Vector2(-401, 994), Vector2(-316, 1007), Vector2(-179, 1134), Vector2(-101, 1238),
	])
	var bed := outer.duplicate()
	var reverse_inner := inner.duplicate()
	reverse_inner.reverse()
	bed.append_array(reverse_inner)
	draw_colored_polygon(bed, Color("#503027"))
	_draw_ravine_bank(outer, Vector2(42, 84), Color("#99634a"))
	_draw_ravine_bank(inner, Vector2(-103, 163), Color("#b97e56"))

func _draw_ravine_bank(bank: PackedVector2Array, depth: Vector2, rock: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 315709
	for i in range(bank.size() - 1):
		var a := bank[i]
		var b := bank[i + 1]
		var base_a := depth * clampf((a.y + 300.0) / 750.0, 0.12, 1.0)
		var base_b := depth * clampf((b.y + 300.0) / 750.0, 0.12, 1.0)
		var layers := PackedFloat32Array([0.0, 0.15, 0.38, 0.49, 0.69, 0.92, 1.0])
		for band in range(layers.size() - 1):
			var high := layers[band]
			var low := layers[band + 1]
			var tone := 0.15 - low * 0.42 + rng.randf_range(-0.10, 0.08)
			var edge_a := a + base_a * high
			var edge_b := b + base_b * high
			_quad(edge_a, edge_b, b + base_b * low, a + base_a * low, _shade(rock, tone))
			draw_line(edge_a, edge_b, Color(JOINT, 0.43), 2.0)
			var joints := rng.randi_range(2, 4)
			for joint in range(1, joints):
				var t := (joint + rng.randf_range(-0.16, 0.16)) / joints
				var split := edge_a.lerp(edge_b, t)
				var base := base_a.lerp(base_b, t) * (low - high)
				_quad(split, split + Vector2(rng.randf_range(4, 13), 0),
					split + base + Vector2(6, 1), split + base, _shade(rock, tone - 0.085))
		var lip := Color("#d6a06c")
		draw_line(a, b, lip, 2.0)
		for chip in 4:
			var edge := a.lerp(b, rng.randf()) - depth.normalized() * rng.randf_range(4, 23)
			_draw_scree_stone(edge.round(), rng.randf_range(2, 10), rng)

func _draw_gate_pavilion() -> void:
	var gate_a := _rim(REAR_GATE.x)
	var gate_b := _rim(REAR_GATE.y)
	var direction := (gate_b - gate_a).normalized()
	var a := gate_a - Vector2(0, 146)
	var b := gate_b - Vector2(0, 146)
	var rear := ISO_NORTHEAST * 139.0
	_quad(gate_a, gate_b, b, a, LIGHT_FACE)
	_quad(gate_b, gate_b + rear, b + rear, b, RED_STONE)
	for row in range(1, 8):
		var left := gate_a.lerp(a, row / 8.0)
		var right := gate_b.lerp(b, row / 8.0)
		draw_line(left, right, Color(JOINT, 0.55), 2.0)
		draw_line(right, right + rear, Color(JOINT, 0.52), 2.0)
	_quad(a, b, b + rear, a + rear, OCHRE)
	draw_line(a, b, CAP, 8.0)
	draw_line(b, b + rear, CAP.darkened(0.11), 6.0)
	for i in range(1, 6):
		var rail := a.lerp(b, i / 6.0)
		draw_line(rail, rail - Vector2(0, 20), JOINT, 4.0)
	draw_line(a - Vector2(0, 20), b - Vector2(0, 20), JOINT, 4.0)
	var posts := PackedVector2Array([a, b, b + rear, a + rear])
	var up := Vector2(0, -79)
	for foot in posts:
		draw_line(foot, foot + up, JOINT, 8.0)
		draw_line(foot - Vector2(2, 0), foot + up - Vector2(2, 0), OCHRE, 2.0)
	var ridge := (a + b + rear) * 0.5 + Vector2(0, -136)
	var roof := PackedVector2Array([a + up - direction * 13.0, b + up + direction * 13.0,
		b + rear + up + direction * 13.0, a + rear + up - direction * 13.0])
	var cloth := [Color("#ead09b"), Color("#b38a59"), Color("#d9ba84"), Color("#f0d8a8")]
	for i: int in [2, 3, 1, 0]:
		var left := roof[i]
		var right := roof[(i + 1) % 4]
		draw_colored_polygon(PackedVector2Array([left, right, ridge]), cloth[i])
		if i < 2:
			var drape := left.lerp(right, 0.5) + Vector2(0, 12)
			draw_colored_polygon(PackedVector2Array([left, drape, right]), cloth[i].darkened(0.13))
			draw_polyline(PackedVector2Array([left, drape, right]), Color("#8e6642"), 3.0)
			draw_line(right, ridge, Color("#9c794f"), 2.0)
	draw_line(ridge, ridge - Vector2(0, 27), JOINT, 3.0)
	var point := ridge - Vector2(0, 26)
	draw_colored_polygon(PackedVector2Array([point, point + Vector2(39, 9),
		point + Vector2(30, 12), point + Vector2(35, 21), point + Vector2(0, 14)]), Color("#a04730"))

func _draw_flag(section: int) -> void:
	var base := _seat(section, 4) + Vector2(0, 4)
	var east := ISO_SOUTHEAST * 9.0
	var north := ISO_NORTHEAST * 9.0
	_quad(base - east, base + north, base + east, base - north, CAP.darkened(0.07))
	draw_line(base - north, base + east, RED_STONE, 5.0)
	var tip := base - Vector2(0.0, 77.0)
	var flag_axis := ISO_NORTHEAST if base.x < 0.0 else ISO_SOUTHEAST
	var end := tip + flag_axis * 43.0
	var lower := Vector2(0.0, 38.0)
	var cloth := Color("#a34630") if section % 2 == 0 else Color("#bc823e")
	var notch := end - flag_axis * 12.0 + lower * 0.58
	draw_colored_polygon(PackedVector2Array([tip, end, notch, end + lower * 0.88,
		tip + lower]), cloth)
	draw_line(tip + Vector2(0.0, 7.0), end + Vector2(0.0, 7.0), CAP, 2.0)
	draw_line(base, tip - Vector2(0.0, 5.0), JOINT.darkened(0.23), 4.0)
	draw_line(base - Vector2(1.0, 0.0), tip - Vector2(1.0, 5.0), CAP.darkened(0.14), 1.0)

func _draw_seating_awning(section: int, fabric: Color, trim: Color) -> void:
	var a := _seat(section - 1, 3)
	var b := _seat(section + 1, 3)
	var back_a := _seat(section - 1, 5)
	var back_b := _seat(section + 1, 5)
	var above := Vector2(0.0, -55.0)
	var back_lift := Vector2(0.0, -36.0)
	for foot in [back_a, back_b]:
		draw_line(foot, foot + back_lift, JOINT, 4.0)
	for foot in [a, b]:
		draw_line(foot, foot + above, JOINT, 4.0)
	_quad(a + above, b + above, back_b + back_lift, back_a + back_lift, fabric)
	for i: int in [0, 2, 4]:
		var t := i / 5.0
		var next := (i + 1) / 5.0
		_quad(a.lerp(b, t) + above, a.lerp(b, next) + above,
			back_a.lerp(back_b, next) + back_lift, back_a.lerp(back_b, t) + back_lift, trim)
	var hem := Vector2(0, 8)
	_quad(a + above, b + above, b + above + hem, a + above + hem, fabric.darkened(0.20))
	draw_line(a + above, b + above, trim.darkened(0.16), 2.0)

func _draw_gallery(i: int) -> void:
	var a := _rim(i)
	var b := _rim(i + 1)
	var ia := _seat(i, 0)
	var ib := _seat(i + 1, 0)
	var tone := float(posmod(i * 37, 15) - 7) * 0.008
	var wall := _shade(RED_STONE, tone + absf(a.x) / RADIUS.x * 0.16)
	_quad(a, b, ib, ia, wall)
	for row in range(1, 4):
		var t := row / 4.0
		var left := a.lerp(ia, t)
		var right := b.lerp(ib, t)
		draw_line(left, right, Color(JOINT, 0.67), 1.0)
		var joint := 0.32 if (i + row) % 2 == 0 else 0.67
		draw_line(left.lerp(right, joint), a.lerp(b, joint).lerp(ia.lerp(ib, joint), t + 0.19), JOINT, 1.0)
	if i in [1, 35, 45, 51, 57, 63, 71]:
		_arch(a.lerp(b, 0.14), a.lerp(b, 0.86), _height(i) * 0.72, wall)
	draw_line(ia, ib, CAP, 5.0)
	for row in range(1, SEAT_ROWS + 1):
		var high_a := _seat(i, row)
		var high_b := _seat(i + 1, row)
		var step_a := high_a + Vector2(0, _seat_rise(i))
		var step_b := high_b + Vector2(0, _seat_rise(i + 1))
		var stairway := i in [5, 17, 36, 47, 62, 72]
		var tread := _shade(OCHRE if stairway else CAP, tone - row * 0.028)
		_quad(ia, ib, step_b, step_a, tread)
		_quad(step_a, step_b, high_b, high_a, wall.lightened(0.19))
		draw_line(high_a, high_b, tread.lightened(0.13), 2.0)
		if stairway:
			draw_line(ia, step_a, JOINT, 2.0)
			draw_line(ib, step_b, JOINT, 2.0)
			draw_line(ia.lerp(step_a, 0.5), ib.lerp(step_b, 0.5), tread.darkened(0.20), 2.0)
		else:
			var seam := 0.41 if (i + row) % 2 == 0 else 0.62
			draw_line(ia.lerp(ib, seam), step_a.lerp(step_b, seam), Color(JOINT, 0.42), 1.0)
		ia = high_a
		ib = high_b
	draw_line(ia, ib, CAP.lightened(0.16), 7.0)

func _draw_pier(section: int, height: float) -> void:
	var center := _rim(section)
	var side := (_rim(section + 1) - _rim(section - 1)).normalized() * 25.0
	var inward := -center.normalized() * 20.0
	var lift := Vector2(0.0, -height)
	var a := center - side
	var b := center + side
	_quad(a, b, b + inward, a + inward, CAP.darkened(0.31))
	_quad(a, a + inward, a + inward + lift, a + lift, RED_STONE.darkened(0.12))
	_quad(a + inward, b + inward, b + inward + lift, a + inward + lift, LIGHT_FACE)
	_quad(a + lift, b + lift, b + inward + lift, a + inward + lift, CAP)
	var y := 35.0
	var row := 0
	while y < height - 22.0:
		var row_left := a + inward - Vector2(0, y)
		var row_right := b + inward - Vector2(0, y)
		draw_line(row_left, row_right, JOINT, 1.0)
		var joint := row_left.lerp(row_right, 0.35 if row % 2 == 0 else 0.69)
		draw_line(joint, joint + Vector2(0, 14.0), JOINT, 1.0)
		y += 19.0
		row += 1
	for band in [9.0, 18.0, height - 16.0, height - 8.0]:
		draw_line(a + inward - Vector2(0, band), b + inward - Vector2(0, band), JOINT, 2.0)
	draw_line(a + inward + lift + Vector2(0, 3), b + inward + lift + Vector2(0, 3), CAP, 5.0)

func _draw_portcullis(sections: Vector2i, height: float) -> void:
	var a := _rim(sections.x)
	var b := _rim(sections.y)
	var left := a.lerp(b, 0.10)
	var right := a.lerp(b, 0.90)
	var inward := -(a + b).normalized() * 20.0
	var opening := PackedVector2Array([left])
	for i in range(17):
		var t := i / 16.0
		opening.append(left.lerp(right, t) - Vector2(0.0, _arch_height(t, height)))
	opening.append(right)
	draw_colored_polygon(opening, ARCH_DARK.darkened(0.35))
	_quad(left, right, right + inward, left + inward, RED_STONE)
	for bar in range(1, 12):
		var t := bar / 12.0
		var foot := left.lerp(right, t)
		var tip := foot - Vector2(0, _arch_height(t, height) - 5.0)
		draw_line(foot, tip, Color("#372b27"), 6.0)
		draw_line(foot + Vector2(1, 0), tip + Vector2(1, 0), Color("#886145"), 2.0)
	for y in [24.0, 48.0]:
		draw_line(left - Vector2(0, y), right - Vector2(0, y), Color("#79513a"), 5.0)
	for i in range(1, opening.size() - 2):
		draw_line(opening[i], opening[i + 1], LIGHT_FACE, 18.0)
		draw_line(opening[i] - Vector2(0, 6), opening[i + 1] - Vector2(0, 6), CAP, 3.0)
		if i % 2 == 0:
			draw_line(opening[i] - Vector2(0, 8), opening[i] + Vector2(0, 6), JOINT, 2.0)
	for foot in [left, right]:
		_quad(foot - Vector2(12, 0), foot + Vector2(12, 0),
			foot + Vector2(12, -height * 0.62), foot - Vector2(12, height * 0.62), LIGHT_FACE)
		draw_line(foot - Vector2(12, 5), foot + Vector2(12, 5), CAP, 4.0)

func _arch_height(t: float, height: float) -> float:
	return height * (0.60 + sin(PI * t) * 0.40)

func _foundation_foot(section: int) -> Vector2:
	return _seat(section, SEAT_ROWS) + Vector2(0, 200.0 + 42.0 * sin(TAU * section / SECTION_COUNT))

func _draw_approach() -> void:
	var route := PackedVector2Array([
		Vector2(-1850, 918), Vector2(-1615, 880), Vector2(-1450, 840),
		Vector2(-1355, 789), Vector2(-1250, 775), Vector2(-1155, 777),
	])
	var sand := Color(0.86, 0.62, 0.36, 0.39)
	for i in range(route.size() - 1):
		var a := route[i]
		var b := route[i + 1]
		var margin := Vector2(0, 58 + i * 2)
		for bank: float in [-1.0, 1.0]:
			var feather := margin * bank
			draw_polygon(PackedVector2Array([a, b, b + feather, a + feather]),
				PackedColorArray([sand, sand, Color(sand, 0.0), Color(sand, 0.0)]))

func _draw_footing_shadows() -> void:
	var dark := Color(0.36, 0.19, 0.12, 0.47)
	for i in range(22):
		var a := _foundation_foot(i)
		var b := _foundation_foot(i + 1)
		var shift_a := Vector2(142.0, 42.0) + _rim(i).normalized() * 49.0
		var shift_b := Vector2(142.0, 42.0) + _rim(i + 1).normalized() * 49.0
		var alpha_a := dark.a * smoothstep(0.0, 4.0, float(i)) * (1.0 - smoothstep(18.0, 22.0, float(i)))
		var alpha_b := dark.a * smoothstep(0.0, 4.0, float(i + 1)) * (1.0 - smoothstep(18.0, 22.0, float(i + 1)))
		draw_polygon(PackedVector2Array([a, b, b + shift_b, a + shift_a]),
			PackedColorArray([Color(dark, alpha_a), Color(dark, alpha_b), Color(dark, 0.0), Color(dark, 0.0)]))

func _draw_dry_shrubs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11071
	var scrub := Color("#796943")
	for patch: int in [3, 8, 14, 17, 21, 29, 33]:
		var base := _foundation_foot(patch) + Vector2(4, 8)
		for tuft in rng.randi_range(2, 4):
			var root := (base + Vector2(rng.randf_range(-18, 24), rng.randf_range(0, 17))).round()
			var width := rng.randf_range(5, 12)
			draw_line(root, root + Vector2(width + 4, 4), Color(ARCH_DARK, 0.33), width * 0.46)
			for leaf in rng.randi_range(4, 7):
				var tip := (root + Vector2(rng.randf_range(-width, width), rng.randf_range(-14, -3))).round()
				var color := _shade(scrub, rng.randf_range(-0.19, 0.21))
				var edge := tip + Vector2(3, 0)
				draw_colored_polygon(PackedVector2Array([root, tip, edge]), color)

func _draw_foundation_stones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19187
	for bay: int in [2, 4, 8, 10, 14, 16, 20, 22, 28, 31, 34]:
		var ground := _foundation_foot(bay) + Vector2(1, -2)
		var tangent := _foundation_foot(bay + 1) - ground
		var outward := Vector2(1, 0.63) if bay < 13 else Vector2(0.20, 1)
		for stone in rng.randi_range(8, 14):
			var at := ground + tangent * rng.randf_range(-0.24, 0.65)
			at += outward * pow(rng.randf(), 2.0) * 59.0
			_draw_scree_stone(at.round(), rng.randf_range(3.0, 13.0), rng)

func _draw_scree_stone(at: Vector2, size: float, rng: RandomNumberGenerator) -> void:
	var wide := Vector2(size, 0)
	var deep := Vector2(size * 0.19, size * 0.49)
	var surface := PackedVector2Array([at - wide, at - deep, at + wide, at + deep])
	var color := _shade(Color("#aa774d"), rng.randf_range(-0.21, 0.37))
	draw_colored_polygon(Transform2D(0, Vector2(3, 3)) * surface, Color(ARCH_DARK, 0.34))
	draw_colored_polygon(surface, color)
	draw_line(at - wide, at - deep, color.lightened(0.28), 1.0)

func _draw_front_foundation() -> void:
	for i in range(FRONT_SECTIONS):
		var a := _seat(i, SEAT_ROWS)
		var b := _seat(i + 1, SEAT_ROWS)
		var foot_a := _foundation_foot(i)
		var foot_b := _foundation_foot(i + 1)
		var depth := foot_a - a
		var tone := float(posmod(i * 41, 19) - 9) * 0.006
		var face := _shade(LIGHT_FACE, tone - absf(a.x) / RADIUS.x * 0.22).darkened(0.13)
		_quad(a, b, foot_b, foot_a, face)
		if i % 2 == 0 and (i < BRIDGE_GATE.x or i >= BRIDGE_GATE.y) and not EXTERIOR_ENTRIES.has(i):
			_arch(a.lerp(b, 0.09), a.lerp(b, 0.94), depth.y - 35.0, face, true)
		for course in range(1, 10):
			var band := float(course) / 10.0
			var left := a.lerp(foot_a, band)
			var right := b.lerp(foot_b, band)
			draw_line(left, right, Color(JOINT, 0.38), 1.5)
			if i % 2 != 0:
				var joint := left.lerp(right, 0.39 if course % 2 == 0 else 0.71)
				draw_line(joint, joint + depth * 0.085, Color(JOINT, 0.42), 1.5)
		draw_line(a, a + depth, face.lightened(0.17), 4.0)
		if i % 3 == 2:
			var pilaster := (b - a) * 0.24
			_quad(a, a + pilaster, a + pilaster + depth, a + depth, face.lightened(0.12))
			draw_line(a, a + pilaster, CAP, 7.0)
			draw_line(a + pilaster, a + pilaster + depth, JOINT, 2.0)
		var dust := Color(0.63, 0.42, 0.26, 0.55)
		draw_polygon(PackedVector2Array([a.lerp(foot_a, 0.68), b.lerp(foot_b, 0.68), foot_b, foot_a]),
			PackedColorArray([Color(dust, 0.0), Color(dust, 0.0), dust, dust]))

func _draw_exterior_stairs(section: int) -> void:
	# The door and sand contact use the same facade points as the arcade.
	var first := _foundation_foot(section)
	var last := _foundation_foot(section + 2)
	var center := first.lerp(last, 0.5) - Vector2(0, 78)
	var direction := (first - last).normalized()
	var sill_left := center - direction * 33.0
	var sill_right := center + direction * 33.0
	_arch(sill_left, sill_right, 94.0, CAP.darkened(0.20))
	draw_line(sill_left - Vector2(0, 5), sill_right - Vector2(0, 5), ARCH_DARK, 5.0)

	var tread := ISO_SOUTHEAST * 11.0
	var step_count := 12
	var drop := Vector2(0, 78.0 / step_count)
	var stride := tread + drop
	var landing := ISO_SOUTHEAST * 38.0
	var left := center - ISO_NORTHEAST * 43.0 + landing
	var right := center + ISO_NORTHEAST * 43.0 + landing
	var end_left := left + stride * step_count
	var end_right := right + stride * step_count
	var apron := ISO_SOUTHEAST * 26.0
	var shade := Color(0.28, 0.16, 0.09, 0.42)
	draw_polygon(PackedVector2Array([right + Vector2(0, 78), end_right + apron,
		end_right + apron + Vector2(58, 16), right + Vector2(74, 89)]),
		PackedColorArray([shade, shade, Color(shade, 0.0), Color(shade, 0.0)]))

	var jamb_left := center - direction * 43.0
	var jamb_right := center + direction * 43.0
	_quad(jamb_left, jamb_right, right, left, OCHRE)
	_quad(jamb_left, left, end_left, jamb_left + Vector2(0, 78), RED_STONE)
	_quad(end_left, end_right, end_right + apron, end_left + apron, OCHRE.darkened(0.08))
	draw_line(end_left + apron, end_right + apron, Color(JOINT, 0.54), 3.0)
	_draw_stair_parapet(right, end_right)
	for i in step_count:
		var step_left := left + stride * i
		var step_right := right + stride * i
		var stone := _shade(OCHRE, float(posmod(i * 19, 7) - 3) * 0.024)
		_quad(step_left, step_right, step_right + tread, step_left + tread, stone)
		_quad(step_left + tread, step_right + tread, step_right + stride, step_left + stride, RED_STONE)
		draw_line(step_left + tread, step_right + tread, CAP, 2.0)
		var seam := step_left.lerp(step_right, 0.31 if i % 2 == 0 else 0.64)
		draw_line(seam, seam + tread, Color(JOINT, 0.56), 1.5)
	_draw_stair_parapet(left, end_left)

func _draw_stair_parapet(start: Vector2, end: Vector2) -> void:
	var high := Vector2(0, -21)
	var rim := ISO_NORTHEAST * 9.0
	_quad(start, end, end + high, start + high, RED_STONE)
	_quad(start + high, end + high, end + high + rim, start + high + rim, CAP)
	for joint in range(1, 6):
		var at := start.lerp(end, joint / 6.0)
		draw_line(at, at + high, Color(JOINT, 0.57), 1.5)
		draw_line(at + high, at + high + rim, Color(JOINT, 0.50), 1.5)
	draw_line(end, end + high, JOINT, 3.0)

func _draw_bridge() -> void:
	var threshold_left := _rim(BRIDGE_GATE.y)
	var threshold_right := _rim(BRIDGE_GATE.x)
	var middle := threshold_left.lerp(threshold_right, 0.5) - ISO_NORTHEAST * 42.0
	var side := ISO_SOUTHEAST * (threshold_right.x - threshold_left.x) * 0.92
	var left := middle - side * 0.5
	var right := left + side
	# The short apron joins the ellipse's chord to the projected bridge deck.
	_quad(threshold_left, threshold_right, right, left, OCHRE)
	draw_line(left, right, CAP, 3.0)
	var span := -ISO_NORTHEAST * 445.0
	var base := Vector2(0, FRONT_BRIDGE_DROP)
	var end := right + span
	_quad(left, right, end, left + span, Color("#a97850"))
	_quad(right, end, end + base, right + base, RED_STONE)
	for bay in 5:
		var a := end.lerp(right, bay / 5.0)
		var b := end.lerp(right, (bay + 1) / 5.0)
		_arch(a.lerp(b, 0.10), a.lerp(b, 0.87), base.y, RED_STONE, true)
		draw_line(a + Vector2(0, 4), a + base, LIGHT_FACE, 5.0)
	draw_line(right + Vector2(0, 15), end + Vector2(0, 15), LIGHT_FACE, 3.0)
	_draw_bridge_stairs(left + span, side)
	for i in range(1, 23):
		var a := left + span * (i / 23.0)
		draw_line(a, a + side, JOINT, 2.0)
		draw_line(a - Vector2(0, 2), a + side - Vector2(0, 2), CAP, 1.0)
		var joint := a + side * (float(posmod(i * 13, 11) + 2) / 14.0)
		draw_line(joint, joint + span / 23.0, JOINT, 1.0)
	for edge in [left, right]:
		draw_line(edge - Vector2(0, 10), edge + span - Vector2(0, 10), LIGHT_FACE, 12.0)
		draw_line(edge - Vector2(0, 15), edge + span - Vector2(0, 15), CAP, 3.0)

func _draw_bridge_stairs(start: Vector2, side: Vector2) -> void:
	var tread := -ISO_NORTHEAST * 14.0
	var drop := Vector2(0.0, 8.0)
	var stride := tread + drop
	var end := start + stride * 9.0
	_quad(start + side, end + side, end + side + Vector2(0, 5), start + side + Vector2(0, FRONT_BRIDGE_DROP), RED_STONE)
	for i in 9:
		var a := start + stride * i
		var b := a + side
		_quad(a, b, b + tread, a + tread, OCHRE)
		_quad(a + tread, b + tread, b + stride, a + stride, RED_STONE)
		draw_line(a + tread, b + tread, CAP, 2.0)

func _arch(a: Vector2, b: Vector2, height: float, face: Color, downward := false) -> void:
	var direction := 1.0 if downward else -1.0
	var spring := height * (0.27 if downward else 0.73)
	var base := height if downward else 0.0
	var arch := PackedVector2Array([a + Vector2(0, base * direction)])
	for i in range(9):
		var t := i / 8.0
		var h := spring - sin(PI * t) * height * 0.25 if downward else spring + sin(PI * t) * height * 0.25
		arch.append(a.lerp(b, t) + Vector2(0, h * direction))
	arch.append(b + Vector2(0, base * direction))
	draw_colored_polygon(arch, ARCH_DARK)
	draw_polyline(arch, face.lightened(0.21), 3.0)
	draw_line(arch[0] + Vector2(3, 0), arch[1] + Vector2(3, 0), JOINT, 3.0)

func _draw_wall_shadow() -> void:
	for i in SECTION_COUNT:
		var a := _rim(i)
		var b := _rim(i + 1)
		var reach := 0.076 if a.y < 0.0 else 0.034
		var fade := Color(0.20, 0.08, 0.04, 0.34 if a.y < 0.0 else 0.22)
		draw_polygon(PackedVector2Array([a, b, b * (1.0 - reach), a * (1.0 - reach)]),
			PackedColorArray([fade, fade, Color(fade, 0.0), Color(fade, 0.0)]))

func _draw_stone_fragments() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 66017
	for cluster: Vector2 in DEBRIS_CLUSTERS:
		for i in 16:
			var at := cluster + Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-28.0, 34.0)).round()
			var width := rng.randi_range(3, 13)
			var height := maxf(2.0, roundf(width * 0.43))
			var rim := PackedVector2Array([at - Vector2(width, 0), at - Vector2(2, height),
				at + Vector2(width, -1), at + Vector2(3, height)])
			var rise := Vector2(0.0, rng.randi_range(1, 4))
			draw_colored_polygon(Transform2D(0.0, Vector2(1, 2)) * rim, Color(ARCH_DARK, 0.32))
			_quad(rim[0], rim[3], rim[3] - rise, rim[0] - rise, RED_STONE)
			_quad(rim[3], rim[2], rim[2] - rise, rim[3] - rise, JOINT)
			draw_colored_polygon(Transform2D(0.0, -rise) * rim, _shade(CAP, rng.randf_range(-0.22, 0.03)))

func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), color)

func _shade(color: Color, amount: float) -> Color:
	return color.lightened(amount) if amount >= 0.0 else color.darkened(-amount)
