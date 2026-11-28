class_name ReboundShield extends Spell
## Knight right click: throw the shield. It flies at the foe under the cursor (or straight ahead), and every foe it hits
## sends it on to the nearest foe it has not hit yet within BOUNCE, up to MAX_HITS foes, each hit weaker (FALLOFF).
## Then it flies home to the Knight wherever he is. The first foe hit is slowed. While the shield is away Bulwark is
## off (Player.shield_out): throwing it is a choice. A dash shakes off its homing, like any locked shot.
## Runs on every peer (like the Hammer); damage lands on each victim's own peer.

const SPEED := 950.0
const RANGE := 400.0          ## the first flight
const BOUNCE := 300.0         ## a bounce looks this far from the foe it just hit
const MAX_HITS := 3
const FALLOFF := [1.0, 0.75, 0.55]
const RADIUS := 26.0
const SLOW := [0.6, 1.0]      ## first foe hit: speed multiplier, seconds
const PICK_RADIUS := 150.0

## The next foe a bounce goes for: the nearest one within BOUNCE of `from` not hit yet, or null.
static func next_target(caster: Node2D, from: Vector2, hit: Array[Node]) -> Node2D:
	var best: Node2D = null
	var best_d := BOUNCE
	for e in Spell.foes(caster):
		if e in hit or (e.has_method("hidden_from") and e.hidden_from(caster)):
			continue
		var d := e.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = e
	return best

class Disc extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var velocity := Vector2.ZERO   ## for bots to dodge (group dodgeables)
	var dmg := 18
	var target: Node2D
	var _left := RANGE
	var _hits: Array[Node] = []
	var _back := false
	const FLIGHT_HEIGHT := Vector2(0, -20)
	const LAUNCH_BLEND := 0.08
	const CATCH_BLEND := 76.0
	const WAKE_LENGTH := 9

	var release_at: Vector2
	var _age := 0.0
	var _art_at: Vector2
	var _wake := PackedVector2Array()

	func _ready() -> void:
		add_to_group("dodgeables")
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		z_index = KnightFx.shield_depth(caster)
		_art_at = release_at
		KnightFx.shield_glint(caster, release_at, false)
		if caster is Player:
			caster.shield_out = true

	func _exit_tree() -> void:
		if is_instance_valid(caster) and caster is Player:
			caster.shield_out = false

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		_age += delta
		var step := SPEED * delta
		if _back:
			var to: Vector2 = caster.global_position + Vector2(0, -6) - global_position
			if to.length() <= step + 10.0:
				KnightFx.shield_glint(caster, KnightFx.shield_point(caster, false), true)
				queue_free()
				return
			dir = to.normalized()
			global_position += dir * step
			var blend := 1.0 - smoothstep(0.0, CATCH_BLEND, to.length() - step)
			_update_art((global_position + FLIGHT_HEIGHT).lerp(KnightFx.shield_point(caster, false), blend))
			if blend > 0.55:
				z_index = KnightFx.shield_depth(caster)
			return
		if is_instance_valid(target) and not target.down and not (target.has_method("dodging") and target.dodging()):
			dir = (target.global_position + Vector2(0, -4) - global_position).normalized()
		else:
			target = null
		global_position += dir * step
		velocity = dir * SPEED
		var launch := smoothstep(0.0, LAUNCH_BLEND, _age)
		_update_art(release_at.lerp(global_position + FLIGHT_HEIGHT, launch))
		if launch >= 1.0:
			z_index = 6
		_left -= step
		for e in Spell.foes(caster):
			if e in _hits or e.global_position.distance_to(global_position) > RADIUS + 16.0:
				continue
			_strike(e)
			return
		if _left <= 0.0:
			_back = true

	func _strike(e: Node2D) -> void:
		_hits.append(e)
		var k: float = ReboundShield.FALLOFF[mini(_hits.size() - 1, ReboundShield.FALLOFF.size() - 1)]
		var landed: bool = e.take_damage(maxi(roundi(dmg * k), 1), global_position - dir * 10.0, false, caster, KnightFx.SHIELD)
		if landed and _hits.size() == 1 and e.has_method("apply_slow"):
			e.apply_slow(ReboundShield.SLOW[0], ReboundShield.SLOW[1])
		Sfx.play("hit", global_position, -4.0, 1.4 + 0.15 * _hits.size())   # a rising "ting" per bounce
		if _hits.size() >= ReboundShield.MAX_HITS:
			_back = true
			return
		target = ReboundShield.next_target(caster, e.global_position, _hits)
		if target == null:
			_back = true
			return
		_left = ReboundShield.BOUNCE + 60.0
		dir = (target.global_position - global_position).normalized()

	func _update_art(at: Vector2) -> void:
		_art_at = at
		if _wake.is_empty() or _wake[-1].distance_squared_to(at) > 9.0:
			_wake.append(at)
			if _wake.size() > WAKE_LENGTH:
				_wake.remove_at(0)
		queue_redraw()

	func _draw() -> void:
		var tint := KnightFx.STEEL if _back else KnightFx.GOLD
		for i in range(1, _wake.size()):
			var strength := float(i) / WAKE_LENGTH
			var a := to_local(_wake[i - 1])
			var b := to_local(_wake[i])
			draw_line(a, b, Color(KnightFx.INK, strength * 0.45), 3.0 + strength * 10.0)
			draw_line(a, b, Color(tint, strength * 0.8), 1.0 + strength * 4.0)
			if i % 2 == 0:
				var spark := a + (b - a).orthogonal().normalized() * (7.0 if i % 4 == 0 else -7.0)
				draw_rect(Rect2(spark.round(), Vector2(2, 2)), Color(tint, strength * 0.8))
		KnightFx.draw_disc(self, to_local(_art_at), dir, _age * (35.0 if _back else 45.0))

func _init() -> void:
	display_name = "Rebound Shield"
	cooldown = 6.0
	damage = 18
	sfx = "swing"
	cast_pitch = 0.75

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.45, RANGE + 40.0)

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.45, RANGE)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var disc := Disc.new()
	disc.caster = caster
	disc.dir = d
	disc.dmg = damage
	disc.target = lock if is_instance_valid(lock) else null
	disc.release_at = KnightFx.shield_point(caster, true)
	caster.get_parent().add_child(disc)
	disc.global_position = caster.global_position + Vector2(0, -6) + d * 26.0
	return cooldown
