class_name PacketLoss extends Spell
## Six Seven basic: a packet that flies out a short way, FREEZES mid-air for BUFFER seconds (a spinning "loading" ring),
## then reconnects as a homing missile at the foe closest to it (the locked foe if it is in SEEK). A dash still shakes
## the homing off, like any locked shot. It can also hit a foe directly on the way out. Only flinches (a basic).
## Runs on every peer; the hit lands on the victim's own peer.

const OUT_SPEED := 260.0       ## a sluggish crawl out of the gate (200 ping), then it stalls
const OUT_TIME := 0.4         ## ~105 px out before it lags
const BUFFER := 0.35
const SEEK := 450.0           ## after the freeze it hunts the closest foe within this of itself
const HOME_SPEED := 900.0      ## and then it all arrives at once
const HOME_LIFE := 1.0
const RADIUS := 18.0
const PICK_RADIUS := 150.0
const COLOR := Color(0.85, 0.9, 1.0)   ## the hero's signature colour (Hero.basic_color)

var range_px := 450.0

## The foe a reconnecting packet at `at` goes for: `lock` if it is still in SEEK, else the closest foe in SEEK, or null.
static func seek(caster: Node2D, at: Vector2, lock_: Node2D) -> Node2D:
	if is_instance_valid(lock_) and not lock_.down and lock_.global_position.distance_to(at) <= SEEK:
		return lock_
	var best: Node2D = null
	var best_d := SEEK
	for e in Spell.foes(caster):
		if e.has_method("hidden_from") and e.hidden_from(caster):
			continue
		var d := e.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = e
	return best

class Packet extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var velocity := Vector2.ZERO   ## for bots to dodge (group dodgeables)

	func _ready() -> void:
		add_to_group("dodgeables")
	var dmg := 9
	var lock: Node2D
	var color := COLOR
	var _age := 0.0
	var _target: Node2D
	var _homing := false

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster):
			queue_free()
			return
		if _age < OUT_TIME:
			global_position += dir * OUT_SPEED * delta
			velocity = dir * OUT_SPEED
		elif _age < OUT_TIME + BUFFER:
			velocity = Vector2.ZERO   # lagging: frozen mid-air
		else:
			if not _homing:
				_homing = true
				_target = PacketLoss.seek(caster, global_position, lock)
				Sfx.play("shoot", global_position, -6.0, 1.7)
			if is_instance_valid(_target) and not _target.down and not (_target.has_method("dodging") and _target.dodging()):
				dir = (_target.global_position + Vector2(0, -4) - global_position).normalized()
			else:
				_target = null
			global_position += dir * HOME_SPEED * delta
			velocity = dir * HOME_SPEED
			if _age >= OUT_TIME + BUFFER + HOME_LIFE:
				queue_free()
				return
		for e in Spell.foes(caster):
			if e.global_position.distance_to(global_position) > RADIUS + 14.0:
				continue
			Player.basic_hit = true
			e.take_damage(dmg, global_position - dir * 10.0, false, caster)
			Player.basic_hit = false
			SheetFrames.play_once(get_parent(), global_position, SheetFrames.FX + "AoE/IceAoE/", 0, 40.0, 0.15).modulate = color
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var buffering := _age >= OUT_TIME and _age < OUT_TIME + BUFFER
		if buffering:   # the loading ring
			var spin := _age * 14.0
			draw_arc(Vector2.ZERO, 14.0, spin, spin + PI * 1.4, 16, Color(color, 0.9), 3.0)
			var font := ThemeDB.fallback_font
			draw_string_outline(font, Vector2(-30, -20), "200ms", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, 3, Color.BLACK)
			draw_string(font, Vector2(-30, -20), "200ms", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(1.0, 0.45, 0.45))
		if _homing:
			draw_line(Vector2.ZERO, -dir * 26.0, Color(color, 0.4), 6.0)
		var jitter := Vector2(randf_range(-2, 2), 0) if buffering else Vector2.ZERO   # a little glitch (visual only)
		draw_rect(Rect2(Vector2(-6, -6) + jitter, Vector2(12, 12)), color)
		draw_rect(Rect2(Vector2(-6, -6) + jitter, Vector2(12, 12)), Color(0.1, 0.1, 0.15), false, 2.0)
		draw_rect(Rect2(Vector2(-2, -2) + jitter, Vector2(4, 4)), Color(1.0, 0.45, 0.75))

func _init() -> void:
	display_name = "Packet Loss"
	cooldown = 0.6
	damage = 9
	sfx = "shoot"
	cast_pitch = 1.5

func reach() -> float:
	return range_px

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.5, range_px)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var p := Packet.new()
	p.caster = caster
	p.dir = aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	p.dmg = damage
	p.lock = lock if is_instance_valid(lock) else null
	if "hero" in caster and caster.hero:
		p.color = caster.hero.basic_color
	p.position = caster.global_position + Vector2(0, 2) + p.dir * 26.0
	p.z_index = 6
	caster.get_parent().add_child(p)
	return cooldown
