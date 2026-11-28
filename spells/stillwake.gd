class_name Stillwake extends Spell
## Chaos Lord ult: stop time in a disk projected onto the arena floor at the cursor. Everyone inside but him (allies too) is held in stopped time
## for as long as the field lasts, anyone who walks in is caught for what is left, and he moves and swings freely in it.
## Loaded Dice sets the length: BASE x roll (0.4 .. 2.8 s). The hold ignores the stun immunity (it is the ult) and
## starts it when time runs again (Player.chrono_hold). Runs on every peer.

const MAX_RANGE := 450.0
const RADIUS := 180.0
const BASE := 0.8
const RELEASE_TIME := 0.22
const FLOOR_ART := preload(ChaosFx.ART + "SphereFloor.png")
const GLASS_ART := preload(ChaosFx.ART + "SphereGlass.png")
const STASIS_ART := preload(ChaosFx.ART + "Stasis.png")
const ART_CELL := Vector2(256, 256)
const ART_RADIUS := 112.0
const ART_SCALE := RADIUS / ART_RADIUS

static func spot(from: Vector2, aim_pos: Vector2) -> Vector2:
	return from + (aim_pos - from).limit_length(MAX_RANGE)

class Field extends Node2D:
	var caster: Node2D
	var dur := BASE
	var _age := 0.0
	var _floor: Node2D
	var _held: Array[Node2D] = []

	func _ready() -> void:
		add_to_group("zones")
		_floor = Node2D.new()
		_floor.z_as_relative = false
		_floor.z_index = -1
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_floor.draw.connect(_draw_floor)
		add_child(_floor)

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or _age >= dur + RELEASE_TIME:
			queue_free()
			return
		if _age < dur:
			for e in Spell.foes(caster):
				if ChaosFx.ground_distance(e.global_position - global_position) <= RADIUS and e.has_method("chrono_hold"):
					e.chrono_hold(dur - _age)
					if e.has_method("time_stopped") and e.time_stopped() and e not in _held:
						_held.append(e)
		elif is_in_group("zones"):
			remove_from_group("zones")
		queue_redraw()
		_floor.queue_redraw()

	func bot_avoid(pos: Vector2) -> Vector2:
		var off := pos - global_position
		return off.normalized() if _age < dur and ChaosFx.ground_distance(off) < RADIUS + 40.0 and off.length() > 1.0 else Vector2.ZERO

	func _draw_floor() -> void:
		var fade := 1.0 - smoothstep(dur, dur + RELEASE_TIME, _age)
		var excess := _age - dur
		var time_left := clampf(-excess / dur, 0.0, 1.0)
		var extent := ART_CELL * ART_SCALE
		_floor.draw_texture_rect(FLOOR_ART, Rect2(-extent * 0.5, extent), false, Color(1, 1, 1, fade))
		_draw_glass(_floor, 0, fade)
		if time_left > 0.0:
			ChaosFx.draw_ribbon(_floor, -PI / 2.0, TAU * time_left, RADIUS - 11.0, 12.0, 0.0,
				Color(1.04, 1.0, 1.15, 0.93))
			var hand := -PI / 2.0 + TAU * time_left
			var point := Vector2.from_angle(hand) * ChaosFx.GROUND_SCALE * (RADIUS - 18.0)
			var head := Vector2(13, 13)
			_floor.draw_texture_rect_region(ChaosFx.BLAST_IMPACT, Rect2(point - head * 0.5, head),
				Rect2(28, 27, 40, 40), Color(1.0, 1.0, 1.0, 0.91))

	func _draw_glass(canvas: CanvasItem, layer: int, fade: float) -> void:
		var opening := smoothstep(0.0, 0.15, _age)
		var scale := ART_SCALE * Vector2(1.0 + (1.0 - fade) * 0.08, lerpf(0.52, 1.0, opening) + (1.0 - fade) * 0.14)
		var extent := ART_CELL * scale
		var tone := Color(1.10, 1.01, 1.14, fade)
		canvas.draw_texture_rect_region(GLASS_ART, Rect2(-extent * 0.5, extent),
			Rect2(Vector2(0.0, ART_CELL.y * layer), ART_CELL), tone)

	func _draw() -> void:
		var fade := 1.0 - smoothstep(dur, dur + RELEASE_TIME, _age)
		_draw_glass(self, 1, fade)
		for fighter in _held:
			if is_instance_valid(fighter) and fighter.time_stopped() and not fighter.down:
				var at := to_local(fighter.global_position) + Vector2(0, -27)
				var extent := STASIS_ART.get_size() * 1.08
				draw_texture_rect(STASIS_ART, Rect2(at - extent * 0.5, extent), false, Color(1, 1, 1, fade))

func _init() -> void:
	display_name = "Time Sphere"
	cooldown = 0.6     # the charge is the real gate; this only covers the cast lock
	damage = 0
	sfx = "crown"
	cast_pitch = 0.5

func ult_lock() -> float:
	return BASE * Chaos.HI + 0.5

func worth_casting(caster: Node2D, aim_pos: Vector2) -> bool:
	var at := spot(caster.global_position, aim_pos)
	for e in Spell.foes(caster):
		if ChaosFx.ground_distance(e.global_position - at) <= RADIUS * 0.8:
			return true
	return false

func cast(caster: Node2D, _aim_dir: Vector2, aim_pos: Vector2) -> float:
	var f := Field.new()
	f.caster = caster
	f.dur = BASE * Chaos.roll(caster)
	f.z_index = 3
	caster.get_parent().add_child(f)
	f.global_position = spot(caster.global_position, aim_pos)
	return cooldown
