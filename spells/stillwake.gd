class_name Stillwake extends Spell
## Chaos Lord ult: stop time in a circle at the cursor. Everyone inside but him (allies too) is held in stopped time
## for as long as the field lasts, anyone who walks in is caught for what is left, and he moves and swings freely in it.
## Loaded Dice sets the length: BASE x roll (0.4 .. 2.8 s). The hold ignores the stun immunity (it is the ult) and
## starts it when time runs again (Player.chrono_hold). Runs on every peer.

const MAX_RANGE := 450.0
const RADIUS := 180.0
const BASE := 0.8
const COLOR := Color(0.95, 0.3, 0.85)   ## the hero's signature colour (Hero.basic_color)

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

class Field extends Node2D:
	var caster: Node2D
	var dur := BASE
	var _age := 0.0

	func _ready() -> void:
		add_to_group("zones")

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= dur or not is_instance_valid(caster):
			queue_free()
			return
		for e in Spell.foes(caster):
			if e.global_position.distance_to(global_position) <= RADIUS and e.has_method("chrono_hold"):
				e.chrono_hold(dur - _age)
		queue_redraw()

	func bot_avoid(pos: Vector2) -> Vector2:
		var off := pos - global_position
		return off.normalized() if off.length() < RADIUS + 40.0 and off.length() > 1.0 else Vector2.ZERO

	func _draw() -> void:
		var k := clampf(_age / dur, 0.0, 1.0)
		draw_circle(Vector2.ZERO, RADIUS, Color(COLOR, 0.22))
		draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 64, Color(COLOR, 0.9), 4.0)
		draw_arc(Vector2.ZERO, RADIUS - 10.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - k), 48, Color(1, 1, 1, 0.7), 3.0)   # time left

func _init() -> void:
	display_name = "Time Sphere"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "crown"
	cast_pitch = 0.5

func ult_lock() -> float:
	return BASE * Chaos.HI + 0.5

func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	var at := spot(caster.global_position, aim_pos)
	for e in Spell.foes(caster):
		if e.global_position.distance_to(at) <= RADIUS * 0.8:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var f := Field.new()
	f.caster = caster
	f.dur = BASE * Chaos.roll(caster)
	f.position = spot(caster.global_position, aim_pos)
	f.z_index = 3
	caster.get_parent().add_child(f)
	return cooldown
