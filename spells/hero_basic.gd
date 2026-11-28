class_name HeroBasic extends Spell
## Every hero's basic, shaped per archetype by Hero.make_basic(). mode "arc": a cone sweep (Knight cleave, Rogue stab).
## mode "bolt": a projectile (Ranger arrow); with `splash` > 0 it is an orb that flies to the cursor and bursts there
## (Mage). With `combo` on, the 3rd cast in a row is a finisher (bigger hit, a launch, extra bolts for spread heroes);
## heroes without it hit the same every time. No auto-lunge: a locked swing only steps in with PlaySettings.melee_step.

const FINISHER_SHOVE := 250.0   ## extra launch on the melee finisher (~50-100 px slide with its own knockback)
const COMBO_WINDOW_MSEC := 900
const ROGUE_STAB_HIT := "rogue_stab"
const ROGUE_RUSH_HIT := "rogue_rush"

static func rogue_impact(victim: Node2D, direction: Vector2, rush: bool) -> void:
	var sprite := SheetFrames.play_once(victim.get_parent(), victim.global_position + Vector2(0, -16),
		SheetFrames.FX + "Spells/Rogue/SilverImpact.png", 5, 38.0, 1.5)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 20
	sprite.rotation = direction.angle()
	if rush:
		sprite.modulate = Color(0.62, 0.82, 1.0)

@export var mode := "bolt"
@export var radius := 115.0          ## arc reach
@export var arc_angle := 2.2
@export var windup := 0.1             ## melee: telegraph before the sweep turns live
@export var active := 0.12            ## melee: how long the sweep keeps hitting (each foe once)
@export var assist_angle := 0.55      ## melee/bolt aim assist: snap toward the nearest foe within this angle (see aim()); was 0.35 (20 deg), whiffed on strafing foes
@export var lunge_speed := 0.0       ## melee: step forward with each sweep
@export var back_mult := 1.0         ## melee: damage multiplier on a victim that is facing away from the sweep
@export var bolt_speed := 640.0
@export var bolt_radius := 16.0
@export var bolt_life := 0.6
@export var bolt_pierce := 0
@export var finisher_spread := 1     ## extra bolt pairs on the finisher
@export var finisher_mult := 1.0
@export var finisher_cd_mult := 1.5  ## longer recovery after the finisher
@export var combo := true            ## false: no finisher, every cast is the same
@export var splash := 0.0            ## bolt: > 0 = an orb that bursts in this radius at the cursor or on the first thing it touches
@export var fx_color := Color(1.0, 0.5, 0.15)   ## sweep / orb colour, so each hero's basic reads apart
@export var knight_cleave_fx := false
@export var chaos_cleave_fx := false          ## use the cut in the floor and the split impact
@export var rogue_stab_art := false
@export var arrow_tex := ""          ## bolt: arrow frame folder ("" = the default spell sprite)
@export var might := 0.0             ## + this x the caster's current HP as damage (Paladin Holy Might)
@export var focus_hits := 0          ## the Nth hit in a row on one target crits (Shade Focus); 0 = off
@export var crit_mult := 2.5
@export var chaos_lo := 0.0           ## Loaded Dice (Chaos Lord): every cast rolls a damage multiplier in [chaos_lo, chaos_hi]; 0 = off
@export var chaos_hi := 0.0
@export var impetus := 0.0           ## Long Malice (Demonbound): + this much damage per px the bolt flew
@export var pull := 0.0              ## Grasping Blast (Pactknight): px a hit drags the foe toward the caster
@export var homing := true           ## bolt: a locked bolt steers at its target. false = a skillshot (Ranger): it flies straight, aim matters
const EMPOWER_MULT := 2.5            ## Tumble (Scout): the next shot's damage
const EMPOWER_PIERCE := 2

var _focus_target: Node = null
var _focus := 0

## Focus (Shade): one more hit on `e`. Returns the damage multiplier: crit_mult on the focus_hits-th hit in a row on the
## same target (then it starts over), 1 otherwise. A different target starts the count again. Deterministic: no dice.
func focus_mult(e: Node) -> float:
	if focus_hits <= 0:
		return 1.0
	if e != _focus_target:
		_focus_target = e
		_focus = 0
	_focus += 1
	if _focus >= focus_hits:
		_focus = 0
		return crit_mult
	return 1.0

