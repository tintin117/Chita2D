class_name Fiendform extends Spell
## Demonbound ult: TIME seconds as the fiend. His bolts fly SPEED x as fast over the same flight time (so SPEED x the
## range, and Long Malice grows with it) and hit DAMAGE x as hard; a Mirror Torment cast meanwhile lasts longer.
## Bigger and red-lit on every screen (Player._apply_look). The state is set on every peer by the cast.

const TIME := 6.0
const SPEED := 1.4
const DAMAGE := 1.3
const DOUBLE_CHANCE := 0.6   ## each basic has this chance of a second bolt (rolled on the cast's shared seed)
const DOUBLE_SPREAD := 0.14

func _init() -> void:
	display_name = "Demon Form"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "explosion"
	cast_pitch = 0.5

func ult_lock() -> float:
	return TIME + 0.5

func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	var reach: float = caster.hero.attack_range * SPEED if "hero" in caster and caster.hero else 600.0
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) < reach:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	if caster.has_method("fiend"):
		caster.fiend(TIME)
	if caster.has_method("float_text"):
		caster.float_text("DEMON FORM", Color(1.0, 0.35, 0.3), 24)
	SheetFrames.play_once(caster.get_parent(), caster.global_position + Vector2(0, 10), SheetFrames.FX + "AoE/FireAoE/", 0, 30.0, 0.9).modulate = Color(1.0, 0.3, 0.3)
	return cooldown
