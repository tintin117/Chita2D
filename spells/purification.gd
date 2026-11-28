class_name Purification extends Spell
## Paladin right click: a wave sweeps outward, then back toward him. Each pass can hit a foe once.

const RADIUS := 150.0
const HEAL := 30
const PASS_TIME := 0.38
const FADE_TIME := 0.14
const GROUND_SQUASH := 0.58
const HIT_MARGIN := 14.0
const BURST := SheetFrames.FX + "Spells/Paladin/Purification/"
const HEAL_ART := SheetFrames.FX + "Spells/Paladin/Heal.png"
const SPARK_ART := SheetFrames.FX + "Spells/Paladin/HolySpark.png"
const SPARK := preload(SPARK_ART)
const ART_RADIUS := 50.0
const SHIELD_FLASH_TIME := 0.10
## Center of the raised shield in Paladin's CastSpell release, in the native 128 px cells.
const CAST_SHIELD: Array[Vector2] = [Vector2(81, 44), Vector2(83, 61), Vector2(72, 67), Vector2(56, 65),
	Vector2(51, 56), Vector2(53, 44), Vector2(56, 36), Vector2(71, 37)]

static func ground_distance(at: Vector2, point: Vector2) -> float:
	var offset := point - at
	return Vector2(offset.x, offset.y / GROUND_SQUASH).length()

func _init() -> void:
	display_name = "Purify"
	cooldown = 8.0
	damage = HEAL
	sfx = "crown"
	cast_pitch = 1.4