## Riposte: the next hit on `e` is the crit.
func prime_focus(e: Node) -> void:
	if focus_hits > 0:
		_focus_target = e
		_focus = focus_hits - 1

## Hits landed in a row on the current focus target (for the HUD / tests).
func focus_count() -> int:
	return _focus

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
	var pose: StringName
	var lunge_speed := 0.0
	var lunge_time := 0.08
	var lock: Node2D      ## lock-on: the swing turns to this foe when it goes live
	var back_mult := 1.0
	var color := Color(1.0, 0.5, 0.15)
	var basic: HeroBasic   ## the spell that swung it (Focus counts on it)
	var chaos_power := 0.0
	var _age := 0.0
	var _lunged := false
	var _hit: Array[Node] = []

	func _physics_process(delta: float) -> void:
		_age += delta
		if not is_instance_valid(caster) or caster.down:
			queue_free()
			return
		position = caster.global_position + Vector2(0, 8)
		if not pose.is_empty() and caster is Player and caster._knight_sweep == self:
			if caster._sprite.animation == pose and caster._cast_time > 0.0 and (caster._freeze <= 0.0 or not _lunged and _age >= windup):
				var frame := KnightFx.cleave_frame(pose, _age, windup, Player.SWING_TIME)
				caster._sprite.set_frame_and_progress(frame, 0.0)
		if _age < windup:
			return
		if not _lunged:
			_lunged = true
			if is_instance_valid(lock) and not lock.down:
				dir = (lock.global_position - caster.global_position).normalized()   # it moved during the windup
				if caster is Player and basic and (basic.chaos_cleave_fx or basic.knight_cleave_fx or basic.rogue_stab_art) and caster._cast_time > 0.0:
					if caster._sprite.animation in [&"cast", &"cast2", &"cast_finisher"]:
						caster._face_cast(dir)
			if lunge_speed > 0.0:
				caster.lunge(dir, lunge_time, lunge_speed)
		var projection := basic.range_projection() if basic else Vector2.ONE
		var axis := dir / projection
		for e in Spell.foes(caster):
			var off := (e.global_position - position) / projection
			if e in _hit or off.length() > reach + 20.0:
				continue
			if off.length() < 24.0 or absf(axis.angle_to(off)) <= angle / 2.0 + atan2(20.0, off.length()):   # the edge of the cone counts the foe's body, not just its centre
				_hit.append(e)
				var hit := dmg
				var unseen: bool = caster.has_method("veiled") and (caster.veiled() or caster.ambushing())   # Smoke Screen / a stab out of Stalk: from behind
				if back_mult > 1.0 and (unseen or Sweep.from_behind(e, position)):
					hit = roundi(dmg * back_mult)
					if e.has_method("float_text"):
						e.float_text("BACKSTAB", Color(1.0, 0.45, 0.9), 22)
				var crit := basic.focus_mult(e) if basic else 1.0
				if crit > 1.0:
					hit = roundi(hit * crit)
					if e.has_method("float_text"):
						e.float_text("CRIT", Color(0.4, 1.0, 0.6), 24)
				Player.basic_hit = not finisher   # the Knight's finisher still launches; every other swing only flinches
				if basic and basic.chaos_cleave_fx:
					e.take_damage(hit, position, false, caster, ChaosFx.CLEAVE, chaos_power)
				elif basic and basic.knight_cleave_fx:
					e.take_damage(hit, position, false, caster, KnightFx.FINISHER if finisher else KnightFx.CLEAVE)
				elif basic and basic.rogue_stab_art:
					e.take_damage(hit, position, false, caster, ROGUE_STAB_HIT)
				else:
					e.take_damage(hit, position, false, caster)   # the hit sound plays only when the hit lands
				Player.basic_hit = false
				if finisher:
					Spell.shove(e, dir * FINISHER_SHOVE)   # the 3rd hit launches; hits 1-2 only flinch, so the combo keeps landing

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
		if basic and basic.rogue_stab_art:
			return   # the silver glint is painted at the moving stiletto tip
		if basic and basic.chaos_cleave_fx:
			ChaosFx.draw_boundary(self, dir, angle, reach, _age, windup, active, chaos_power)
			return
		if basic and basic.knight_cleave_fx:
			KnightFx.draw_cleave(self, dir, angle, reach, _age, windup, finisher, pose == &"cast")
			return
		var base := dir.angle() - angle / 2.0
		var pts := PackedVector2Array([Vector2.ZERO])
		if _age < windup:   # telegraph: faint outline growing toward full reach
			var w := _age / windup
			for i in 13:
				pts.append(Vector2.from_angle(base + angle * i / 12.0) * reach * (0.5 + 0.5 * w))
			draw_polyline(pts.slice(1), Color(color.lightened(0.4), 0.25 + 0.4 * w), 2.0)
			return
		var t := clampf((_age - windup) / (active + 0.08), 0.0, 1.0)
		for i in 13:
			pts.append(Vector2.from_angle(base + angle * i / 12.0) * reach)
		draw_colored_polygon(pts, Color(color, (0.7 if finisher else 0.55) * (1.0 - t)))
		draw_polyline(pts.slice(1), Color(1, 1, 1, 0.8 * (1.0 - t)), 3.0)

