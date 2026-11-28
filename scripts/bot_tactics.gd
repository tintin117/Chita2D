class_name BotTactics extends RefCounted
## Where a bot should stand next: Monte Carlo position search (the tactical layer of BotBrain).
##
## The bot's state machine (BotBrain) decides WHAT it is doing; this decides WHERE to stand while doing it.
## Every plan, the bot samples SAMPLES candidate spots it could walk to (round itself, round its target at the range its
## hero wants, the objective, the spot it already chose). Each spot is scored by ROLLOUTS short random futures, HORIZON
## seconds ahead: every foe keeps roughly its current velocity plus some noise and some drift toward the spot. A rollout
## adds up what standing there would mean then:
##   danger     foes in striking reach of the spot (worse when hurt)
##   ring-out   a foe whose hit would knock us from the spot into water (the Colosseum's moat and pools)
##   shore      water right next to the spot
##   range      how close the spot is to the hero's ideal distance from its target (+ a clear line for ranged)
##   flank      Assassins: being behind the target
##   setup      our hit from the spot would knock the target into water (herd them to the edge)
##   objective  the free crown, a pickup, a zone to hold
##   travel     route length divided by movement speed, with a dash shortcut when available
## The best average wins; the spot already chosen is kept unless a new one beats it by KEEP_MARGIN (no dithering).
##
## Why not a full MCTS: a tree search needs a fast, faithful forward model of every skill, hit and knockback; in
## GDScript at several decisions a second for several bots that model would be both too slow and too crude. Sampling
## spots and rolling each out a short way gives the useful half (look ahead at real geometry, average over what foes
## might do) at a cost that fits a frame. Reflexes (dodging, edge rescue) stay in BotBrain and run on top.
##
## `ctx` is a Dictionary so tests can build one without a match:
##   me: Vector2, speed: float, hp_frac: float, ideal: float (px from the target), ranged: bool, assassin: bool,
##   foes: Array of {pos: Vector2, vel: Vector2, aim: Vector2, reach: float, target: bool},
##   objective: Vector2 (Vector2.INF = none), objective_w: float,
##   hold_at: Vector2 (Vector2.INF = none), hold_r: float (stay inside this circle: the crown holder on the centre),
##   dash_px: float (dash distance if available, otherwise 0), avoid: Vector2 (a recently stalled goal or INF),
##   fear: float (danger and ring-out weight, set by the bot's state: Engage 0.7, Retreat 1.6; default 1)

## Tuned for a fast game: few, short rollouts and a brave default (the state machine raises the fear when it matters).
const SAMPLES := 10
const ROLLOUTS := 2
const HORIZON := 0.5
const KEEP_MARGIN := 0.1

const W_DANGER := 1.0
const W_RINGOUT := 1.6
const W_SHORE := 0.6
const W_RANGE := 2.0
const W_LOS := 0.4
const W_BEHIND := 0.9
const W_TRAVEL := 0.6
const W_SETUP := 0.8   ## standing where our own hit would ring the target out

## Candidate spots, all standing ground (on the nav grid when the map has one).
static func candidates(map: WorldMap, ctx: Dictionary, rng: RandomNumberGenerator, keep := Vector2.INF) -> Array[Vector2]:
	var me: Vector2 = ctx.me
	var raw: Array[Vector2] = [me]
	if keep != Vector2.INF:
		raw.append(keep)
	if ctx.get("objective", Vector2.INF) != Vector2.INF:
		raw.append(ctx.objective)
	var tgt := target_of(ctx)
	if not tgt.is_empty():
		var tp: Vector2 = tgt.pos
		var bearing := (me - tp).angle() if me.distance_to(tp) > 1.0 else 0.0
		for i in 5:   # round the target at the wanted range, biased to the side we are on
			var a := bearing + rng.randf_range(-1.6, 1.6)
			raw.append(tp + Vector2.from_angle(a) * float(ctx.ideal) * rng.randf_range(0.85, 1.1))
		if ctx.get("assassin", false):
			raw.append(tp - (tgt.aim as Vector2).normalized() * 60.0)   # its back
	var hold: Vector2 = ctx.get("hold_at", Vector2.INF)
	if hold != Vector2.INF:
		raw.append(hold)
		for i in 3:
			raw.append(hold + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * float(ctx.hold_r) * 0.8)
	while raw.size() < SAMPLES:   # and round ourselves
		raw.append(me + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, 260.0))
	var out: Array[Vector2] = []
	var avoid: Vector2 = ctx.get("avoid", Vector2.INF)
	for p in raw:
		if standable(map, p) and (hold == Vector2.INF or p.distance_to(hold) <= float(ctx.hold_r)) \
				and (avoid == Vector2.INF or p.distance_to(avoid) >= WorldMap.NAV_CELL * 1.5):
			out.append(p)
	return out

static func standable(map: WorldMap, p: Vector2) -> bool:
	if map.nav:
		return map.nav_open(map.nav_cell(p))
	return not map.off_ground(p)

