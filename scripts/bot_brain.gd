class_name BotBrain extends RefCounted
## The "keyboard" of a bot. A Player with `ai` set asks think() every physics frame and reads the same four things a human
## gives it: move, aim_pos, which skill slots are held, a dash press (plus an emote). Everything else (cooldowns, casting,
## damage) is the normal Player code, so a bot plays by exactly the same rules.
##
## What it does, in priority order:
##  1. Survive the edge: if a slide (knock) will end in the water, dash back; if already over water, dash for land.
##  2. Dodge: sidestep or dash out of incoming projectiles and unexploded blasts, and keep clear of hot-potato carriers.
##  3. Hot potato: when carrying it, run at the nearest victim and dash in to hand it over.
##  4. Pickups: go for healing when hurt and for power-ups when they are close; avoid the chicken and potato pickups.
##  5. Fight: pick a target (wounded, close, crowned, not a giant), hold the spacing the hero is built for (melee closes in,
##     ranged keeps back and strafes), lead its shots, and fire only through clear lines (cover blocks bolts).
## `skill` (0..1) scales reaction time, aim error and how often it dodges. Rocks are steered around, and a bot that stops
## making progress backs off sideways and dashes.

const REACT_SLOW := 0.32      ## seconds between decisions at skill 0
const REACT_FAST := 0.07      ## ... at skill 1
const EDGE_PROBE := 130.0     ## px: how far ahead the bot looks for water
const EDGE_FAR := 330.0       ## px: a softer, earlier nudge toward the middle
const DASH_SPEED_PX := 240.0  ## what one dash covers (Player.DASH_SPEED * DASH_TIME)
const PICKUP_VALUE := {"heal": 1.0, "damage": 1.6, "speed": 0.9, "mystery": 1.1, "giant": 1.4, "chicken": -1.0, "bomb": -1.0}

# --- what Player reads
var move := Vector2.ZERO
var aim_pos := Vector2.ZERO
var held: Array[bool] = [false, false, false, false]
var skill := 0.6

var _dash := false
var _emote := -1
var _emote_age := 0.0

var _p: Player
var _arena: Node              ## the match: _pickups and _map
var _map: WorldMap
var _target: Player
var _steer := Vector2.ZERO
var _aim_goal := Vector2.ZERO
var _dash_dir := Vector2.ZERO
var _orbit := 1.0
var _react := 0.0
var _retarget := 0.0
var _orbit_t := 0.0
var _burst_t := 0.0
var _bursting := true
var _dash_cd := 0.0
var _mark_pos := Vector2.ZERO
var _mark_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := Vector2.ZERO
var _rescue_ok := true

func setup(player: Player, arena: Node, level: float) -> void:
	_p = player
	_arena = arena
	_map = arena._map
	skill = clampf(level, 0.0, 1.0)
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_react = randf() * 0.3   # bots do not all think on the same frame

# --- Player-facing API

func take_dash() -> bool:
	var d := _dash
	_dash = false
	return d

func take_emote() -> int:
	var e := _emote
	_emote = -1
	return e

func holding() -> bool:
	return held.has(true)

## The match tells the bot about its own kills and deaths so it can gloat or groan.
func on_kill() -> void:
	if randf() < 0.45:
		_emote = [0, 1].pick_random()
		_emote_age = 0.0

func on_death(cause: String) -> void:
	if randf() < (0.7 if cause == "fall" else 0.25):
		_emote = 2
		_emote_age = 0.0

# --- the loop

func think(delta: float) -> void:
	if _p.down:
		move = Vector2.ZERO
		held = [false, false, false, false]
		_dash = false
		return
	_emote_age += delta
	if _emote_age > 2.0:
		_emote = -1
	_retarget -= delta
	_orbit_t -= delta
	_burst_t -= delta
	_dash_cd -= delta
	_react -= delta
	_unstick_t -= delta
	if _orbit_t <= 0.0:
		_orbit = -_orbit if randf() < 0.6 else _orbit
		_orbit_t = randf_range(1.0, 2.6)
	if _burst_t <= 0.0:   # fire in bursts, then reposition, like a person tapping the button
		_bursting = not _bursting
		_burst_t = randf_range(0.5, 0.9) if _bursting else randf_range(0.15, 0.35)
	if _react <= 0.0:
		_react = lerpf(REACT_SLOW, REACT_FAST, skill) * randf_range(0.75, 1.25)
		_decide()
	move = _dash_dir if _dash else _steer   # a dash press uses `move` as its direction
	aim_pos = _aim_goal
	_safety(delta)

# --- thinking