const LOCK_RADIUS := 150.0   ## a foe this close to the cursor is the target (was 110: a moving foe slipped out from under a casual cursor)
const LOCK_STEP := 250.0     ## melee: a locked swing reaches this far beyond the blade by stepping in
const LOCK_LUNGE := 1000.0   ## step-in speed of a locked swing (px/s), so the gap closes inside ~0.27 s

func reach() -> float:
	if mode == "arc":
		return radius + (LOCK_STEP if PlaySettings.melee_step else 0.0)
	return bolt_speed * bolt_life

func range_projection() -> Vector2:
	return ChaosFx.GROUND_SCALE if chaos_cleave_fx else Vector2.ONE

## Lock-on (point and click): the foe under the cursor, or failing that the one in the aim cone. A locked bolt homes
## and a locked swing steps in to reach; a dash or a phase shakes it off. Bots aim for themselves: no lock.
func target(caster: Node2D, aim_pos: Vector2, dir: Vector2) -> Node2D:
	if caster.get("ai"):
		return null
	return Spell.pick_foe(caster, aim_pos, dir, LOCK_RADIUS, assist_angle, reach(), range_projection())

## Free-aimed casts (no lock): melee snaps to the nearest foe in reach, bolts lead a foe near the aim line.
func aim(caster: Node2D, dir: Vector2) -> Vector2:
	if mode == "arc":
		return Spell.assist_dir(caster, dir, assist_angle, radius + 40.0, 0.0, range_projection())
	if caster is Player and caster.ai:
		var assist := clampf(inverse_lerp(0.3, 0.9, caster.ai.skill), 0.0, 1.0)
		if assist == 0.0:
			return dir
		var corrected := Spell.assist_dir(caster, dir, assist_angle, bolt_speed * bolt_life)
		return dir.lerp(corrected, assist).normalized()
	return Spell.assist_dir(caster, dir, assist_angle, bolt_speed * bolt_life, bolt_speed)

## Orb: seconds of flight to burst on `aim_pos` (at least a short throw, at most the full range).
func orb_life(from: Vector2, aim_pos: Vector2) -> float:
	return clampf(from.distance_to(aim_pos), 90.0, bolt_speed * bolt_life) / bolt_speed

func combo_step() -> int:
	return _combo if combo and Time.get_ticks_msec() - _last_msec <= COMBO_WINDOW_MSEC else 0