static func target_of(ctx: Dictionary) -> Dictionary:
	for f: Dictionary in ctx.get("foes", []):
		if f.get("target", false):
			return f
	return {}

## Average score of standing at `spot` over ROLLOUTS random futures. Higher is better.
static func score(map: WorldMap, ctx: Dictionary, spot: Vector2, rng: RandomNumberGenerator) -> float:
	var me: Vector2 = ctx.me
	var hp: float = ctx.get("hp_frac", 1.0)
	var speed: float = maxf(ctx.get("speed", 260.0), 1.0)
	var walk := map.nav_travel_length(me, spot, float(ctx.get("dash_px", 0.0)))
	if not is_finite(walk):
		return -INF
	var travel := walk / speed
	var base := -W_TRAVEL * travel - W_SHORE * shore_risk(map, spot)
	var obj: Vector2 = ctx.get("objective", Vector2.INF)
	if obj != Vector2.INF:
		base += float(ctx.get("objective_w", 1.0)) * (1.0 - clampf(spot.distance_to(obj) / 900.0, 0.0, 1.0))
	var total := 0.0
	for r in ROLLOUTS:
		total += _rollout(map, ctx, spot, hp, rng)
	return base + total / ROLLOUTS

static func _rollout(map: WorldMap, ctx: Dictionary, spot: Vector2, hp: float, rng: RandomNumberGenerator) -> float:
	var s := 0.0
	var fear: float = (1.0 + (1.0 - hp) * 1.5) * float(ctx.get("fear", 1.0))   # hurt bots weigh danger far more; the state scales it
	for f: Dictionary in ctx.get("foes", []):
		var fp: Vector2 = f.pos
		var drift := (spot - fp).normalized() if spot.distance_to(fp) > 1.0 else Vector2.ZERO
		fp += (f.vel as Vector2) * HORIZON * rng.randf_range(0.3, 1.0) + drift * 120.0 * rng.randf_range(0.0, 0.8) \
			+ Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-50.0, 50.0))
		var d := spot.distance_to(fp)
		var reach: float = f.get("reach", 150.0) + 40.0
		if d < reach:
			s -= W_DANGER * fear * (1.0 - d / reach)
		if d < 450.0 and ringout_line(map, fp, spot):
			s -= W_RINGOUT * fear * (1.0 - d / 450.0)
		if f.get("target", false):
			var off := absf(d - float(ctx.get("ideal", 100.0)))
			s += W_RANGE * (1.0 - clampf(off / 250.0, 0.0, 1.0))
			if ctx.get("ranged", false) and clear_shot(map, spot, fp):
				s += W_LOS
			if ctx.get("assassin", false) and (f.aim as Vector2).dot((spot - fp).normalized()) < -0.3:
				s += W_BEHIND
			if d < float(ctx.get("ideal", 100.0)) + 200.0 and ringout_line(map, spot, fp):
				s += W_SETUP   # our hit from here would knock the target into the water: herd them to the edge
	return s

## True if a hit from `from` would knock someone at `spot` into water (it flies straight away from the hitter).
static func ringout_line(map: WorldMap, from: Vector2, spot: Vector2) -> bool:
	var away := (spot - from).normalized() if spot.distance_to(from) > 1.0 else Vector2.ZERO
	if away == Vector2.ZERO:
		return false
	for reach in [80.0, 160.0, 240.0, 320.0, 400.0]:   # every 80 px: the moat is ~115 px wide, a coarser step could skip it
		if map.is_water(spot + Vector2(0, 14) + away * reach):
			return true
	return false

## 0..1: how much of the ground right round `spot` is water.
static func shore_risk(map: WorldMap, spot: Vector2) -> float:
	var wet := 0
	for k in 8:
		if map.is_water(spot + Vector2(0, 14) + Vector2.from_angle(k * TAU / 8.0) * 70.0):
			wet += 1
	return wet / 8.0

## Shots fly over water and rails; only the cover (braziers, rocks) blocks them.
static func clear_shot(map: WorldMap, a: Vector2, b: Vector2) -> bool:
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1.0)
	for c in map.cover:
		var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < map.cover_r + 10.0:
			return false
	return true

## The best spot: the highest average score, keeping `keep` unless something beats it by KEEP_MARGIN.
static func best(map: WorldMap, ctx: Dictionary, rng: RandomNumberGenerator, keep := Vector2.INF) -> Vector2:
	var best_p: Vector2 = ctx.me
	var best_s := -INF
	var keep_s := -INF
	for p in candidates(map, ctx, rng, keep):
		var sc := score(map, ctx, p, rng)
		if keep != Vector2.INF and p == keep:
			keep_s = sc
		if sc > best_s:
			best_s = sc
			best_p = p
	if keep != Vector2.INF and keep_s > -INF and keep_s >= best_s - KEEP_MARGIN:
		return keep
	return best_p
