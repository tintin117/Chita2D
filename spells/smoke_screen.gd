class_name SmokeScreen extends Spell
## Rogue ult (Riki-style): drop a cloud of smoke at the cursor for DURATION seconds.
##  - Foes inside swing blind: each of their hits has Player.SMOKE_MISS chance to miss.
##  - The Rogue inside is veiled: gone from everyone else's screen (sprite, name, bar), nothing can lock onto it, bots
##    lose it, and every stab counts as a backstab (Backstab passive).
## Area hits still find a veiled Rogue: an Ember Field or a Meteor thrown into the smoke is the counterplay, and so is
## leaving the cloud. Always fires: it is a zone, not a target.
## Note: the miss chance is output randomness, against pillar 2. Kept because asked; a deterministic version would be
## "every other hit from inside misses".

const MAX_RANGE := 500.0
const RADIUS := 200.0
const DURATION := 4.5
const REFRESH := 0.15   ## statuses granted per frame last this long: they drop almost at once after stepping out

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

static func inside(at: Vector2, pos: Vector2) -> bool:
	return pos.distance_to(at) <= RADIUS

class Cloud extends Node2D:
	var caster: Node2D
	var _age := 0.0
	var _puffs: Array[Vector3] = []   ## x, y, size: visual only

	func _ready() -> void:
		z_index = 8   # above the players: you cannot see who is in there
		add_to_group("zones")
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 26:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * SmokeScreen.RADIUS * 0.85
			_puffs.append(Vector3(cos(a) * r, sin(a) * r * 0.8, rng.randf_range(40.0, 70.0)))

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= SmokeScreen.DURATION:
			queue_free()
			return
		if is_instance_valid(caster) and not caster.down:
			if SmokeScreen.inside(global_position, caster.global_position) and caster.has_method("veil"):
				caster.veil(SmokeScreen.REFRESH)
			for e in Spell.foes(caster):
				if SmokeScreen.inside(global_position, e.global_position) and e.has_method("smoke"):
					e.smoke(SmokeScreen.REFRESH)
		queue_redraw()

	func _draw() -> void:
		var fade := clampf(_age / 0.3, 0.0, 1.0) * clampf((SmokeScreen.DURATION - _age) / 0.5, 0.0, 1.0)
		draw_circle(Vector2.ZERO, SmokeScreen.RADIUS, Color(0.35, 0.33, 0.4, 0.35 * fade))
		for p in _puffs:
			var wob := sin(_age * 1.3 + p.x * 0.05) * 6.0
			draw_circle(Vector2(p.x + wob, p.y), p.z, Color(0.55, 0.52, 0.6, 0.3 * fade))
		draw_arc(Vector2.ZERO, SmokeScreen.RADIUS, 0.0, TAU, 48, Color(0.7, 0.65, 0.8, 0.5 * fade), 2.0)

## Bots: drop it on a fight, not on empty ground (a foe near the spot it lands).
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	var at := spot(caster.global_position, aim_pos)
	for e in Spell.foes(caster):
		if e.global_position.distance_to(at) < RADIUS + 60.0:
			return true
	return false

func _init() -> void:
	display_name = "Smoke Cloud"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "explosion"
	cast_pitch = 0.6

func ult_lock() -> float:
	return DURATION + 0.5

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var c := Cloud.new()
	c.caster = caster
	c.position = spot(caster.global_position, aim_pos)
	caster.get_parent().add_child(c)
	return cooldown
