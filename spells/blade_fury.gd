class_name BladeFury extends Spell
## Shade ult: spin for DURATION seconds (Player.spin). Every TICK, every foe within RADIUS takes a hit. While spinning
## the Shade takes no damage, cannot be stunned or frozen, and cannot attack, but walks at full speed: chase them down
## or hold a spot. The counterplay is distance: walk away and wait it out.
## Silent hits, so the spin keeps foes close instead of bouncing them away. Needs a foe within REACH to start.

const DURATION := 2.5
const RADIUS := 115.0
const TICK := 0.2
const REACH := 220.0

class Fury extends Node2D:
	var caster: Node2D
	var dmg := 6
	var _age := 0.0
	var _next := 0.0

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down or _age >= DURATION:
			queue_free()
			return
		global_position = caster.global_position
		if _age >= _next:
			_next += TICK
			for e in Spell.foes(caster):
				if e.global_position.distance_to(global_position) <= RADIUS + 14.0:
					e.take_damage(dmg, global_position, true, caster)
			Sfx.play("swing", global_position, -10.0, 1.3 + randf() * 0.3)

func _init() -> void:
	display_name = "Blade Spin"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 6
	sfx = "swing"
	cast_pitch = 0.7

## Bots only: is anyone there to make it worth spending the charge? (Players can always cast it.)
func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) <= REACH:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	if caster.has_method("spin"):
		caster.spin(DURATION)
	var f := Fury.new()
	f.caster = caster
	f.dmg = damage
	caster.get_parent().add_child(f)
	return cooldown
