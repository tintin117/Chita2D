class_name Blast extends Spell
## Standard 1: delayed explosion at the aim point.

const MAX_RANGE := 420.0

func _init() -> void:
	display_name = "Blast"
	cooldown = 3.0
	damage = 28

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var offset := (aim_pos - caster.global_position).limit_length(MAX_RANGE)
	var e := Explosion.new().setup(caster.global_position + offset, 90.0, damage, 0.45, caster)
	caster.get_tree().current_scene.add_child(e)
	return cooldown
