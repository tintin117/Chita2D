class_name HammerThrow extends Spell
## Paladin basic (Dawnbreaker): throw the hammer forward a short way; it hangs a moment at the end, then flies back to
## the Paladin wherever he is now. Two damage windows: everyone it passes on the way OUT is hit once, and everyone it
## passes on the way BACK is hit once more, so a foe standing in its lane takes it twice. Holy Might still applies
## (+ `might` x current HP, set at the throw), and the Paladin's lifesteal heals on every hit.
## Slower than a swing (a bit of cooldown), but it reaches, and walking can drag the return through a crowd.

const OUT_SPEED := 760.0
const BACK_SPEED := 900.0
const HANG := 0.12            ## seconds it hangs at the far end
const RADIUS := 30.0
const PICK_RADIUS := 150.0
const ART_SCALE := 0.92
const HAMMER := preload("res://assets/isometric_projecttile/Spells/Paladin/Hammer.png")
const SPARK_PATH := "res://assets/isometric_projecttile/Spells/Paladin/HolySpark.png"
const SPARK := preload(SPARK_PATH)

var range_px := 260.0
var might := 0.0

## Seconds from the throw until the hammer starts back (out + hang).
static func turn_time(range_px_: float) -> float:
	return range_px_ / OUT_SPEED + HANG

## Where the hammer is (relative to the throw point) at `t` seconds while it is going out or hanging.
static func out_offset(dir: Vector2, range_px_: float, t: float) -> Vector2:
	return dir.normalized() * minf(t * OUT_SPEED, range_px_)

class Hammer extends Node2D:
	var caster: Node2D
	var dir := Vector2.RIGHT
	var dmg := 12
	var range_px := 260.0
	var _start := Vector2.ZERO
	var _age := 0.0
	var _back := false
	var _hit_out: Array[Node] = []
	var _hit_back: Array[Node] = []
	var _spin := 0.0

	func _ready() -> void:
		z_index = 6
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_start = global_position

	func _physics_process(delta: float) -> void:
		_age += delta
		_spin += delta * 22.0
		if not is_instance_valid(caster):
			queue_free()
			return
		if not _back:
			global_position = _start + HammerThrow.out_offset(dir, range_px, _age)
			if _age >= HammerThrow.turn_time(range_px):
				_back = true
		else:
			var home: Vector2 = caster.global_position + Vector2(0, -6)
			var to := home - global_position
			if to.length() <= BACK_SPEED * delta + 8.0:
				queue_free()   # caught
				return
			global_position += to.normalized() * BACK_SPEED * delta
		_hit(_hit_back if _back else _hit_out)
		queue_redraw()

	## One hit per foe per pass (out, then back).
	func _hit(done: Array[Node]) -> void:
		for e in Spell.foes(caster):
			if e in done or e.global_position.distance_to(global_position) > RADIUS + 16.0:
				continue
			done.append(e)
			Player.basic_hit = true
			e.take_damage(dmg, caster.global_position if not _back else global_position + dir * -10.0, false, caster)
			Player.basic_hit = false

	func _draw() -> void:
		var radiance := 0.22 + 0.15 * (0.5 + 0.5 * sin(_spin))
		var flare_size := SPARK.get_size() * ART_SCALE
		draw_texture_rect(SPARK, Rect2(-flare_size * 0.5, flare_size), false, Color(1.0, 1.0, 1.0, radiance))
		draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE * ART_SCALE)
		draw_texture(HAMMER, -HAMMER.get_size() * 0.5)

func _init() -> void:
	display_name = "Hammer"
	cooldown = 0.85
	damage = 12
	sfx = "swing"
	cast_pitch = 0.8

func reach() -> float:
	return range_px

func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, PICK_RADIUS, 0.45, range_px + 20.0)

func aim(caster: Node2D, dir: Vector2) -> Vector2:
	return Spell.assist_dir(caster, dir, 0.45, range_px + 20.0)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var d := aim_dir.normalized() if aim_dir != Vector2.ZERO else Vector2.RIGHT
	var h := Hammer.new()
	h.caster = caster
	h.dir = d
	h.range_px = range_px
	h.dmg = damage + (roundi(caster.hp * might) if "hp" in caster else 0)   # Holy Might: a healthy Paladin throws harder
	h.position = caster.global_position + Vector2(0, -6) + d * 24.0
	caster.get_parent().add_child(h)
	return cooldown
