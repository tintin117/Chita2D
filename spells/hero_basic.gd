class_name HeroBasic extends Spell
## Fast 3-cast combo basic. mode "arc": instant cone sweep (melee). mode "bolt": projectile(s) (ranged).
## The 3rd cast is the finisher: bigger damage, and extra bolts for spread heroes. Built by Hero.make_basic().

@export var mode := "bolt"
@export var radius := 115.0          ## arc reach
@export var arc_angle := 1.9
@export var lunge_speed := 0.0       ## melee: step forward with each sweep
@export var bolt_speed := 640.0
@export var bolt_radius := 10.0
@export var bolt_life := 0.6
@export var bolt_pierce := 0
@export var finisher_spread := 1     ## extra bolt pairs on the finisher
@export var finisher_mult := 1.0
@export var finisher_cd_mult := 2.14 ## 0.28s -> 0.6s recovery after the finisher

var _combo := 0
var _last_msec := 0

class Sweep extends Node2D:
	var dir := Vector2.RIGHT
	var reach := 115.0
	var angle := 1.9
	var _age := 0.0

	func _process(delta: float) -> void:
		_age += delta
		if _age >= 0.22:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var t := _age / 0.22
		var pts := PackedVector2Array([Vector2.ZERO])
		var base := dir.angle() - angle / 2.0
		for i in 13:
			pts.append(Vector2.from_angle(base + angle * i / 12.0) * reach * (0.6 + 0.4 * minf(t * 3.0, 1.0)))
		draw_colored_polygon(pts, Color(1.0, 0.5, 0.15, 0.55 * (1.0 - t)))
		draw_polyline(pts.slice(1), Color(1, 1, 1, 0.8 * (1.0 - t)), 3.0)

func cast(caster: Node2D, aim_dir: Vector2, _aim_pos: Vector2) -> float:
	var now := Time.get_ticks_msec()
	if now - _last_msec > 900:
		_combo = 0
	_last_msec = now
	var finisher := _combo == 2
	_combo = 0 if finisher else _combo + 1
	var dmg := int(damage * (finisher_mult if finisher else 1.0))
	var scene := caster.get_tree().current_scene
	if mode == "arc":
		var origin := caster.global_position + Vector2(0, 8)
		for e: Node2D in caster.get_tree().get_nodes_in_group("enemies"):
			var off := e.global_position - origin
			if off.length() <= radius + 16.0 and (off.length() < 24.0 or absf(aim_dir.angle_to(off)) <= arc_angle / 2.0):
				e.take_damage(dmg, origin)
				caster.on_dealt_damage(dmg)
		var fx := Sweep.new()
		fx.position = origin
		fx.dir = aim_dir
		fx.reach = radius
		fx.angle = arc_angle
		fx.z_index = 5
		scene.add_child(fx)
		if lunge_speed > 0.0:
			caster.lunge(aim_dir, 0.12 if finisher else 0.08, lunge_speed * (2.0 if finisher else 1.0))  # finisher steps in harder
	else:
		var extra := finisher_spread if finisher else 0
		for i in extra * 2 + 1:
			var dir := aim_dir.rotated((i - extra) * 0.22)
			var p := Projectile.new().setup(caster.global_position + dir * 28.0 + Vector2(0, 8), dir * bolt_speed, dmg, true, caster)
			p.radius = bolt_radius
			p.life = bolt_life
			p.pierce = bolt_pierce
			scene.add_child(p)
	return cooldown * (finisher_cd_mult if finisher else 1.0)