func _decide() -> void:
	var me := _p.global_position
	var foes := _foes()
	_pick_target(foes, me)
	var hp_frac := float(_p.hp) / maxf(_p.max_hp, 1.0)
	var want := Vector2.ZERO
	var tpos := _target.global_position if _target else me
	var dist := me.distance_to(tpos)

	# objective
	var pickup := _best_pickup(me, hp_frac)
	if _p.has_bomb:
		var victim := _nearest(foes, me, true)
		if victim:
			want = _dir(me, victim.global_position)
			if me.distance_to(victim.global_position) > 110.0 and me.distance_to(victim.global_position) < 330.0:
				_try_dash(want, 0.8)
	elif pickup.pos != Vector2.INF and (_target == null or pickup.score > 1.3 or dist > 500.0):
		want = _dir(me, pickup.pos)
	elif _target:
		want = _spacing(me, tpos, dist)
	elif me.distance_to(_map.spawn_point) > 250.0:
		want = _dir(me, _map.spawn_point)   # nobody around: drift back to the middle

	# hurt and pressed: back off (a heal pickup already took the objective above)
	if hp_frac < 0.3 and _target and dist < 260.0 and pickup.pos == Vector2.INF:
		want = (want * 0.3 + _dir(tpos, me) * 1.2)
		if dist < 150.0:
			_try_dash(_dir(tpos, me), 0.7)

	want += _repulsion(me, foes, pickup)
	var edge := _edge_push(me, EDGE_PROBE)
	want += edge * 2.5 + _edge_push(me, EDGE_FAR) * 0.9 + _knock_line(me, foes) * 1.3
	want += _dodge(me) * 2.5
	want = _around_cover(want.normalized() if want.length() > 0.05 else Vector2.ZERO, me)

	# stuck: tried to move for a while without getting anywhere
	_mark_t += _react
	if _mark_t > 0.7:
		if want.length() > 0.5 and me.distance_to(_mark_pos) < 18.0 and not held[0]:
			_unstick_t = 0.6
			_unstick_dir = want.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
			_try_dash(_unstick_dir, 0.5)
		_mark_pos = me
		_mark_t = 0.0
	_steer = (_unstick_dir if _unstick_t > 0.0 else want).limit_length(1.0)

	_attack(me, tpos, dist, edge)

## The spacing the hero is built for: melee closes in, ranged keeps back and circles.
func _spacing(me: Vector2, tpos: Vector2, dist: float) -> Vector2:
	var to := _dir(me, tpos)
	var ideal := 70.0
	if _p.hero.attack_type == "ranged":
		ideal = _p.hero.attack_range * 0.62
	var radial := clampf((dist - ideal) / 90.0, -1.0, 1.0)
	var tangent := to.orthogonal() * _orbit * (0.55 if _p.hero.attack_type == "ranged" else 0.25)
	# melee wants to be in reach and swinging; the circling would only waste it
	if _p.hero.attack_type == "melee" and dist < ideal + 30.0:
		tangent *= 0.3
	if _target and _target.dash_charges == 0 and _p.dash_charges > 1 and _p.hero.attack_type == "melee" and dist > 220.0 and dist < 420.0:
		_try_dash(to, 0.5)   # close the gap
	return to * radial + tangent

func _attack(me: Vector2, tpos: Vector2, dist: float, edge: Vector2) -> void:
	for i in 4:
		held[i] = false
	var aim_from := me + Vector2(0, 8)
	_aim_goal = tpos if _target else me + (_steer if _steer.length() > 0.1 else Vector2.RIGHT) * 200.0
	if _target == null or _p.buffed("chicken") or _p.has_bomb or edge.length() > 0.6:
		return
	var los := _los_clear(aim_from, tpos)
	for i: int in [3, 1, 2, 0]:
		if i >= _p.spells.size():
			continue
		var s: Spell = _p.spells[i]
		if _p.cooldowns[i] > 0.04 or _p.signature_charge < s.charge_cost or not _fits(s, dist, los):
			continue
		if i == 0 and not _bursting:
			continue
		held[i] = true
		_aim_goal = _aim_for(s, aim_from, tpos)
		break
	var err := randfn(0.0, lerpf(0.14, 0.015, skill))
	_aim_goal = aim_from + (_aim_goal - aim_from).rotated(err)

## Does this skill make sense at this range? Bolts need a clear line, blasts and arcs do not.
func _fits(s: Spell, dist: float, los: bool) -> bool:
	var hb := s as HeroBasic
	if hb:
		if hb.mode == "arc":
			return dist < hb.radius + 6.0
		return dist < hb.bolt_speed * hb.bolt_life * 0.92 and los
	if s is FireWave:
		return dist > 90.0 and dist < 340.0 and los
	if s is Blast:
		return dist < Blast.MAX_RANGE - 20.0
	if s is SnipeShot:
		return dist > 260.0 and dist < 1000.0 and los
	if s is ShieldCharge:
		return dist > 110.0 and dist < 215.0 and los
	if s is BladeStorm:
		return dist < 140.0
	if s is ArrowBarrage:
		return dist < 640.0 and los
	if s is MeteorBarrage:
		return dist < 400.0
	return false