func cast(caster: Node2D, aim_dir: Vector2, aim_pos: Vector2) -> float:
	_combo = combo_step()
	var now := Time.get_ticks_msec()
	_last_msec = now
	var finisher := combo and _combo == 2
	var opening := _combo == 0
	cast_pitch = 0.8 if finisher else 0.95 + 0.1 * _combo   # the swing sound climbs 1-2-3, then the finisher lands deep and loud
	cast_vol = 3.0 if finisher else 0.0
	_combo = 0 if finisher or not combo else _combo + 1
	var dmg := int(damage * (finisher_mult if finisher else 1.0))
	if caster.has_method("focus_firing") and caster.focus_firing():   # Focus Fire: many arrows, each lighter
		dmg = maxi(roundi(dmg * FocusFire.DAMAGE_MULT), 1)
	if might > 0.0 and "hp" in caster:   # Holy Might: the healthier the Paladin, the harder it hits
		dmg += roundi(caster.hp * might)
	var chaos_power := 0.0
	if chaos_hi > 0.0 and caster is Player:   # Loaded Dice: the cast's seed is shared, so every peer rolls the same
		var roll := Chaos.roll(caster, chaos_lo, chaos_hi)
		dmg = maxi(roundi(dmg * roll), 1)
		chaos_power = inverse_lerp(chaos_lo, chaos_hi, roll)
	var fiend: bool = caster is Player and caster.fiended()
	var speed_k := Fiendform.SPEED if fiend else 1.0   # Fiendform: faster bolts over the same flight time = more range
	if fiend:
		dmg = roundi(dmg * Fiendform.DAMAGE)
	var empowered: bool = mode == "bolt" and caster.has_method("consume_empower") and caster.consume_empower()
	var scene := caster.get_tree().current_scene
	if mode == "arc":
		var fx := Sweep.new()
		fx.caster = caster
		fx.dir = aim_dir.normalized()
		fx.reach = radius
		fx.angle = arc_angle
		fx.windup = windup
		fx.active = active
		fx.dmg = dmg
		fx.finisher = finisher
		if knight_cleave_fx and caster is Player:
			fx.pose = &"cast_finisher" if finisher else (&"cast" if opening else &"cast2")
			caster._knight_sweep = fx
		fx.lunge_speed = lunge_speed * (2.0 if finisher else 1.0)   # finisher steps in harder
		fx.lunge_time = 0.12 if finisher else 0.08
		fx.lock = lock
		fx.color = fx_color
		fx.basic = self
		fx.chaos_power = chaos_power
		if lock and PlaySettings.melee_step:   # step in far enough to put the target inside the blade (up to ~LOCK_STEP)
			var to_lock := lock.global_position - caster.global_position
			var screen_scale := 1.0 / (to_lock.normalized() / range_projection()).length() if to_lock != Vector2.ZERO else 1.0
			var gap := to_lock.length() - radius * 0.8 * screen_scale
			if gap < 12.0:
				fx.lunge_speed = 0.0   # already inside the blade: no step-in (players do not collide, so it would run through the target)
			else:
				fx.lunge_speed = maxf(fx.lunge_speed, LOCK_LUNGE)
				fx.lunge_time = clampf(gap / fx.lunge_speed, 0.03, 0.3)
				fx.active = maxf(active, fx.lunge_time + 0.05)
		fx.back_mult = back_mult
		fx.z_index = -1 if chaos_cleave_fx or knight_cleave_fx else 5
		if knight_cleave_fx:
			fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fx.position = caster.global_position + Vector2(0, 8)
		scene.add_child(fx)
	else:
		var extra := finisher_spread if finisher else 0
		var dirs: Array[Vector2] = []
		for i in extra * 2 + 1:
			dirs.append(aim_dir.rotated((i - extra) * 0.22))
		if fiend and caster.rng.randf() < Fiendform.DOUBLE_CHANCE:   # Demon Form: often a second bolt, just off the first
			dirs.append(aim_dir.rotated(Fiendform.DOUBLE_SPREAD * (1.0 if caster.rng.randf() < 0.5 else -1.0)))
		var trail_node: Node = caster.get("_fel") if caster is Player else null
		for i in dirs.size():
			var dir := dirs[i]
			var p := Projectile.new().setup(caster.global_position + dir * 28.0 + Vector2(0, 8), dir * bolt_speed * speed_k, dmg, true, caster)
			p.impetus = impetus
			p.basic = true
			if is_instance_valid(trail_node):
				p.fel = trail_node   # Hellwalker: crossing his own trail sets the bolt alight
			p.pull = pull
			p.radius = bolt_radius
			p.life = bolt_life
			p.pierce = bolt_pierce
			p.arrow_tex = arrow_tex
			p.color = fx_color
			if empowered:   # Tumble: a big piercing shot
				p.damage = roundi(dmg * EMPOWER_MULT)
				p.pierce += EMPOWER_PIERCE
				p.radius = bolt_radius + 6.0
				p.tex_scale = 1.6
				p.trail = 160.0
				p.color = Color(1.0, 0.85, 0.3)
				p.impact_scale = 0.35
			if splash > 0.0:   # an orb: lands on the cursor (never past the range) and bursts there
				p.splash = splash
				p.life = orb_life(caster.global_position, aim_pos)
			var ff: bool = caster.has_method("focus_firing") and caster.focus_firing()
			if lock and i == extra and (homing or ff):   # only the middle bolt of a fan homes; a skillshot only under Focus Fire
				p.target = lock
				p.life = bolt_life * 1.5   # room to catch a target that is running away
			scene.add_child(p)
	return cooldown * (finisher_cd_mult if finisher else 1.0)
