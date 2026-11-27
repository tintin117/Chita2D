class_name GuardianAngel extends Spell
## Paladin ult: for DURATION seconds nothing can hurt you (Player.guardian), and every hit you land heals you for half
## its damage (Player.ANGEL_STEAL). A halo and wings show it on every screen: the counterplay is to back off and wait.
## No target needed: it is a self-buff, so it always fires.

const DURATION := 3.0

func _init() -> void:
	display_name = "Guardian Grace"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "crown"
	cast_pitch = 0.8

func ult_lock() -> float:
	return DURATION + 0.5

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	if caster.has_method("guardian"):
		caster.guardian(DURATION)
	if caster.has_method("float_text"):
		caster.float_text("GUARDIAN ANGEL", Color(1.0, 0.9, 0.5), 22)
	return cooldown
