class_name KnightFx
## Steel and brass effects for the Knight. Ground ornament uses the arena's 2:1 projection.

const CLEAVE := "knight_cleave"
const FINISHER := "knight_finisher"
const SHIELD := "knight_shield"
const SLAM := "knight_slam"

const ART := "res://assets/isometric_projecttile/Spells/Knight/"
const AIR_EDGE := preload(ART + "CleaveAir.png")
const DISC := preload(ART + "ReboundShield.png")
const FLOOR := preload(ART + "JudgementFloor.png")
const DEBRIS := preload(ART + "JudgementDebris.png")
const GOLD := Color("#ffca78")
const STEEL := Color("#b8d9ee")
const INK := Color("#3e2920")
const GROUND_SCALE := Vector2(1.0, 0.5)

# Centres of the painted shield in CastSpell frame 4 and Idle, in native atlas pixels.
const RELEASE := [Vector2(89, 47), Vector2(85, 61), Vector2(71, 70), Vector2(50, 68),
	Vector2(37, 54), Vector2(41, 41), Vector2(55, 35), Vector2(78, 35)]
const CATCH := [Vector2(81, 65), Vector2(80, 72), Vector2(64, 73), Vector2(51, 68),
	Vector2(45, 62), Vector2(50, 53), Vector2(57, 48), Vector2(78, 54)]

static func shield_point(caster: Node2D, release: bool) -> Vector2:
	if caster is Player and caster.hero and caster.hero.id == "knight":
		var sprite: AnimatedSprite2D = caster._sprite
		var row: int = caster._dirs.find(sprite.sprite_frames)
		if row >= 0:
			var cell: Vector2 = RELEASE[row] if release else CATCH[row]
			return sprite.to_global(cell - Vector2(64, 64) + sprite.offset)
	return caster.global_position + Vector2(0, -22)

static func shield_depth(caster: Node2D) -> int:
	if caster is Player and caster.hero and caster.hero.id == "knight":
		var row: int = caster._dirs.find(caster._sprite.sprite_frames)
		if row >= 4 and row <= 6:
			return -1
	return 6

static func is_impact(kind: String) -> bool:
	return kind in [CLEAVE, FINISHER, SHIELD, SLAM]

static func victim_impact(victim: Node2D, kind: String, direction: Vector2) -> void:
	var blade := kind == CLEAVE or kind == FINISHER
	var size := 0.82 if blade else 0.64
	var path := "SteelHit.png" if blade else "ShieldHit.png"
	if kind == FINISHER:
		path = "SteelFinisher.png"
		size = 1.05
	elif kind == SLAM:
		path = "JudgementHit.png"
		size = 0.70
	var fx := SheetFrames.play_once(victim.get_parent(), Vector2.ZERO, ART + path, 8, 34.0, size)
	fx.global_position = victim.global_position + Vector2(clampf(-direction.x * 5.0, -5.0, 5.0), -26)
	fx.z_index = 18
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.flip_h = direction.x < 0.0
	if blade:
		fx.rotation = direction.y * (0.30 if fx.flip_h else -0.30)

static func shield_glint(caster: Node2D, at: Vector2, returning: bool) -> void:
	var fx := SheetFrames.play_once(caster.get_parent(), Vector2.ZERO, ART + "ShieldHit.png", 8, 46.0, 0.27)
	fx.global_position = at
	fx.z_index = shield_depth(caster)
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if returning:
		fx.modulate = STEEL

static func draw_disc(canvas: CanvasItem, at: Vector2, direction: Vector2, spin: float) -> void:
	var cell := Vector2(72, 72)
	var row := SheetFrames.facing_index(direction)
	var frame := posmod(floori(spin), 12)
	canvas.draw_texture_rect_region(DISC, Rect2(at - cell * 0.42, cell * 0.84),
		Rect2(Vector2(frame, row) * cell, cell))

## The release frame is the first strong blade extension in each painted sheet.
static func cleave_frame(pose: StringName, age: float, windup: float, recovery_end: float) -> int:
	var contact := 9 if pose == &"cast_finisher" else 8
	if age < windup:
		return mini(floori(age / windup * contact), contact - 1)
	var release_hold := 0.04
	var follow := clampf((age - windup - release_hold) / maxf(recovery_end - windup - release_hold, 0.01), 0.0, 1.0)
	return mini(contact + floori(follow * (15 - contact)), 14)

static func draw_cleave(canvas: CanvasItem, direction: Vector2, angle: float, reach: float,
		age: float, windup: float, finisher: bool, reverse: bool) -> void:
	var base := direction.angle() - angle * 0.5
	if age < windup:
		return
	var elapsed := age - windup
	var fade := 1.0 - smoothstep(0.018, 0.14, elapsed)
	if fade <= 0.0:
		return
	var head := lerpf(0.57, 1.0, smoothstep(0.0, 0.09, elapsed))
	var tail := maxf(0.0, head - (0.72 if finisher else 0.55))
	var start := 1.0 - head if reverse else tail
	var swept_angle := (head - tail) * angle
	var trail_start := base + start * angle
	_draw_edge(canvas, trail_start, swept_angle, reach * 0.74, 28.0 if finisher else 22.0,
		Color(1, 1, 1, fade))

static func _draw_edge(canvas: CanvasItem, base: float, angle: float, reach: float, width: float, tint: Color) -> void:
	var colors := PackedColorArray([tint])
	var inner := reach - width
	var offset := Vector2(0, -24)
	const STEPS := 24
	for i in STEPS:
		var u0 := float(i) / STEPS
		var u1 := float(i + 1) / STEPS
		var a := Vector2.from_angle(base + angle * u0)
		var b := Vector2.from_angle(base + angle * u1)
		canvas.draw_primitive(PackedVector2Array([a * reach + offset, b * reach + offset, b * inner + offset]), colors,
			PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1)]), AIR_EDGE)
		canvas.draw_primitive(PackedVector2Array([a * reach + offset, b * inner + offset, a * inner + offset]), colors,
			PackedVector2Array([Vector2(u0, 0), Vector2(u1, 1), Vector2(u0, 1)]), AIR_EDGE)

static func draw_slam(canvas: CanvasItem, texture: Texture2D, radius: float, progress: float) -> void:
	var cell := Vector2(256, 256)
	var frame := clampi(floori(progress * 8.0), 0, 7)
	var size := cell * (radius / 112.0)
	canvas.draw_texture_rect_region(texture, Rect2(-size * 0.5, size), Rect2(Vector2(frame, 0) * cell, cell))

static func draw_jump_shadow(canvas: CanvasItem, height: float) -> void:
	canvas.draw_set_transform(Vector2(3, 15), 0.0, GROUND_SCALE)
	canvas.draw_circle(Vector2.ZERO, lerpf(22.0, 16.0, height), Color(0.08, 0.06, 0.05, 0.26))
	canvas.draw_circle(Vector2.ZERO, lerpf(16.0, 12.0, height), Color(0.05, 0.04, 0.03, 0.26))
	canvas.draw_set_transform(Vector2.ZERO)
