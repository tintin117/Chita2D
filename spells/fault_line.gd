class_name FaultLine extends Spell
## Rampager ult (Earth Split): he plants his feet (rooted, can still turn) while a crack creeps out from him toward
## the cursor at GROW px/s up to LENGTH. SETTLE seconds after it reaches full length the ground splits: every foe
## within WIDTH / 2 of the line takes MAX_HP_SHARE of its max HP, is pulled onto the line and slowed. The slow crawl is
## the counterplay: see where it goes, step off it. Runs on every peer; damage lands on each victim's own peer.

const LENGTH := 700.0
const WIDTH := 120.0
const GROW := 420.0          ## px/s the crack creeps out
const SETTLE := 0.3          ## full length -> split
const MAX_HP_SHARE := 0.25
const MIN_DMG := 15
const SLOW := [0.5, 3.0]
const COLOR := Color(0.85, 0.6, 0.3)

static func grow_time() -> float:
	return LENGTH / GROW

static func delay() -> float:
	return grow_time() + SETTLE

static func caught(start: Vector2, dir: Vector2, pos: Vector2) -> bool:
	var off := pos - start
	var along := off.dot(dir)
	return along >= -10.0 and along <= LENGTH + 10.0 and absf(off.cross(dir)) <= WIDTH * 0.5 + 14.0

class Crack extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var _age := 0.0
	var _split := false
	var _jag: PackedFloat32Array = []   ## side offsets of the crack's zigzag, fixed per cast

	func _ready() -> void:
		add_to_group("zones")   # bots step out of it
		Sfx.play("crown", global_position, -4.0, 0.5)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 29:
			_jag.append(rng.randf_range(-10.0, 10.0))

	func _physics_process(delta: float) -> void:
		_age += delta
		if not _split and _age >= FaultLine.delay():
			_split = true
			_impact()
		if _age >= FaultLine.delay() + 0.7:
			queue_free()
		queue_redraw()

	func _impact() -> void:
		Sfx.play("bomb_boom", global_position + dir * LENGTH * 0.5, -2.0, 0.7)
		var cam := get_tree().get_first_node_in_group("camera") as GameCamera
		if cam:
			cam.shake(0.4)
		for i in 5:   # dust bursts along the split
			SheetFrames.play_once(get_parent(), global_position + dir * LENGTH * (i + 0.5) / 5.0, SheetFrames.FX + "AoE/SwordAoE/", 0, 30.0, 0.5).modulate = Color(COLOR, 0.8)
		if not is_instance_valid(caster):
			return
		var side_axis := dir.orthogonal()
		for e in Spell.foes(caster):
			if not FaultLine.caught(global_position, dir, e.global_position):
				continue
			var side: float = (e.global_position - global_position).dot(side_axis)
			var to_line := -side_axis * signf(side) if absf(side) > 1.0 else Vector2.ZERO
			var mhp: int = e.max_hp if "max_hp" in e else 100
			var dmg := maxi(roundi(mhp * FaultLine.MAX_HP_SHARE), FaultLine.MIN_DMG)
			if e.take_damage(dmg, e.global_position - to_line * 12.0, false, caster):
				if to_line != Vector2.ZERO:
					Spell.shove(e, to_line * sqrt(2.0 * Player.KNOCK_DECEL * absf(side)))
				if e.has_method("apply_slow"):
					e.apply_slow(FaultLine.SLOW[0], FaultLine.SLOW[1])

	## Bots: step sideways off the line before it splits (zero = not on it, or already split).
	func bot_avoid(pos: Vector2) -> Vector2:
		if _split or not FaultLine.caught(global_position, dir, pos):
			return Vector2.ZERO
		var side := dir.orthogonal()
		return side * (1.0 if (pos - global_position).dot(side) >= 0.0 else -1.0)

	func _crack_points(length: float) -> PackedVector2Array:
		var pts := PackedVector2Array([Vector2.ZERO])
		var n := int(length / 25.0)
		var side := dir.orthogonal()
		for i in range(1, n + 1):
			pts.append(dir * i * 25.0 + side * _jag[mini(i, _jag.size() - 1)])
		return pts

	func _draw() -> void:
		var end := dir * LENGTH
		var side := dir.orthogonal() * WIDTH * 0.5
		var band := PackedVector2Array([side, end + side, end - side, -side])
		if not _split:
			var grown := minf(_age * GROW, LENGTH)
			var k := clampf(_age / FaultLine.delay(), 0.0, 1.0)
			draw_colored_polygon(band, Color(COLOR, 0.05 + 0.12 * k))   # the whole danger zone shows from the start
			draw_line(side, end + side, Color(COLOR, 0.35), 2.0)
			draw_line(-side, end - side, Color(COLOR, 0.35), 2.0)
			var pts := _crack_points(grown)
			if pts.size() > 1:
				draw_polyline(pts, Color(0.2, 0.1, 0.05, 0.9), 7.0)
				draw_polyline(pts, Color(1.0, 0.75, 0.35, 0.6 + 0.4 * k), 3.0)   # glowing seam
			draw_circle(dir * grown, 8.0, Color(1.0, 0.8, 0.4, 0.9))   # the creeping tip
		else:
			var k := clampf((_age - FaultLine.delay()) / 0.7, 0.0, 1.0)
			draw_colored_polygon(band, Color(COLOR, 0.5 * (1.0 - k)))
			draw_polyline(_crack_points(LENGTH), Color(0.12, 0.06, 0.03, 1.0 - k), 14.0)

func _init() -> void:
	display_name = "Earth Split"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "explosion"
	cast_pitch = 0.5

func ult_lock() -> float:
	return delay() + 0.6

func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	var d := (aim_pos - caster.global_position).normalized()
	for e in Spell.foes(caster):
		if caught(caster.global_position, d, e.global_position):
			return true
	return false

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var c := Crack.new()
	c.caster = caster
	c.dir = aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	c.position = caster.global_position + Vector2(0, 10)
	c.z_index = 2
	caster.get_parent().add_child(c)
	if caster.has_method("root"):
		caster.root(grow_time())   # he plants his feet while the crack runs
	return cooldown
