class_name EbbAndFlow extends Spell
## Tidecaller ult: SPOKES lines of water burst OUT of his body to LENGTH (damage + push outward), hang a moment, then
## rush back IN along lines turned half a gap (damage + a pull to his feet), so standing between the outgoing lines
## only dodges half of it. He takes Player.BRACE_MULT damage while it plays. Charged 2x by damage taken
## (Hero.ult_taken_mult). The lines follow him. Runs on every peer; damage lands on each victim's own peer.

const SPOKES := 6
const LENGTH := 300.0
const WIDTH := 64.0
const OUT_TIME := 0.3
const HOLD := 0.3
const IN_TIME := 0.35
const OUT_DMG := 18
const IN_DMG := 14
const OUT_SHOVE := 520.0
const IN_STOP := 55.0        ## the pull drops a foe about this far from him
const COLOR := Color(0.15, 0.85, 0.85)   ## the hero's signature colour (Hero.basic_color)

static func total() -> float:
	return OUT_TIME + HOLD + IN_TIME

## Is `pos` (relative to the centre) on a spoke at `angle` within `[near, far]` along it?
static func on_spoke(off: Vector2, angle: float, near: float, far: float) -> bool:
	var d := Vector2.from_angle(angle)
	var along := off.dot(d)
	return along >= near and along <= far and absf(off.cross(d)) <= WIDTH * 0.5 + 14.0

class Tide extends Node2D:
	var caster: Node2D
	var base := 0.0
	var _age := 0.0
	var _out: Array[Node] = []
	var _in: Array[Node] = []

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down or _age >= EbbAndFlow.total():
			queue_free()
			return
		global_position = caster.global_position + Vector2(0, 8)
		var step := TAU / EbbAndFlow.SPOKES
		for e in Spell.foes(caster):
			var off: Vector2 = e.global_position - global_position
			if _age <= EbbAndFlow.OUT_TIME + 0.05 and not (e in _out):
				var reach := EbbAndFlow.LENGTH * clampf(_age / EbbAndFlow.OUT_TIME, 0.0, 1.0)
				for i in EbbAndFlow.SPOKES:
					if EbbAndFlow.on_spoke(off, base + i * step, 0.0, reach):
						_out.append(e)
						if e.take_damage(EbbAndFlow.OUT_DMG, global_position, false, caster):
							Spell.shove(e, off.normalized() * EbbAndFlow.OUT_SHOVE)
						break
			var t_in := _age - EbbAndFlow.OUT_TIME - EbbAndFlow.HOLD
			if t_in >= 0.0 and not (e in _in):
				var front := EbbAndFlow.LENGTH * (1.0 - clampf(t_in / EbbAndFlow.IN_TIME, 0.0, 1.0))
				for i in EbbAndFlow.SPOKES:
					if EbbAndFlow.on_spoke(off, base + (i + 0.5) * step, front, EbbAndFlow.LENGTH + 20.0):
						_in.append(e)
						var inward := -off.normalized()
						if e.take_damage(EbbAndFlow.IN_DMG, e.global_position - inward * 12.0, false, caster):
							var gap := maxf(off.length() - EbbAndFlow.IN_STOP, 0.0)
							Spell.shove(e, inward * sqrt(2.0 * Player.KNOCK_DECEL * gap))
						break
		queue_redraw()

	func _draw() -> void:
		var step := TAU / EbbAndFlow.SPOKES
		if _age <= EbbAndFlow.OUT_TIME + EbbAndFlow.HOLD:
			var reach := EbbAndFlow.LENGTH * clampf(_age / EbbAndFlow.OUT_TIME, 0.0, 1.0)
			var fade := 1.0 - clampf((_age - EbbAndFlow.OUT_TIME) / EbbAndFlow.HOLD, 0.0, 1.0) * 0.6
			for i in EbbAndFlow.SPOKES:
				_spoke(Vector2.from_angle(base + i * step), 0.0, reach, fade)
			for i in EbbAndFlow.SPOKES:   # where the return will come in: a faint guide
				var d := Vector2.from_angle(base + (i + 0.5) * step)
				draw_line(d * 30.0, d * EbbAndFlow.LENGTH, Color(EbbAndFlow.COLOR, 0.15), 3.0)
		else:
			var t_in := _age - EbbAndFlow.OUT_TIME - EbbAndFlow.HOLD
			var front := EbbAndFlow.LENGTH * (1.0 - clampf(t_in / EbbAndFlow.IN_TIME, 0.0, 1.0))
			for i in EbbAndFlow.SPOKES:
				_spoke(Vector2.from_angle(base + (i + 0.5) * step), front, EbbAndFlow.LENGTH, 1.0)

	func _spoke(d: Vector2, from: float, to: float, alpha: float) -> void:
		draw_line(d * from, d * to, Color(EbbAndFlow.COLOR, 0.5 * alpha), EbbAndFlow.WIDTH * 0.7)
		draw_line(d * from, d * to, Color(0.9, 0.97, 1.0, 0.8 * alpha), 4.0)
		draw_circle(d * (to if from == 0.0 else from), 12.0, Color(0.95, 1.0, 1.0, 0.9 * alpha))   # the foam at the moving end

func _init() -> void:
	display_name = "Ravaging Tide"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = OUT_DMG
	sfx = "explosion"
	cast_pitch = 0.6

func ult_lock() -> float:
	return total() + 0.6

func worth_casting(caster: Node2D, _aim_pos: Vector2) -> bool:
	for e in Spell.foes(caster):
		if e.global_position.distance_to(caster.global_position) < LENGTH * 0.75:
			return true
	return false

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var t := Tide.new()
	t.caster = caster
	t.base = aim_dir.angle()   # one line always goes where he aims
	t.position = caster.global_position + Vector2(0, 8)
	t.z_index = 4
	caster.get_parent().add_child(t)
	if caster.has_method("brace"):
		caster.brace(total())
	Sfx.play("splash", caster.global_position, 2.0, 0.7)
	return cooldown
