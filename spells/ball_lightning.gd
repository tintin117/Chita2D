class_name BallLightning extends Spell
## Sorcerer right click: become a ball of lightning and fly to the cursor (up to RANGE, over rocks, not walls) in TRAVEL
## seconds. Untouchable on the way, and every foe on the path takes a hit. The mage's escape and its engage.

const RANGE := 420.0
const TRAVEL := 0.28
const WIDTH := 42.0

## Where it lands for a cast from `from` aimed at `aim_pos`.
static func landing(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(RANGE)

## Foes on the path (reuses Shadow Rush's line test with this spell's width).
static func path_hits(from: Vector2, to: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var seg := to - from
	var len2 := maxf(seg.length_squared(), 1.0)
	for e in foes:
		var t := clampf((e.global_position - from).dot(seg) / len2, 0.0, 1.0)
		if e.global_position.distance_to(from + seg * t) <= WIDTH + 14.0:
			out.append(e)
	return out

class Streak extends Node2D:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= TRAVEL + 0.25:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / TRAVEL, 0.0, 1.0)
		var fade := 1.0 - clampf((_age - TRAVEL) / 0.25, 0.0, 1.0)
		var head := a.lerp(b, k)
		draw_line(a, head, Color(ChainLightning.BOLT, 0.4 * fade), 22.0)
		draw_line(a, head, Color(1, 1, 1, 0.8 * fade), 3.0)
		draw_circle(head, 20.0, Color(ChainLightning.BOLT, 0.7 * fade))
		draw_circle(head, 10.0, Color(1, 1, 1, fade))

func _init() -> void:
	display_name = "Ball Lightning"
	cooldown = 7.0
	damage = 16
	sfx = "dash"
	cast_pitch = 1.7

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var from := caster.global_position
	var to := landing(from, aim_pos)
	caster.phase(TRAVEL + 0.05)
	if caster.owns():   # only the owner moves it; everyone else sees the flight through the replicated position
		caster.leap(to - from, TRAVEL)
	for e in path_hits(from, to, Spell.foes(caster)):
		e.take_damage(damage, from, false, caster)
	var s := Streak.new()
	s.a = from + Vector2(0, -10)
	s.b = to + Vector2(0, -10)
	s.z_index = 6
	caster.get_parent().add_child(s)
	return cooldown
