class_name Tumble extends Spell
## Scout right click: roll toward the cursor (up to ROLL px), untouchable while rolling, and the next basic within
## EMPOWER seconds is empowered: HeroBasic.EMPOWER_MULT damage, extra pierce, a big gold arrow. Dodge, then punish.

const ROLL := 220.0
const TIME := 0.22
const EMPOWER := 2.5

## The roll: toward `aim_pos`, at most ROLL long (a cursor on top of you rolls the way you face).
static func roll_vec(from: Vector2, aim_pos: Vector2, facing: Vector2) -> Vector2:
	var v := aim_pos - from
	if v.length() < 8.0:
		v = facing
	return v.normalized() * ROLL

func _init() -> void:
	display_name = "Tumble"
	cooldown = 4.5
	damage = 0
	sfx = "dash"
	cast_pitch = 1.3

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var v := roll_vec(caster.global_position, aim_pos, aim_dir)
	caster.phase(TIME + 0.05)
	if caster.owns():   # only the owner moves it
		caster.lunge(v, TIME, ROLL / TIME)
	if caster.has_method("empower"):
		caster.empower(EMPOWER)
	SheetFrames.play_once(caster.get_parent(), caster.global_position + Vector2(0, 20), SheetFrames.FX + "AoE/IceAoE/", 0, 30.0, 0.2)
	return cooldown
