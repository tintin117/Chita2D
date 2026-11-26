class_name Riposte extends Spell
## Shade right click: a parry stance for STANCE seconds (Player.parry). The next hit is cancelled; if a player threw it
## and is within Player.RIPOSTE_RANGE, the Shade blinks to it and counter-slashes for a guaranteed crit (the basic x
## Player.RIPOSTE_CRIT), and Focus is primed so the hit after that crits too. A whiffed stance just costs the cooldown.
## Telegraphed by a bright arc in front of the Shade: baiting it out is the counterplay.

const STANCE := 0.5

func _init() -> void:
	display_name = "Riposte"
	cooldown = 5.0
	damage = 0
	sfx = "swing"
	cast_pitch = 1.6

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	if caster.has_method("parry"):
		caster.parry(STANCE)
	return cooldown