func cast(caster: Node2D, _aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var pulse := Pulse.new()
	pulse.caster = caster
	pulse.total = damage
	pulse.position = Vector2(0, 14)
	caster.add_child(pulse)
	return cooldown

class Pulse extends Node2D:
	var caster: Node2D
	var total := HEAL
	var _rings: SpriteFrames
	var _pass := 0
	var _age := 0.0
	var _radius := 0.0
	var _hit: Dictionary[Node2D, bool] = {}

	func _ready() -> void:
		z_index = -1
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_rings = SheetFrames.seq(BURST, 20.0, false)

	func _physics_process(delta: float) -> void:
		if caster.down:
			queue_free()
			return
		var remaining := delta
		while remaining > 0.0 and _pass < 2:
			var step := minf(remaining, PASS_TIME - _age)
			var last_radius := _radius
			var last_age := _age
			_age += step
			remaining -= step
			if _pass == 0 and last_age < SHIELD_FLASH_TIME and _age >= SHIELD_FLASH_TIME:
				_shield_flash()
			var progress := _age / PASS_TIME
			_radius = RADIUS * (progress if _pass == 0 else 1.0 - progress)
			@warning_ignore("integer_division")
			var half := total / 2
			var amount := half if _pass == 0 else total - half
			_sweep(last_radius, _radius, amount)
			if _age >= PASS_TIME:
				_settle(amount)
				_hit.clear()
				_pass += 1
				_age = 0.0
		if _pass == 2:
			_age += remaining
			if _age >= FADE_TIME:
				queue_free()
		queue_redraw()

	func _shield_flash() -> void:
		var at := Vector2(0, -38)
		if caster is Player and caster.hero.id == "paladin":
			var body: AnimatedSprite2D = caster._sprite
			var row: int = caster._dirs.find(body.sprite_frames)
			if row >= 0:
				var offset := CAST_SHIELD[row] - Vector2(64, 64) + body.offset
				at = body.position + (offset * body.scale).rotated(body.rotation)
		_flash(caster, SPARK_ART, at, 1.35, 0.18, -6.0)

	func _sweep(start: float, finish: float, amount: int) -> void:
		var at := caster.global_position
		var near_edge := minf(start, finish) - HIT_MARGIN
		var far_edge := maxf(start, finish) + HIT_MARGIN
		for foe in Spell.foes(caster):
			if _hit.has(foe):
				continue
			var distance := Purification.ground_distance(at, foe.global_position)
			if distance < near_edge or distance > far_edge:
				continue
			_hit[foe] = true
			if foe.take_damage(amount, at, false, caster, Player.PURIFY_IMPACT):
				_flash(foe, SPARK_ART, Vector2(0, -32), 1.6, 0.3, -9.0)

	func _settle(amount: int) -> void:
		_rising_sparks()
		if not caster.owns() or not caster.has_method("heal"):
			return
		var before: int = caster.hp
		caster.heal(amount)
		var recovered: int = caster.hp - before
		if recovered <= 0:
			return
		_flash(caster, HEAL_ART, Vector2(0, -62), 2.0, 0.46, -24.0)
		caster.float_text("+%d" % recovered, Color(0.5, 1.0, 0.5), 20)
		if caster.online:
			caster._net_hp.rpc(caster.hp)

	func _draw() -> void:
		if _pass == 2:
			var fade := clampf(1.0 - _age / FADE_TIME, 0.0, 1.0)
			_draw_glint(Vector2.ZERO, 12.0 + 14.0 * fade, Color(1.0, 0.92, 0.75, fade))
			return
		var progress := clampf(_age / PASS_TIME, 0.0, 1.0)
		var art := _rings.get_frame_texture("fx", roundi(progress * 8.0))
		var outward := _pass == 0
		var direction := 1.0 if outward else -1.0
		var alpha := smoothstep(8.0, 34.0, _radius)
		var rim := Color(1.16, 1.04, 0.87) if outward else Color(1.08, 1.06, 1.14)
		# The afterimage always trails the damaging edge, so its placement reverses on the way back.
		var trail_radius := clampf(_radius - direction * 19.0, 0.0, RADIUS)
		_draw_ring(art, trail_radius, Color(rim, 0.28 * alpha))
		_draw_ring(art, _radius, Color(rim, alpha))
		_draw_streaks(progress, direction, alpha)

	func _draw_ring(art: Texture2D, radius: float, tint: Color) -> void:
		if radius <= 0.0 or tint.a <= 0.0:
			return
		var extent := art.get_size() * (radius / ART_RADIUS) * Vector2(1, GROUND_SQUASH)
		draw_texture_rect(art, Rect2(-extent * 0.5, extent), false, tint)

	func _draw_streaks(progress: float, direction: float, alpha: float) -> void:
		var spark_tint := Color(1.0, 0.88, 0.57, alpha) if direction > 0.0 else Color(1.0, 0.96, 0.85, alpha)
		for i in 12:
			var angle := TAU * i / 12.0 + (0.23 if i % 2 else 0.0) - 0.30 * _radius / RADIUS
			var axis := Vector2.from_angle(angle) * Vector2(1, GROUND_SQUASH)
			var head := (axis * _radius).round()
			var length := 9.0 + 12.0 * (0.5 + 0.5 * sin(TAU * progress + i * 2.3))
			var tail := (axis * clampf(_radius - direction * length, 0.0, RADIUS)).round()
			draw_line(tail, head, Color(0.98, 0.54, 0.20, 0.54 * alpha), 2.0)
			draw_line(tail.lerp(head, 0.58), head, spark_tint, 1.0)
			if i % 3 == 0:
				_draw_glint(head, 11.0, spark_tint)

	func _draw_glint(at: Vector2, size: float, tint: Color) -> void:
		var extent := Vector2.ONE * size
		draw_texture_rect(SPARK, Rect2(at - extent * 0.5, extent), false, tint)

	func _flash(target: Node2D, art: String, at: Vector2, size: float, life: float, rise: float) -> void:
		var flash := SheetFrames.play_once(target, at, art, 1, 1.0 / life, size)
		flash.z_index = 8
		flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var tween := flash.create_tween().set_parallel(true)
		tween.tween_property(flash, "position:y", at.y + rise, life)
		tween.tween_property(flash, "modulate:a", 0.0, life * 0.75).set_delay(life * 0.25)

	func _rising_sparks() -> void:
		var sparks := CPUParticles2D.new()
		sparks.emitting = false
		sparks.position = position
		sparks.z_index = 5
		sparks.texture = SPARK
		sparks.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sparks.local_coords = true
		sparks.one_shot = true
		sparks.amount = 8
		sparks.lifetime = 0.4
		sparks.explosiveness = 0.9
		sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		sparks.emission_rect_extents = Vector2(28.0, 14.0)
		sparks.direction = Vector2.UP
		sparks.spread = 42.0
		sparks.gravity = Vector2(0.0, 90.0)
		sparks.initial_velocity_min = 120.0
		sparks.initial_velocity_max = 190.0
		sparks.scale_amount_min = 0.32
		sparks.scale_amount_max = 0.68
		var fade := Gradient.new()
		fade.set_color(0, Color.WHITE)
		fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		sparks.color_ramp = fade
		caster.add_child(sparks)
		sparks.finished.connect(sparks.queue_free)
		sparks.emitting = true
