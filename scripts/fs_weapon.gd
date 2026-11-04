class_name FsWeapon extends Spell
## Friendslop pickup weapons. One is held per button slot (0 = LMB, 1 = RMB) and replaces the hero's basic / skill while it
## lasts: until `uses` run out or `time` seconds pass. Built by make(); the Player casts it through the same _net_cast
## path as any spell, so every peer spawns identical projectiles / blasts (anything random comes from the caster's seeded rng).

## Per weapon: name, slot, uses, time (s), cd (s), dmg; the rest feeds the bots (reach band, needs a clear line, projectile speed to lead).
const DEFS := {
	"slingshot": {"name": "Slingshot", "slot": 0, "uses": 14, "time": 15.0, "cd": 0.32, "dmg": 7, "min": 0.0, "max": 400.0, "los": true, "speed": 720.0, "sfx": "shoot"},
	"firecracker": {"name": "Firecracker", "slot": 1, "uses": 4, "time": 15.0, "cd": 1.6, "dmg": 16, "min": 60.0, "max": 320.0, "los": false, "speed": 0.0, "sfx": "swing"},
	"hammer": {"name": "War Hammer", "slot": 0, "uses": 8, "time": 14.0, "cd": 0.8, "dmg": 30, "min": 0.0, "max": 135.0, "los": false, "speed": 0.0, "sfx": "swing"},
	"frost_gun": {"name": "Frost Gun", "slot": 0, "uses": 30, "time": 12.0, "cd": 0.16, "dmg": 5, "min": 0.0, "max": 380.0, "los": true, "speed": 760.0, "sfx": "shoot"},
	"boomerang": {"name": "Boomerang", "slot": 1, "uses": 5, "time": 14.0, "cd": 1.3, "dmg": 15, "min": 60.0, "max": 380.0, "los": false, "speed": 0.0, "sfx": "shoot"},
	"bomb_launcher": {"name": "Bomb Launcher", "slot": 1, "uses": 5, "time": 14.0, "cd": 1.2, "dmg": 26, "min": 120.0, "max": 480.0, "los": false, "speed": 0.0, "sfx": "swing"},
	"rocket": {"name": "Rocket Launcher", "slot": 1, "uses": 4, "time": 12.0, "cd": 1.0, "dmg": 38, "min": 140.0, "max": 800.0, "los": true, "speed": 900.0, "sfx": "shoot"},
	"meteor": {"name": "Meteor Storm", "slot": 1, "uses": 2, "time": 12.0, "cd": 3.0, "dmg": 28, "min": 100.0, "max": 450.0, "los": false, "speed": 0.0, "sfx": "swing"},
	"gatling": {"name": "Gatling Gun", "slot": 0, "uses": 60, "time": 12.0, "cd": 0.07, "dmg": 5, "min": 0.0, "max": 440.0, "los": true, "speed": 800.0, "sfx": "shoot"},
}

var id := ""
var slot := 0
var uses := 1
var time := 12.0
var until := 0.0           ## seconds (Time.get_ticks_msec / 1000) when it runs out; set by the Player when it is picked up
var min_range := 0.0
var max_range := 400.0
var needs_los := false
var lead_speed := 0.0
var _melee: HeroBasic      ## the hammer is a slow, heavy HeroBasic arc

static func ids() -> Array:
	return DEFS.keys()

static func make(weapon_id: String) -> FsWeapon:
	var d: Dictionary = DEFS[weapon_id]
	var w := FsWeapon.new()
	w.id = weapon_id
	w.display_name = d.name
	w.slot = d.slot
	w.uses = d.uses
	w.time = d.time
	w.cooldown = d.cd
	w.damage = d.dmg
	w.sfx = d.sfx
	w.min_range = d.min
	w.max_range = d.max
	w.needs_los = d.los
	w.lead_speed = d.speed
	if weapon_id == "hammer":
		var h := HeroBasic.new()
		h.mode = "arc"
		h.radius = 135.0
		h.arc_angle = 2.3
		h.windup = 0.18
		h.active = 0.14
		h.damage = w.damage
		h.cooldown = w.cooldown
		h.finisher_mult = 1.0
		h.finisher_cd_mult = 1.0
		w._melee = h
	return w

func seconds_left() -> float:
	return maxf(until - Time.get_ticks_msec() / 1000.0, 0.0)

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	var scene := caster.get_tree().current_scene
	var from := caster.global_position + Vector2(0, 8)
	match id:
		"slingshot":
			_bolt(scene, caster, Spell.assist_dir(caster, aim_dir, 0.25, 420.0), 720.0, 0.55, 9.0, Color(0.85, 0.7, 0.4))
		"frost_gun":
			var p := IceBolt.new().setup(from + aim_dir * 28.0, aim_dir * 760.0, damage, true, caster)
			p.radius = 10.0
			p.life = 0.5
			p.color = Color(0.55, 0.88, 1.0)
			scene.add_child(p)
		"gatling":
			var rng: RandomNumberGenerator = caster.get("rng")
			var dir := aim_dir.rotated(rng.randf_range(-0.09, 0.09))
			_bolt(scene, caster, dir, 800.0, 0.55, 8.0, Color(1.0, 0.9, 0.35))
		"hammer":
			return _melee.cast(caster, aim_dir, aim_pos)
		"firecracker":
			var t := _lob_target(caster, aim_pos, 320.0)
			_lob(scene, from, t, 0.5, Color(1.0, 0.55, 0.3))
			scene.add_child(Explosion.new().setup(t, 85.0, damage, 0.5, caster))
		"bomb_launcher":
			var t := _lob_target(caster, aim_pos, 480.0)
			_lob(scene, from, t, 0.75, Color(0.2, 0.2, 0.25))
			scene.add_child(Explosion.new().setup(t, 120.0, damage, 0.75, caster))
		"boomerang":
			var b := Boomerang.new().setup(from + aim_dir * 24.0, aim_dir * 760.0, damage, true, caster)
			b.home = caster
			b.pierce = 99
			b.radius = 16.0
			scene.add_child(b)
		"rocket":
			var r := Rocket.new().setup(from + aim_dir * 30.0, aim_dir * 900.0, damage, true, caster)
			r.radius = 12.0
			r.life = 1.0
			r.silent = true
			scene.add_child(r)
		"meteor":
			var rng: RandomNumberGenerator = caster.get("rng")
			var centre := _lob_target(caster, aim_pos, 450.0)
			for i in 8:
				var spot := centre if i == 0 else centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 280.0)
				var wait := 0.6 + i * 0.17
				scene.add_child(Explosion.new().setup(spot, 85.0, damage, wait, caster))
	return cooldown

