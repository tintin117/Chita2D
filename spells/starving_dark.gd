class_name StarvingDark extends Spell
## Pactknight ult: a sphere of hungry dark at the cursor for TIME seconds. Foes inside are slowed, take DMG cold damage
## every TICK, and swing blind (Player.smoke: each of their hits may miss). Area damage, so it finds anyone hiding in it.
## Runs on every peer; the ticks land on each victim's own peer (silent, like a burn).

const MAX_RANGE := 500.0
const RADIUS := 190.0
const TIME := 4.0
const TICK := 0.5
const DMG := 5
const SLOW := 0.55
const REFRESH := 0.15
const COLOR := Color(0.2, 0.1, 0.3)

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

class Dark extends Node2D:
	var caster: Node2D
	var _age := 0.0
	var _tick := TICK

	func _ready() -> void:
		z_index = 8   # over the players: it is dark in there
		add_to_group("zones")

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= TIME:
			queue_free()
			return
		_tick -= delta
		var bite := _tick <= 0.0
		if bite:
			_tick += TICK
		if is_instance_valid(caster) and not caster.down:
			for e in Spell.foes(caster):
				if e.global_position.distance_to(global_position) > RADIUS:
					continue
				if e.has_method("smoke"):
					e.smoke(REFRESH)
				if e.has_method("apply_slow"):
					e.apply_slow(SLOW, REFRESH)
				if bite:
					e.take_damage(DMG, global_position, true, caster)
		queue_redraw()

	func bot_avoid(pos: Vector2) -> Vector2:
		var off := pos - global_position
		return off.normalized() if off.length() < RADIUS + 40.0 and off.length() > 1.0 else Vector2.ZERO

	func _draw() -> void:
		var fade := clampf(_age / 0.3, 0.0, 1.0) * clampf((TIME - _age) / 0.5, 0.0, 1.0)
		draw_circle(Vector2.ZERO, RADIUS, Color(COLOR, 0.6 * fade))
		for i in 8:   # slow-turning tendrils
			var a := TAU * i / 8.0 + _age * 0.6
			draw_line(Vector2.from_angle(a) * RADIUS * 0.3, Vector2.from_angle(a + 0.4) * RADIUS * 0.95, Color(0.55, 0.35, 0.8, 0.35 * fade), 5.0)
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 56, Color(0.6, 0.4, 0.9, 0.7 * fade), 3.0)

func _init() -> void:
	display_name = "Hunger Void"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = DMG
	sfx = "explosion"
	cast_pitch = 0.4

func ult_lock() -> float:
	return TIME + 0.5

func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	var at := spot(caster.global_position, aim_pos)
	for e in Spell.foes(caster):
		if e.global_position.distance_to(at) <= RADIUS * 0.8:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var d := Dark.new()
	d.caster = caster
	d.position = spot(caster.global_position, aim_pos)
	caster.get_parent().add_child(d)
	return cooldown
