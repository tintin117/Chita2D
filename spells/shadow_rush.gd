class_name ShadowRush extends Spell
## Rogue right click: blink in a straight line toward the cursor. Every foe the line passes through takes a light hit and
## is Frozen (Player.freeze): it cannot move, dash or turn, but can still attack the way it was facing.
## The trick it teaches: rush THROUGH someone who is looking at you, and you land at their back while they cannot turn:
## free backstabs. Rush badly (land in front) and the frozen foe still swings at you. Untargetable for the blink itself.

const RANGE := 380.0       ## blink length with nobody on the line
const WIDTH := 38.0        ## a foe this close to the line is caught (plus its own body)
const BEHIND := 60.0       ## a foe caught near the end of the line: the blink carries on this far past it
const FREEZE := 0.8
const PHASE := 0.2
const ICE := Color(0.55, 0.85, 1.0)

## Foes within WIDTH of the segment `from` -> `to`, nearest to `from` first. Pure, so tests and every peer agree.
static func hits(from: Vector2, to: Vector2, foes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var seg := to - from
	var len2 := maxf(seg.length_squared(), 1.0)
	for e in foes:
		var t := clampf((e.global_position - from).dot(seg) / len2, 0.0, 1.0)
		if e.global_position.distance_to(from + seg * t) <= WIDTH + 14.0:
			out.append(e)
	out.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return out

## How far the blink goes along `dir`: RANGE, or past the farthest foe on the line by BEHIND (never more than
## RANGE + BEHIND), so a foe caught at the tip still ends up with the Rogue at its back.
static func length_along(from: Vector2, dir: Vector2, foes: Array[Node2D]) -> float:
	var d := dir.normalized()
	var reach := RANGE
	for e in hits(from, from + d * RANGE, foes):
		reach = maxf(reach, (e.global_position - from).dot(d) + BEHIND)
	return minf(reach, RANGE + BEHIND)

class Trail extends Node2D:
	## A fading streak from the start to the landing, and a frost ring on everyone caught.
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var caught: Array[Vector2] = []
	var _age := 0.0
	const LIFE := 0.45

	func _process(delta: float) -> void:
		_age += delta
		if _age >= LIFE:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := 1.0 - _age / LIFE
		draw_line(a, b, Color(ShadowRush.ICE, 0.25 * k), 26.0 * k + 2.0)
		draw_line(a, b, Color(1, 1, 1, 0.7 * k), 4.0)
		for p in caught:
			draw_arc(p + Vector2(0, 14), 30.0 + 20.0 * (1.0 - k), 0.0, TAU, 24, Color(ShadowRush.ICE, k), 4.0)

func _init() -> void:
	display_name = "Shadow Rush"
	cooldown = 6.0
	damage = 8         # light: a flinch, not a launch; the freeze is the point
	sfx = "dash"
	cast_pitch = 1.4

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var from := caster.global_position
	var dir := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var foes := Spell.foes(caster)
	var to := from + dir * length_along(from, dir, foes)
	if caster.is_inside_tree():   # hard walls stop the line (rocks do not, like a dash); blink_to does the same clip
		var q := PhysicsRayQueryParameters2D.create(from, to, Player.WALL_MASK)
		var wall := caster.get_world_2d().direct_space_state.intersect_ray(q)
		if not wall.is_empty():
			to = wall.position - dir * 24.0
	var caught := hits(from, to, foes)
	var dust := SheetFrames.FX + "AoE/DeathAoE/"
	SheetFrames.play_once(caster.get_parent(), from + Vector2(0, 20), dust, 0, 30.0, 0.25)
	caster.phase(PHASE)
	var trail := Trail.new()
	trail.z_index = 6
	trail.a = from
	trail.b = to
	for e in caught:
		trail.caught.append(e.global_position)
		if e.take_damage(damage, from, false, caster):   # dodged (dash / i-frames): no freeze
			Spell.freeze(e, FREEZE)
	if caster.owns():   # only the owner moves it; everyone else sees it arrive through the replicated position
		caster.blink_to(to)
		if not caught.is_empty():
			caster.aim_dir = (caught.back().global_position - caster.global_position).normalized()   # turn to face the backs
	caster.get_parent().add_child(trail)
	SheetFrames.play_once(caster.get_parent(), to + Vector2(0, 20), dust, 0, 30.0, 0.25)
	return cooldown
