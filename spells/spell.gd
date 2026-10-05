class_name Spell extends Resource
## Base spell. Subclass and override cast(); this is the seam for custom skill mechanics.

@export var display_name := "Spell"
@export var cooldown := 0.5
@export var damage := 10
@export var charge_cost := 0.0   ## signature meter needed (0 = none)
@export var icon: Texture2D

## Returns the cooldown (seconds) to apply after this cast.
func cast(_caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	return cooldown
