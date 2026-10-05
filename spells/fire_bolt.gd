class_name FireBolt extends Spell
## Basic attack: 3-hit combo, the 3rd cast fires a 3-bolt spread.

const SPEED := 640.0
var _combo := 0
var _last_cast_msec := 0

func _init() -> void:
	display_name = "Fire Bolt"
	cooldown = 0.28
	damage = 10

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var now := Time.get_ticks_msec()
	if now - _last_cast_msec > 900:
		_combo = 0
	_last_cast_msec = now
	var finisher := _combo == 2
	_combo = 0 if finisher else _combo + 1
	var angles := [-0.22, 0.0, 0.22] if finisher else [0.0]
	for a: float in angles:
		var dir := aim_dir.rotated(a)
		var p := Projectile.new().setup(caster.global_position + dir * 28.0 + Vector2(0, 8), dir * SPEED, damage, true, caster)
		caster.get_tree().current_scene.add_child(p)
	return 0.6 if finisher else cooldown