func _bolt(scene: Node, caster: Node2D, dir: Vector2, speed: float, life: float, radius: float, color: Color) -> void:
	var p := Projectile.new().setup(caster.global_position + dir * 28.0 + Vector2(0, 8), dir * speed, damage, true, caster)
	p.radius = radius
	p.life = life
	p.color = color
	scene.add_child(p)

## Where a lobbed shot lands: the aim point, no farther than `reach` from the caster.
static func _lob_target(caster: Node2D, aim_pos: Vector2, reach: float) -> Vector2:
	var off := aim_pos - caster.global_position
	return caster.global_position + off.limit_length(reach)

static func _lob(scene: Node, from: Vector2, to: Vector2, secs: float, color: Color) -> void:
	var l := Lob.new()
	l.from = from
	l.to = to
	l.secs = secs
	l.color = color
	scene.add_child(l)

## The ball in the air between a lobbed shot's thrower and its blast.
class Lob extends Node2D:
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var secs := 0.5
	var color := Color.WHITE
	var _age := 0.0

	func _ready() -> void:
		z_index = 20

	func _process(delta: float) -> void:
		_age += delta
		if _age >= secs:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / secs, 0.0, 1.0)
		var p := from.lerp(to, k) - global_position + Vector2(0, -sin(k * PI) * 90.0)
		draw_circle(from.lerp(to, k) - global_position, 7.0 * (1.0 - 0.3 * sin(k * PI)), Color(0, 0, 0, 0.25))
		draw_circle(p, 9.0, Color.BLACK)
		draw_circle(p, 7.0, color)

## Frost Gun bolt: a hit also slows the victim (applied on the victim's own peer, which is the one that simulates its movement).
class IceBolt extends Projectile:
	func _on_body_entered(body: Node) -> void:
		var live: bool = body != source and not ("down" in body and body.down) and not (body.has_method("phased") and body.phased())
		super(body)
		if live and body.has_method("apply_slow") and body.has_method("owns") and body.owns():
			body.apply_slow(0.45, 1.6)

## Flies out, then curves back to its thrower, hitting everything on both legs. Passes through rocks.
class Boomerang extends Projectile:
	const OUT_TIME := 0.5
	var home: Node2D
	var _age := 0.0
	var _turned := false

	func _physics_process(delta: float) -> void:
		_age += delta
		if _age >= OUT_TIME:
			if not _turned:
				_turned = true
				_hit.clear()   # it can hit everyone again on the way back
			if not is_instance_valid(home) or _age > 3.0:
				queue_free()
				return
			var to := home.global_position - global_position
			if to.length() < 34.0:
				queue_free()
				return
			velocity = to.normalized() * 840.0
		position += velocity * delta
		rotation += delta * 18.0
		queue_redraw()

	func _on_body_entered(body: Node) -> void:
		if body.has_method("take_damage"):
			super(body)

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(-16, -12), Vector2(14, 0), Vector2(-16, 12), Vector2(-6, 0)])
		draw_colored_polygon(pts, Color(0.45, 0.9, 0.5))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 2.5)

## Rocket: explodes on the first body or when its fuel runs out. The blast, not the missile, does the damage.
class Rocket extends Projectile:
	var _done := false

	func _physics_process(delta: float) -> void:
		position += velocity * delta
		life -= delta
		queue_redraw()
		if life <= 0.0:
			_explode()

	func _on_body_entered(body: Node) -> void:
		if body == source or ("down" in body and body.down) or (body.has_method("phased") and body.phased()):
			return
		_explode()

	func _explode() -> void:
		if _done:
			return
		_done = true
		var boom := Explosion.new().setup(global_position, 150.0, damage, 0.03, source)
		get_parent().add_child.call_deferred(boom)
		queue_free()

	func _draw() -> void:
		var a := velocity.angle()
		var f := Vector2.from_angle(a)
		draw_circle(-f * 18.0, 9.0, Color(1.0, 0.6, 0.15, 0.7))
		draw_circle(-f * 10.0, 6.0, Color(1.0, 0.9, 0.4))
		draw_line(-f * 14.0, f * 14.0, Color.BLACK, 11.0)
		draw_line(-f * 12.0, f * 12.0, Color(0.9, 0.25, 0.2), 7.0)
		draw_circle(f * 14.0, 5.0, Color(0.95, 0.95, 0.95))
