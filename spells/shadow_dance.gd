class_name ShadowDance extends Spell
## Rogue ult: marks up to STRIKES foes in reach (nearest the cursor first), then after a MARK telegraph blinks behind
## each one in turn and stabs it. Landing behind means the Backstab passive always pays (hero.back_mult).
## A foe takes at most MAX_PER_FOE strikes, so a lone target is hurt badly but not deleted from full HP.
## Untargetable for the whole dance. The mark is the counterplay: a dash or a phase in that window slips the strike.

const RANGE := 520.0       ## a foe must be this close to be marked
const HOP_RANGE := 620.0   ## each blink reaches this far from where the last one landed; farther = that strike is skipped
const STRIKES := 3
const MAX_PER_FOE := 2
const MARK := 0.35         ## telegraph before the first strike
const GAP := 0.22          ## seconds between strikes
const BEHIND := 58.0
const MARK_COLOR := Color(0.75, 0.35, 1.0)

## The strike order for foes sorted by priority: round-robin, at most `max_per` each, `strikes` in total.
## [A, B] -> [A, B, A]; [A] -> [A, A]; [A, B, C, D] -> [A, B, C]. Pure, so tests and every peer agree.
static func plan(targets: Array, strikes := STRIKES, max_per := MAX_PER_FOE) -> Array:
	var out := []
	if targets.is_empty():
		return out
	for round_i in max_per:
		for t in targets:
			if out.size() >= strikes:
				return out
			out.append(t)
	return out

## Foes within RANGE of `from`, nearest to `aim_pos` first.
static func pick(from: Vector2, aim_pos: Vector2, foes: Array[Node2D]) -> Array:
	var near: Array = []
	for e in foes:
		if e.global_position.distance_to(from) <= RANGE:
			near.append(e)
	near.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(aim_pos) < b.global_position.distance_to(aim_pos))
	return near

class Dance extends Node2D:
	var caster: Node2D
	var order: Array = []
	var dmg := 18
	var _age := 0.0
	var _next := 0
	var _trail: Array[Vector2] = []   ## landing points, for the afterimage line

	func _ready() -> void:
		z_index = 6
		var marked := {}
		for t in order:
			if is_instance_valid(t) and not marked.has(t):
				marked[t] = true
				if t.has_method("float_text"):
					t.float_text("MARKED", MARK_COLOR, 22)

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down or (caster.has_method("stunned") and caster.stunned()):
			queue_free()
			return
		while _next < order.size() and _age >= MARK + _next * GAP:
			_strike(order[_next])
			_next += 1
		if _next >= order.size() and _age >= MARK + order.size() * GAP + 0.3:
			queue_free()
		queue_redraw()

	func _strike(foe: Node2D) -> void:
		if not is_instance_valid(foe) or foe.down:
			return
		var from: Vector2 = caster.global_position
		if from.distance_to(foe.global_position) > HOP_RANGE:
			return   # it ran: that strike is lost
		var facing: Vector2 = foe.aim_dir if "aim_dir" in foe else (foe.global_position - from).normalized()
		var dest: Vector2 = foe.global_position - facing.normalized() * BEHIND
		var dust := SheetFrames.FX + "AoE/DeathAoE/"
		SheetFrames.play_once(caster.get_parent(), from + Vector2(0, 20), dust, 0, 30.0, 0.25)
		if caster.owns():   # only the owner moves it; everyone else sees it arrive through the replicated position
			caster.blink_to(dest)
			caster.aim_dir = (foe.global_position - dest).normalized()
		SheetFrames.play_once(caster.get_parent(), dest + Vector2(0, 20), dust, 0, 30.0, 0.25)
		Sfx.play("dash", dest, 0.0, 1.6)
		_trail.append(dest)
		var hit := dmg
		var back: float = caster.hero.back_mult if "hero" in caster and caster.hero else 1.0
		if back > 1.0 and HeroBasic.Sweep.from_behind(foe, dest):   # the passive: landing behind is the whole point
			hit = roundi(dmg * back)
			if foe.has_method("float_text"):
				foe.float_text("BACKSTAB", Color(1.0, 0.45, 0.9), 22)
		foe.take_damage(hit, dest, false, caster)

	func _draw() -> void:
		# marks under every foe still waiting for its strike: the telegraph that gives them a chance to dash
		var pulse := 0.5 + 0.5 * sin(_age * 18.0)
		for i in range(_next, order.size()):
			var t: Node2D = order[i]
			if not is_instance_valid(t) or t.down:
				continue
			var at := to_local(t.global_position) + Vector2(0, 14)
			draw_arc(at, 34.0 + 4.0 * pulse, 0.0, TAU, 28, Color(MARK_COLOR, 0.9), 4.0)
			draw_line(at + Vector2(-16, -16), at + Vector2(16, 16), Color(MARK_COLOR, 0.8), 3.0)
			draw_line(at + Vector2(16, -16), at + Vector2(-16, 16), Color(MARK_COLOR, 0.8), 3.0)
		# afterimage line between the landings, fading
		for i in range(1, _trail.size()):
			draw_line(to_local(_trail[i - 1]), to_local(_trail[i]), Color(MARK_COLOR, 0.5), 3.0)

func _init() -> void:
	display_name = "Shadow Strikes"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 18
	sfx = "dash"
	cast_pitch = 0.8

## Targeted ult: it needs a foe to lock onto. With nobody there the press does nothing and the charge is kept
## ("Nobody in reach"), for players and bots alike.
func can_cast(caster: Node2D, aim_pos: Vector2) -> bool:
	return worth_casting(caster, aim_pos)

## Is there a foe to lock onto?
func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	return not pick(caster.global_position, aim_pos, Spell.foes(caster)).is_empty()

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var order := plan(pick(caster.global_position, aim_pos, Spell.foes(caster)))
	if order.is_empty():
		return cooldown
	caster.phase(MARK + order.size() * GAP + 0.15)   # untargetable for the whole dance
	var d := Dance.new()
	d.caster = caster
	d.order = order
	d.dmg = damage
	caster.get_tree().current_scene.add_child(d)
	return cooldown