## Where to aim: ahead of a moving target for slow shots, and at where it will be for delayed blasts.
func _aim_for(s: Spell, from: Vector2, tpos: Vector2) -> Vector2:
	var vel := _target.velocity if skill > 0.35 else Vector2.ZERO
	if s is Blast:
		return tpos + (vel * 0.45).limit_length(160.0)
	if s is MeteorBarrage:
		return tpos + (vel * 0.5).limit_length(160.0)
	var speed := 0.0
	var hb := s as HeroBasic
	if hb and hb.mode == "bolt":
		speed = hb.bolt_speed
	elif s is FireWave:
		speed = 520.0
	elif s is SnipeShot:
		speed = SnipeShot.SPEED
	elif s is ArrowBarrage:
		speed = 1000.0
	if speed <= 0.0:
		return tpos
	return lead(from, tpos, vel, speed)

## Intercept point for a shot of `speed` at a target moving with `vel`.
static func lead(from: Vector2, pos: Vector2, vel: Vector2, speed: float) -> Vector2:
	var t := from.distance_to(pos) / maxf(speed, 1.0)
	for i in 2:
		t = from.distance_to(pos + vel * t) / maxf(speed, 1.0)
	return pos + (vel * t).limit_length(220.0)

func _pick_target(foes: Array[Player], me: Vector2) -> void:
	if _retarget > 0.0 and is_instance_valid(_target) and not _target.down and _target in foes:
		return
	_retarget = 0.7
	var best: Player = null
	var best_s := -INF
	for f in foes:
		if f.has_bomb:
			continue   # never chase the potato carrier: stay clear and let someone else eat it
		var d := me.distance_to(f.global_position)
		var s := 900.0 / (d + 120.0) + (1.0 - float(f.hp) / maxf(f.max_hp, 1.0)) * 3.0
		if f.crowned:
			s += 2.5   # a bounty
		if f.buffed("giant"):
			s -= 1.5
		if f == _target:
			s += 1.0
		if s > best_s:
			best_s = s
			best = f
	_target = best

func _foes() -> Array[Player]:
	var out: Array[Player] = []
	for n in _p.get_tree().get_nodes_in_group("players"):
		var f := n as Player
		if f and f != _p and not f.down and not (_p.team >= 0 and f.team == _p.team):
			out.append(f)
	return out

func _nearest(foes: Array[Player], me: Vector2, without_bomb: bool) -> Player:
	var best: Player = null
	for f in foes:
		if without_bomb and f.has_bomb:
			continue
		if best == null or me.distance_squared_to(f.global_position) < me.distance_squared_to(best.global_position):
			best = f
	return best

## {pos, score} of the pickup worth walking to, pos == Vector2.INF when none.
func _best_pickup(me: Vector2, hp_frac: float) -> Dictionary:
	var best := {"pos": Vector2.INF, "score": 0.0}
	if _p.has_bomb or _p.buffed("chicken"):
		return best
	for pk: PvpPickup in _arena._pickups.values():
		var value: float = PICKUP_VALUE.get(pk.kind, 0.0)
		if pk.kind == "heal":
			value = 0.15 if hp_frac > 0.9 else 1.0 + (1.0 - hp_frac) * 3.0
		if value <= 0.0:
			continue
		var score := value * 600.0 / (me.distance_to(pk.global_position) + 200.0)
		if score > best.score:
			best = {"pos": pk.global_position, "score": score}
	return best

