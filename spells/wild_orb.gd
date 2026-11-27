class_name WildOrb extends Spell
## Rampager right click: hurl a slow orb toward the cursor (MIN..RANGE) and vanish into it (Player.vanish: unseen,
## untouchable, rooted, no casting). It hits every foe it passes once; where it lands it goes off with a BANG (area
## damage), and a beat later he appears there. No recast, no cancel: he is committed, and everyone sees where it lands.
## The orb runs on every peer; only the owner moves (Player.blink_to), the others follow through net_pos.

const RANGE := 500.0
const MIN := 140.0
const SPEED := 580.0
const RADIUS := 34.0
const BANG_RADIUS := 120.0
const BANG_DMG := 18
const APPEAR_DELAY := 0.12   ## bang first, then he appears
const COLOR := Color(0.85, 0.6, 0.3)   ## the hero's signature colour (Hero.basic_color)

class Orb extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 10
	var dist := RANGE
	var _flown := 0.0
	var _hits: Array[Node] = []
	var _banged := -1.0   ## seconds since the bang, -1 = still flying

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		if _banged >= 0.0:   # the bang went off: he steps out of it a beat later
			_banged += delta
			if _banged >= WildOrb.APPEAR_DELAY:
				if caster.has_method("owns") and caster.owns():
					caster.blink_to(global_position)
				if caster.has_method("end_vanish"):
					caster.end_vanish()
				queue_free()
			queue_redraw()
			return
		var step := minf(SPEED * delta, dist - _flown)
		global_position += dir * step
		_flown += step
		for e in Spell.foes(caster):
			if e in _hits or e.global_position.distance_to(global_position) > RADIUS + 14.0:
				continue
			_hits.append(e)
			e.take_damage(dmg, global_position - dir * 10.0, false, caster)
		if _flown >= dist - 0.5:
			_bang()
		queue_redraw()

	## Where it lands it bursts: everyone within BANG_RADIUS takes BANG_DMG, then he appears in the dust.
	func _bang() -> void:
		_banged = 0.0
		Sfx.play("explosion", global_position, 0.0, 1.1)
		SheetFrames.play_once(get_parent(), global_position + Vector2(0, 12), SheetFrames.FX + "AoE/FireAoE/", 0, 30.0, WildOrb.BANG_RADIUS / 110.0).modulate = COLOR
		var cam := get_tree().get_first_node_in_group("camera") as GameCamera
		if cam and Player.is_local(caster):
			cam.shake(0.3)
		for e in Spell.foes(caster):
			if e.global_position.distance_to(global_position) <= WildOrb.BANG_RADIUS + 14.0:
				e.take_damage(WildOrb.BANG_DMG, global_position, false, caster)

	func _draw() -> void:
		if _banged >= 0.0:   # the shock ring of the bang
			var k := _banged / WildOrb.APPEAR_DELAY
			draw_arc(Vector2.ZERO, WildOrb.BANG_RADIUS * (0.5 + 0.5 * k), 0.0, TAU, 40, Color(1, 0.95, 0.8, 1.0 - k), 6.0)
			return
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		draw_circle(Vector2.ZERO, RADIUS * (1.2 + 0.15 * pulse), Color(COLOR, 0.2))
		draw_circle(Vector2.ZERO, RADIUS * 0.6, COLOR)
		draw_circle(Vector2(-4, -4), RADIUS * 0.25, Color(1, 1, 0.85, 0.9))

## Where the orb lands (and so where he ends up) for a cast from `from` at `aim_pos`.
static func landing(from: Vector2, aim_pos: Vector2, dir: Vector2) -> Vector2:
	return from + dir.normalized() * clampf(from.distance_to(aim_pos), MIN, RANGE)

func _init() -> void:
	display_name = "Illusion Orb"
	cooldown = 7.0
	damage = 10
	sfx = "swing"
	cast_pitch = 0.6

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var o := Orb.new()
	o.caster = caster
	o.dir = d
	o.dmg = damage
	o.dist = clampf(caster.global_position.distance_to(aim_pos), MIN, RANGE)
	o.position = caster.global_position + Vector2(0, -4)
	o.z_index = 6
	caster.get_parent().add_child(o)
	if caster.has_method("vanish"):
		caster.vanish(o.dist / SPEED + APPEAR_DELAY + 0.2)   # the orb ends it on landing (end_vanish); this is a safety cap
	return cooldown
