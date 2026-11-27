class_name ChainLightning extends Spell
## Sorcerer basic: an instant zap at the foe nearest the cursor (or in the aim cone) within range_px, which then jumps to
## the nearest foe not yet hit within JUMP of the last one, CHAINS targets in all, each jump weaker (FALLOFF).
## No foe in reach: a short fizzle toward the aim, so a miss still reads. The chain is picked on every peer from the
## same positions (like Shadow Dance); the victim's own peer decides each hit.

const RANGE := 380.0   ## default; the hero's attack_range overrides it through range_px
var range_px := RANGE
const JUMP := 230.0
const CHAINS := 3
const FALLOFF := 0.75        ## each jump deals this much of the one before
const BOLT := Color(0.55, 0.75, 1.0)
const LOCK_RADIUS := 150.0
const ASSIST := 0.55

## The chain from `from`: `first`, then repeatedly the nearest unhit foe within JUMP of the last link, up to `count`.
static func chain(first: Node2D, foes: Array[Node2D], count: int) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if first == null:
		return out
	out.append(first)
	while out.size() < count:
		var last: Node2D = out.back()
		var best: Node2D = null
		var best_d := JUMP
		for e in foes:
			if e in out:
				continue
			var d := e.global_position.distance_to(last.global_position)
			if d <= best_d:
				best_d = d
				best = e
		if best == null:
			break
		out.append(best)
	return out

## Damage of link `i` (0 = the first target).
static func link_damage(base: int, i: int) -> int:
	return maxi(roundi(base * pow(FALLOFF, i)), 1)

class Arc extends Node2D:
	## Jagged bolts along the chain points, fading fast.
	var points: PackedVector2Array
	var big := false
	var _age := 0.0
	var _jitter: Array[PackedVector2Array] = []

	func _ready() -> void:
		z_index = 6
		for i in range(1, points.size()):
			var a := points[i - 1]
			var b := points[i]
			var seg := PackedVector2Array([a])
			for k in range(1, 6):
				var t := k / 6.0
				seg.append(a.lerp(b, t) + (b - a).orthogonal().normalized() * randf_range(-14.0, 14.0))
			seg.append(b)
			_jitter.append(seg)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= 0.22:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - _age / 0.22
		for seg in _jitter:
			draw_polyline(seg, Color(BOLT, 0.5 * k), (10.0 if big else 7.0) * k + 1.0)
			draw_polyline(seg, Color(1, 1, 1, k), 2.5)
		for i in range(1, points.size()):
			draw_circle(points[i], 10.0 * k + 4.0, Color(BOLT, 0.6 * k))

func _init() -> void:
	display_name = "Chain Lightning"
	cooldown = 0.55
	damage = 11
	sfx = "shoot"
	cast_pitch = 1.6

func reach() -> float:
	return range_px

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, LOCK_RADIUS, ASSIST, range_px)

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var from: Vector2 = caster.global_position + Vector2(0, -20)
	var foes := Spell.foes(caster)
	var first: Node2D = lock if is_instance_valid(lock) else Spell.pick_foe(caster, aim_pos, aim_dir, LOCK_RADIUS, ASSIST, range_px)
	var links := chain(first, foes, CHAINS)
	var pts := PackedVector2Array([from])
	for i in links.size():
		var e := links[i]
		pts.append(e.global_position + Vector2(0, -10))
		Player.basic_hit = true
		e.take_damage(link_damage(damage, i), from if i == 0 else links[i - 1].global_position, i > 0, caster)
		Player.basic_hit = false
	if links.is_empty():   # a fizzle: the zap goes a little way and dies
		pts.append(from + aim_dir.normalized() * range_px * 0.35)
	var arc := Arc.new()
	arc.points = pts
	caster.get_parent().add_child(arc)
	return cooldown
