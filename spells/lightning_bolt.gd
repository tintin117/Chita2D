class_name LightningBolt extends Spell
## Sorcerer right click (Zeus): a bolt from the sky on the cursor (up to MAX_RANGE). A ring shows the spot for DELAY
## seconds, then everyone within RADIUS takes `damage`, is slowed, and is REVEALED for REVEAL seconds: a Rogue in his
## Smoke Screen shows up and can be locked onto again. The Sorcerer's answer to the smoke.

const MAX_RANGE := 560.0
const RADIUS := 75.0
const DELAY := 0.3
const SLOW := Vector2(0.6, 1.0)
const REVEAL := 2.5

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

static func caught(at: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for e in foes:
		if e.global_position.distance_to(at) <= RADIUS + 14.0:
			out.append(e)
	return out

class Strike extends Node2D:
	var caster: Node2D
	var dmg := 26
	var _age := 0.0
	var _hit := false

	func _physics_process(delta: float) -> void:
		_age += delta
		if not _hit and _age >= DELAY:
			_hit = true
			_strike()
		if _age >= DELAY + 0.3:
			queue_free()
		queue_redraw()

	func _strike() -> void:
		Sfx.play("explosion", global_position, -2.0, 1.7)
		if not is_instance_valid(caster):
			return
		for e in LightningBolt.caught(global_position, Spell.foes(caster)):   # veiled players are in foes(): only lock-on skips them
			if e.has_method("reveal"):
				e.reveal(REVEAL)
			if e.take_damage(dmg, global_position, false, caster) and e.has_method("apply_slow"):
				e.apply_slow(SLOW.x, SLOW.y)

	func _draw() -> void:
		if not _hit:
			var k := clampf(_age / DELAY, 0.0, 1.0)
			draw_circle(Vector2(0, 14), RADIUS, Color(ChainLightning.BOLT, 0.12 + 0.2 * k))
			draw_arc(Vector2(0, 14), RADIUS, 0.0, TAU, 32, Color(ChainLightning.BOLT, 0.9), 3.0)
			return
		var k := 1.0 - clampf((_age - DELAY) / 0.3, 0.0, 1.0)
		var top := Vector2(randf_range(-15, 15), -520)
		var pts := PackedVector2Array([top])
		for i in range(1, 7):
			pts.append(top.lerp(Vector2(0, 14), i / 7.0) + Vector2(randf_range(-20, 20), 0))
		pts.append(Vector2(0, 14))
		draw_polyline(pts, Color(ChainLightning.BOLT, 0.6 * k), 14.0 * k + 1.0)
		draw_polyline(pts, Color(1, 1, 1, k), 3.0)
		draw_circle(Vector2(0, 14), RADIUS * (1.0 - 0.5 * k), Color(1, 1, 1, 0.35 * k))

func _init() -> void:
	display_name = "Lightning Bolt"
	cooldown = 6.0
	damage = 26
	sfx = "shoot"
	cast_pitch = 1.8

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var s := Strike.new()
	s.caster = caster
	s.dmg = damage
	s.position = spot(caster.global_position, aim_pos)
	s.z_index = 6
	caster.get_parent().add_child(s)
	return cooldown
