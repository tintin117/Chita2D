class_name ConnectionLost extends Spell
## Six Seven ult: drop everyone's connection around you. Every foe within RADIUS is frozen (stopped time, Player.chrono_hold)
## for FREEZE seconds with "CONNECTION LOST" over its head; then you are overclocked: your basic attacks twice as fast
## for OVERCLOCK seconds (Player.overclock, it starts now and covers the freeze). Runs on every peer.

const RADIUS := 260.0
const FREEZE := 1.0
const OVERCLOCK := 4.0         ## the freeze + 3 s of double attack speed
const COLOR := Color(0.85, 0.9, 1.0)

class Glitch extends Node2D:
	var color := COLOR
	var _age := 0.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= 0.5:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := _age / 0.5
		draw_circle(Vector2.ZERO, RADIUS * (0.3 + 0.7 * k), Color(color, 0.18 * (1.0 - k)))
		draw_arc(Vector2.ZERO, RADIUS * (0.3 + 0.7 * k), 0.0, TAU, 40, Color(color, 1.0 - k), 4.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_age * 30.0)   # glitch bars that jump a few times a second (visual only)
		for i in 6:
			var y := rng.randf_range(-RADIUS, RADIUS) * 0.7
			draw_rect(Rect2(Vector2(-RADIUS * 0.6, y), Vector2(RADIUS * 1.2 * rng.randf(), 6.0)), Color(1.0, 0.45, 0.75, 0.5 * (1.0 - k)))

func _init() -> void:
	display_name = "Connection Lost"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "crown"
	cast_pitch = 1.8

func ult_lock() -> float:
	return OVERCLOCK + 0.5

func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) < RADIUS * 0.8:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) <= RADIUS and e.has_method("chrono_hold"):
			e.chrono_hold(FREEZE, "CONNECTION LOST")
	if caster.has_method("overclock"):
		caster.overclock(OVERCLOCK)
	if caster.has_method("float_text"):
		caster.float_text("6... 7!", Color(0.2, 1.0, 0.9), 26)
	var g := Glitch.new()
	if "hero" in caster and caster.hero:
		g.color = caster.hero.basic_color
	g.position = caster.global_position + Vector2(0, 8)
	g.z_index = 4
	caster.get_parent().add_child(g)
	return cooldown