## Keep away from potato carriers, the bad pickups and blasts that have not gone off yet.
func _repulsion(me: Vector2, foes: Array[Player], _pickup: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	if not _p.has_bomb:
		for f in foes:
			if f.has_bomb:
				var d := me.distance_to(f.global_position)
				if d < 330.0:
					push += _dir(f.global_position, me) * (1.6 + (330.0 - d) / 330.0)
					if d < 140.0:
						_try_dash(_dir(f.global_position, me).orthogonal() * (1.0 if randf() < 0.5 else -1.0) + _dir(f.global_position, me), 0.9)
	for pk: PvpPickup in _arena._pickups.values():
		if pk.kind == "chicken" or pk.kind == "bomb":
			if me.distance_to(pk.global_position) < 120.0:
				push += _dir(pk.global_position, me) * 1.5
	for n in _p.get_tree().get_nodes_in_group("explosions"):
		var e := n as Explosion
		if e and not e._boomed and me.distance_to(e.global_position) < e.radius + 60.0:
			push += _dir(e.global_position, me) * 2.5
			var left := e.delay - e._age
			if left < 0.3 and me.distance_to(e.global_position) < e.radius:
				_try_dash(_dir(e.global_position, me), 0.9)
	return push

## Which way to sidestep the soonest projectile that will hit (zero = none), dashing if it is nearly on us.
func _dodge(me: Vector2) -> Vector2:
	var worst_t := 0.7
	var side := Vector2.ZERO
	for n in _p.get_tree().get_nodes_in_group("projectiles"):
		var pr := n as Projectile
		if pr == null or pr.source == _p or pr.velocity.length() < 1.0:
			continue
		var dirv := pr.velocity.normalized()
		var rel := me - pr.global_position
		var along := rel.dot(dirv)
		if along < 0.0 or along > pr.velocity.length() * worst_t:
			continue
		var lateral := rel - dirv * along
		if lateral.length() < pr.radius + 26.0:
			worst_t = along / pr.velocity.length()
			side = lateral.normalized() if lateral.length() > 2.0 else dirv.orthogonal()
	if side == Vector2.ZERO or randf() > lerpf(0.15, 0.85, skill) * 1.4:
		return Vector2.ZERO
	if worst_t < 0.3:
		_try_dash(side, 1.0)
	return side

# --- geometry / safety

## Asks for a dash toward `dir` (never on cooldown and only sometimes, `chance` scaled by skill).
func _try_dash(dir: Vector2, chance: float) -> void:
	if _dash_cd > 0.0 or _p.dash_charges <= 0 or dir.length() < 0.1:
		return
	if randf() > chance * lerpf(0.4, 1.0, skill):
		return
	_dash_dir = dir.normalized()
	_dash = true
	_dash_cd = 1.2

## Away from water: sums the directions in which the ground ends within `reach`.
func _edge_push(me: Vector2, reach: float) -> Vector2:
	var push := Vector2.ZERO
	var feet := me + Vector2(0, 14)
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		if _map.is_water(feet + d * reach):
			push -= d
	if push == Vector2.ZERO:
		return push
	return push.normalized() * minf(push.length(), 1.5)

## A hit knocks us straight away from whoever hit us, up to ~500 px. Don't stand where that ends in the water.
func _knock_line(me: Vector2, foes: Array[Player]) -> Vector2:
	var push := Vector2.ZERO
	var feet := me + Vector2(0, 14)
	for f in foes:
		var away := _dir(f.global_position, me)
		var d := me.distance_to(f.global_position)
		if d > 700.0:
			continue
		for reach in [220.0, 360.0, 500.0]:
			if _map.is_water(feet + away * reach):
				push += _dir(me, _map.spawn_point) * (1.0 - d / 700.0)   # toward the middle, harder the closer the foe
				break
	return push

func _around_cover(dir: Vector2, me: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return dir
	for c in _map.cover:
		var rel := c - me
		var along := rel.dot(dir)
		if along <= 0.0 or along > 230.0:
			continue
		var perp := rel - dir * along
		if perp.length() < WorldMap.COVER_R + 36.0:
			var away := -perp.normalized() if perp.length() > 1.0 else dir.orthogonal()
			dir = (dir + away * 1.4).normalized()
	return dir

func _los_clear(a: Vector2, b: Vector2) -> bool:
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1.0)
	for c in _map.cover:
		var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < WorldMap.COVER_R + 10.0:
			return false
	return true

func _dir(from: Vector2, to: Vector2) -> Vector2:
	return (to - from).normalized()

## Every frame: don't drown. A slide toward the water gets a dash back, and so does standing in it.
func _safety(_delta: float) -> void:
	var feet := _p.global_position + Vector2(0, 14)
	var centre := _map.spawn_point
	var to_centre := _dir(feet, centre)
	var slide_end := feet + _p.knock.normalized() * (_p.knock.length_squared() / (2.0 * Player.KNOCK_DECEL)) if _p.knock.length() > 150.0 else feet
	var danger := _map.is_water(feet) or _map.is_water(slide_end) or _map.is_water(feet + _p.velocity * 0.25)
	if not danger:
		_rescue_ok = randf() < lerpf(0.6, 1.0, skill)   # decided once per scare: an easy bot sometimes freezes
		return
	for i in 4:
		held[i] = false
	if _rescue_ok:
		move = to_centre
		if _p.dash_charges > 0 and not _dash and _p._dash_time <= 0.0:
			_dash_dir = to_centre
			_dash = true
	# a dash press uses `move` as its direction
	if _dash:
		move = _dash_dir
