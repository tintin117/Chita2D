class_name HeroBasic extends Spell
## Fast 3-cast combo basic. mode "arc": instant cone sweep (melee). mode "bolt": projectile(s) (ranged).
## The 3rd cast is the finisher: bigger damage, and extra bolts for spread heroes. Built by Hero.make_basic().

const FINISHER_SHOVE := 250.0   ## extra launch on the melee finisher (~240 px slide with its own knockback)

@export var mode := "bolt"
@export var radius := 115.0          ## arc reach
@export var arc_angle := 2.2
@export var windup := 0.1             ## melee: telegraph before the sweep turns live
@export var active := 0.12            ## melee: how long the sweep keeps hitting (each foe once)
@export var assist_angle := 0.35      ## melee/bolt aim assist: snap toward the nearest foe within this angle
@export var lunge_speed := 0.0       ## melee: step forward with each sweep
@export var back_mult := 1.0         ## melee: damage multiplier on a victim that is facing away from the sweep
@export var bolt_speed := 640.0
@export var bolt_radius := 16.0
@export var bolt_life := 0.6
@export var bolt_pierce := 0
@export var finisher_spread := 1     ## extra bolt pairs on the finisher
@export var finisher_mult := 1.0
@export var finisher_cd_mult := 1.5  ## longer recovery after the finisher

var _combo := 0
var _last_msec := 0

class Sweep extends Node2D:
	## Telegraphs for `windup`, then hits every foe in the cone once during `active` (so stepping aside late still gets hit).
	var caster: Node2D
	var dir := Vector2.RIGHT
	var reach := 115.0
	var angle := 2.2
	var windup := 0.1
	var active := 0.12
	var dmg := 12
	var finisher := false
	var lunge_speed := 0.0
	var back_mult := 1.0
	var _age := 0.0
	var _lunged := false
	var _landed := false
	var _hit: Array[Node] = []

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		position = caster.global_position + Vector2(0, 8)
		if _age < windup:
			return
		if not _lunged:
			_lunged = true
			if lunge_speed > 0.0:
				caster.lunge(dir, 0.12 if finisher else 0.08, lunge_speed * (2.0 if finisher else 1.0))  # finisher steps in harder
		for e in Spell.foes(caster):
			var off := e.global_position - position
			if e in _hit or off.length() > reach + 20.0:
				continue
			if off.length() < 24.0 or absf(dir.angle_to(off)) <= angle / 2.0:
				_hit.append(e)
				var hit := dmg
				if back_mult > 1.0 and Sweep.from_behind(e, position):
					hit = roundi(dmg * back_mult)
					if e.has_method("float_text"):
						e.float_text("BACKSTAB", Color(1.0, 0.45, 0.9), 22)
				e.take_damage(hit, position, false, caster)
				if finisher:
					Spell.shove(e, dir * FINISHER_SHOVE)   # the 3rd hit launches; hits 1-2 only flinch, so the combo keeps landing
				if not _landed:
					_landed = true
					Sfx.play("hit_big" if finisher else "hit", position)

	## True when `pos` is behind the victim: it is looking away from the attacker.
	static func from_behind(victim: Node2D, pos: Vector2) -> bool:
		if not ("aim_dir" in victim):
			return false
		return victim.aim_dir.dot((pos - victim.global_position).normalized()) < -0.1

	func _process(_delta: float) -> void:
		if _age >= windup + active + 0.08:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var base := dir.angle() - angle / 2.0
		var pts := PackedVector2Array([Vector2.ZERO])
		if _age < windup:   # telegraph: faint outline growing toward full reach
			var w := _age / windup
			for i in 13:
				pts.append(Vector2.from_angle(base + angle * i / 12.0) * reach * (0.5 + 0.5 * w))
			draw_polyline(pts.slice(1), Color(1, 0.8, 0.5, 0.25 + 0.4 * w), 2.0)
			return
		var t := clampf((_age - windup) / (active + 0.08), 0.0, 1.0)
		for i in 13:
			pts.append(Vector2.from_angle(base + angle * i / 12.0) * reach)
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
		var fx := Sweep.new()
		fx.caster = caster
		fx.dir = Spell.assist_dir(caster, aim_dir, assist_angle, radius + 40.0)
		fx.reach = radius
		fx.angle = arc_angle
		fx.windup = windup
		fx.active = active
		fx.dmg = dmg
		fx.finisher = finisher
		fx.lunge_speed = lunge_speed
		fx.back_mult = back_mult
		fx.z_index = 5
		fx.position = caster.global_position + Vector2(0, 8)
		scene.add_child(fx)
	else:
		var extra := finisher_spread if finisher else 0
		aim_dir = Spell.assist_dir(caster, aim_dir, assist_angle * 0.75, bolt_speed * bolt_life)
		for i in extra * 2 + 1:
			var dir := aim_dir.rotated((i - extra) * 0.22)
			var p := Projectile.new().setup(caster.global_position + dir * 28.0 + Vector2(0, 8), dir * bolt_speed, dmg, true, caster)
			p.radius = bolt_radius
			p.life = bolt_life
			p.pierce = bolt_pierce
			scene.add_child(p)
	return cooldown * (finisher_cd_mult if finisher else 1.0)
