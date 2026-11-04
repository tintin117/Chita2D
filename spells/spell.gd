class_name Spell extends Resource
## Base spell. Subclass and override cast(); this is the seam for custom skill mechanics.

@export var display_name := "Spell"
@export var cooldown := 0.5
@export var damage := 10
@export var icon: Texture2D
@export var sfx := "swing"       ## Sfx sound played on cast (see scripts/sfx.gd)

## Returns the cooldown (seconds) to apply after this cast.
func cast(_caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	return cooldown

## Everything a cast by `caster` can hurt: the other living players (PvP). Add enemies here for PvE later.
static func foes(caster: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for n in caster.get_tree().get_nodes_in_group("players") + caster.get_tree().get_nodes_in_group("dummies"):
		if n != caster and not n.down and not (n.has_method("phased") and n.phased()):
			out.append(n)
	return out

## True if a solid obstacle (rock, wall) is within `dist` of `from` along `dir`.
static func solid_ahead(caster: Node2D, from: Vector2, dir: Vector2, dist: float) -> bool:
	if not caster.is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters2D.create(from, from + dir.normalized() * dist, Player.SOLID_MASK | Player.WALL_MASK)
	return not caster.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

## Pushes a foe on the peer that owns it (a bot is owned by the peer running it; a dummy ignores it).
static func shove(foe: Node, vec: Vector2) -> void:
	if (foe.owns() if foe.has_method("owns") else foe.is_multiplayer_authority()):
		foe.knock += vec

## Aim assist: `dir` bent toward the closest foe inside `max_angle` (radians) and `max_dist`; unchanged if none.
static func assist_dir(caster: Node2D, dir: Vector2, max_angle: float, max_dist: float) -> Vector2:
	var best: Vector2 = dir
	var best_off: float = max_angle
	for e: Node2D in foes(caster):
		var off: Vector2 = e.global_position - caster.global_position
		var ang: float = absf(dir.angle_to(off))
		if off.length() <= max_dist and ang <= best_off:
			best_off = ang
			best = off.normalized()
	return best
