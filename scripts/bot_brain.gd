class_name BotBrain extends RefCounted
## The "keyboard" of a bot. A Player with `ai` set asks think() every physics frame and reads the same four things a human
## gives it: move, aim_pos, which of the two skill slots (basic, signature) are held, a dash press (plus an emote). Everything else (cooldowns, casting,
## damage) is the normal Player code, so a bot plays by exactly the same rules.
##
## What it does, in priority order:
##  1. Survive the edge: if a slide (knock) will end in the water, dash back; if already over water, dash for land.
##  2. Dodge: sidestep or dash out of incoming projectiles and unexploded blasts, and keep clear of hot-potato carriers.
##  3. Hot potato: when carrying it, run at the nearest victim and dash in to hand it over.
##  4. Pickups: go for healing when hurt and for power-ups when they are close; avoid the chicken and potato pickups.
##  5. Fight: pick a target (wounded, close, crowned, not a giant), hold the spacing the hero is built for (melee closes in,
##     ranged keeps back and strafes; the rogue circles to its back and hit-and-runs), lead its shots, fire only through clear lines
##     (cover blocks bolts), and use the hero's signature the way it is meant: charge to pin, blink behind, zone a pickup, snipe.
## `skill` (0..1) scales reaction time, aim error and how often it dodges, through `_sharp` (skill squared) so Easy and
## Normal are beatable by a newcomer while Hard stays close to the old curve. Rocks are steered around, and a bot that stops
## making progress backs off sideways and dashes. On the Colosseum they walk a nav grid (WorldMap.nav_step) round the
## moat, pools and rails, and when knocked toward water they head for the nearest dry ground, not the middle.
## WHAT it is doing is a small state machine (next_state: Roam, Engage, Retreat, Objective, Hold, Potato; urgent ones
## switch at once, the rest hold MIN_STATE_TIME); each state sets how brave the tactics are (STATE_FEAR).
## Where to stand in a fight is BotTactics' job (Monte Carlo position search: sample spots, roll each out a short way,
## score danger, ring-out lines, range, objective); a rail in the way of a long detour gets hopped with a dash. The crown
## holder (Crown mode) keeps to the centre circle.

const REACT_SLOW := 0.35      ## seconds between decisions at skill 0 (fast pace: was 0.42)
const REACT_FAST := 0.07      ## ... at skill 1
const EDGE_PROBE := 130.0     ## px: how far ahead the bot looks for water
const EDGE_FAR := 330.0       ## px: a softer, earlier nudge toward the middle
const DASH_DISTANCE := Player.DASH_SPEED * Player.DASH_TIME
const PICKUP_VALUE := {"heal": 1.0, "damage": 1.6, "speed": 0.9, "mystery": 1.1, "giant": 1.4, "chicken": -1.0, "bomb": -1.0,
	"shield": 1.0, "ult": 1.1, "reset": 1.3, "warcry": 1.5}
const CHANNEL_STAND := 22.0   ## px: this close to a drop the bot stops and channels (Player.can_channel wants no input)
const MIN_ULT_HIT := 0.50
const MIN_FINISHING_ULT_HIT := 0.38
const MIN_METEOR_HIT := 0.58
const STALK_NOTICE_DISTANCE := 180.0   ## the faint Stalk shimmer is easy to miss at the edge of visibility
const CHASE_PROGRESS := 32.0
const CHASE_RECONSIDER := 2.0

# --- what Player reads
var move := Vector2.ZERO
var aim_pos := Vector2.ZERO
var held: Array[bool] = [false, false, false]   ## per Player.SLOTS: basic, skill, ult
var skill := 0.6
var _sharp := 0.36   ## skill squared: the reaction / aim / dodge curves (Normal 0.6 -> 0.36, Hard 0.9 -> 0.81)

enum DashPriority { NONE, TACTICAL, DODGE, RESCUE }
var _dash_priority := DashPriority.NONE
var _emote := -1
var _emote_age := 0.0

var _p: Player
var _arena: Node              ## the match: _pickups and _map
var _map: WorldMap
var _target: Player
var _steer := Vector2.ZERO
var _aim_goal := Vector2.ZERO
var _charge_target: Player
var _charge_aim_error := 0.0
var _dash_dir := Vector2.ZERO
var _orbit := 1.0
var _react := 0.0
var _retarget := 0.0
var _last_seen := Vector2.INF
var _search_t := 0.0
var _chase_gap := INF
var _chase_t := 0.0
var _passed_target: Player
var _reconsider_t := 0.0
var _orbit_t := 0.0
var _burst_t := 0.0
var _bursting := true
var _dash_cd := 0.0
var _mark_pos := Vector2.INF
var _mark_goal := Vector2.INF
var _mark_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := Vector2.ZERO
var _rescue_ok := true
var _spot := Vector2.INF      ## where the tactical layer (BotTactics) wants us to stand; INF = not chosen yet
var _plan_t := 0.0            ## seconds until the next Monte Carlo plan
var _hop_t := 0.0             ## seconds until the next rail-hop check
var _rng := RandomNumberGenerator.new()
var _objective: Node2D
var _last_goal := Vector2.INF
var _route_goal := Vector2.INF
var _route: PackedVector2Array
var _waypoint := 0
var _blocked_goal := Vector2.INF
var _blocked_t := 0.0
const PLAN_EVERY := 0.2       ## re-plan the spot this often (between plans the bot keeps walking to it)

# --- the state machine: WHAT the bot is doing (BotTactics then decides WHERE to stand while doing it)
enum State { ROAM, ENGAGE, RETREAT, OBJECTIVE, HOLD, POTATO }
const STATE_NAMES := ["Roam", "Engage", "Retreat", "Objective", "Hold", "Potato"]
const STATE_COLORS := [Color(0.75, 0.75, 0.75), Color(1.0, 0.45, 0.35), Color(0.5, 0.8, 1.0), Color(1.0, 0.85, 0.3), Color(1.0, 0.7, 0.2), Color(1.0, 0.3, 0.6)]
const STATE_FEAR := [1.0, 0.7, 1.6, 0.6, 1.0, 0.5]   ## BotTactics' danger / ring-out weight per state
const MIN_STATE_TIME := 0.6   ## seconds a state holds before a non-urgent change (no flicker)
const RETREAT_HP := 0.3       ## below this, with a foe close: retreat
const RECOVER_HP := 0.5       ## ... until back above this, or nobody is near
var state: State = State.ROAM
var _state_t := 0.0

# --- personality: each bot gets one at setup, so a solo lobby has a brawler, a careful one and a looter
enum Mood { AGGRO, CAUTIOUS, LOOTER }
const MOOD_NAMES := ["Aggro", "Cautious", "Looter"]
const MOOD_FEAR := [0.7, 1.4, 1.0]        ## x BotTactics' danger weight
const MOOD_RETREAT := [0.18, 0.45, 0.3]   ## HP fraction that sends it into Retreat
const MOOD_LOOT := [0.7, 1.0, 1.7]        ## x how much drops and the crown are worth
const MOOD_DASH := [1.3, 0.8, 1.0]        ## x how readily it dashes
const MOOD_SEARCH := [1.2, 0.45, 0.0]      ## seconds to check the last sighting
const MOOD_CHASE := [3.0, 1.5, 2.0]        ## seconds without closing the gap before breaking pursuit
const MOOD_PUNISH := [1.0, 0.65, 0.35]    ## willingness to commit after noticing a baited dash
var mood: Mood = Mood.AGGRO

enum Bait { NONE, BASIC, WATCH, PUNISH }
const NO_BAIT_SLOT := -2
const BAIT_DASH_MEMORY := 5.0
const BAIT_BASIC_WINDOW := 0.4
const BAIT_RETRY := 2.5
const BAIT_PUNISH_WINDOW := 0.75
var _bait := Bait.NONE
var _bait_target: Player
var _bait_t := 0.0
var _bait_retry := 0.0
var _dash_cue_target: Player
var _dash_cue_active := false
var _dash_cue_age := INF

# --- habits: what the bots have learned about each foe this match (shared by every bot: they compare notes).
## peer_id -> {"shots": n, "dodged": n, "dashes": [msec, ...]}. A foe that dashes away right after being shot at gets
## baited: the cheap basic goes first, the big skill waits until its dashes are spent.
static var habits := {}
const DODGE_WINDOW := 0.5     ## a dash this soon after we shot at it counts as a reaction
const DASH_PX_S := 1000.0     ## faster than this = a dash (bots read puppets' eased velocity too)
var _shot_at := {}            ## peer_id -> msec we last shot at it (to see whether it reacts)
var _seen_dash := {}          ## peer_id -> msec we last saw it dash (one dash, one record)

func setup(player: Player, arena: Node, level: float) -> void:
	_p = player
	_arena = arena
	_map = arena._map
	skill = clampf(level, 0.0, 1.0)
	_sharp = skill * skill
	mood = [Mood.AGGRO, Mood.CAUTIOUS, Mood.LOOTER][player.peer_id % 3] as Mood   # consecutive bot ids: a mix every lobby
	_orbit = 1.0 if randf() < 0.5 else -1.0
	_react = randf() * 0.3   # bots do not all think on the same frame

# --- Player-facing API

func take_dash() -> bool:
	if _dash_priority == DashPriority.NONE:
		return false
	if _dash_priority != DashPriority.RESCUE:
		_dash_cd = 1.2
	_dash_priority = DashPriority.NONE
	_route_goal = Vector2.INF
	_hop_t = 0.4
	return true

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

func reset_intent() -> void:
	move = Vector2.ZERO
	aim_pos = _p.global_position
	_aim_goal = aim_pos
	held.fill(false)
	_dash_priority = DashPriority.NONE
	_steer = Vector2.ZERO
	_target = null
	_charge_target = null
	_team_peel = null
	_react = 0.0
	_retarget = 0.0
	_last_seen = Vector2.INF
	_search_t = 0.0
	_chase_gap = INF
	_chase_t = 0.0
	_passed_target = null
	_reconsider_t = 0.0
	_dash_cd = 0.0
	_blocked_t = 0.0
	_bait_retry = 0.0
	_dash_cue_target = null
	_clear_bait()
	_begin_state(State.ROAM)

# --- the loop

func think(delta: float) -> void:
	if _p.down:
		return
	_dash_priority = DashPriority.NONE
	_emote_age += delta
	if _emote_age > 2.0:
		_emote = -1
	_retarget -= delta
	if _search_t > 0.0:
		_search_t = maxf(_search_t - delta, 0.0)
		if _search_t == 0.0:
			_react = 0.0   # stop walking toward the last sighting as soon as the search expires
	if _passed_target != null:
		_reconsider_t -= delta
		if _reconsider_t <= 0.0:
			_passed_target = null
	_orbit_t -= delta
	_burst_t -= delta
	_dash_cd -= delta
	_react -= delta
	_unstick_t -= delta
	_plan_t -= delta
	_hop_t -= delta
	_state_t += delta
	_blocked_t -= delta
	_mark_t += delta
	if _orbit_t <= 0.0:
		_orbit = -_orbit if randf() < 0.6 else _orbit
		_orbit_t = randf_range(1.0, 2.6)
	if _burst_t <= 0.0:   # fire in bursts, then reposition, like a person tapping the button
		_bursting = not _bursting
		_burst_t = randf_range(0.5, 0.9) if _bursting else randf_range(0.15, 0.35)
	# Player reads held attacks every physics tick, including between decisions.
	if _target != null or (holding() and _p._charge_slot < 0):
		if not _valid_foe(_target) or _target.has_bomb:
			_search_t = 0.0
			_drop_target()
		elif not can_see_foe(_target):
			_search_t = MOOD_SEARCH[mood] if state == State.ENGAGE and _last_seen.is_finite() else 0.0
			_drop_target()
		else:
			_check_chase(delta)
	_tick_bait(delta)
	if _react <= 0.0 or (state == State.OBJECTIVE and not _objective_valid()):
		_react = (lerpf(REACT_SLOW, REACT_FAST, _sharp) + 0.18 * _mistake_weight()) * randf_range(0.75, 1.25)
		_decide()
	if _p._charge_slot >= 0:
		_continue_charge()
	move = _steer
	aim_pos = _aim_goal
	_safety()
	if _dash_priority != DashPriority.NONE:
		move = _dash_dir   # Player uses this frame's move as the dash direction

# --- thinking

func _drop_target() -> void:
	_target = null
	_team_peel = null
	_retarget = 0.0
	_react = 0.0
	_spot = Vector2.INF
	_route_goal = Vector2.INF
	_unstick_t = 0.0
	_chase_gap = INF
	_chase_t = 0.0
	held.fill(false)

func _check_chase(delta: float) -> void:
	var gap := _p.global_position.distance_to(_target.global_position)
	if state != State.ENGAGE or gap <= _p.hero.attack_range + CHASE_PROGRESS:
		_chase_gap = INF
		_chase_t = 0.0
		return
	if gap <= _chase_gap - CHASE_PROGRESS:
		_chase_gap = gap
		_chase_t = 0.0
		return
	_chase_t += delta
	if _chase_t >= MOOD_CHASE[mood]:
		_passed_target = _target
		_reconsider_t = CHASE_RECONSIDER
		_search_t = 0.0
		_drop_target()

func _decide() -> void:
	var me := _p.global_position
	var foes := _foes()
	_observe(foes)
	_pick_target(foes, me)
	var hp_frac := float(_p.hp) / maxf(_p.max_hp, 1.0)
	var want := Vector2.ZERO
	var tpos := _target.global_position if _target else me
	if _target:
		_last_seen = tpos
		_search_t = 0.0
	var dist := me.distance_to(tpos)

	# what are we doing? (the state machine), then how
	var pickup := _best_pickup(me, hp_frac)
	_set_state(next_state(state, _state_t, {"has_bomb": _p.has_bomb, "holding_crown": _holding_crown(),
		"has_target": _target != null, "hp_frac": hp_frac, "target_dist": dist, "retreat_hp": MOOD_RETREAT[mood],
		"has_objective_goal": pickup.item != null,
		"objective": pickup.pos != Vector2.INF and (_target == null or pickup.score > 1.3 or dist > 500.0)}))
	_last_goal = Vector2.INF
	match state:
		State.POTATO:   # hand the hot potato to the nearest victim
			var victim := _nearest(foes, me, true)
			if victim:
				want = _go(me, victim.global_position)
				if me.distance_to(victim.global_position) > 110.0 and me.distance_to(victim.global_position) < 330.0:
					_try_dash(want, 0.8)
		State.OBJECTIVE:   # the free crown or a drop worth the walk
			_objective = pickup.item
			want = _go(me, pickup.pos)
		State.ENGAGE, State.HOLD:
			want = _tactical(me, tpos, dist, foes, hp_frac)
		State.RETREAT:   # out of reach, toward a heal if there is one; the tactics weigh danger x1.6 here
			var heal := _heal_pickup(me)
			if heal != Vector2.INF:
				want = _go(me, heal)
			else:
				want = _tactical(me, tpos, dist, foes, hp_frac) * 0.6 + _dir(tpos, me) * 0.8
			if dist < 150.0:
				_try_dash(_dir(tpos, me), 0.7)
		State.ROAM:
			if _target:
				want = _go(me, tpos)
			elif _search_t > 0.0 and me.distance_to(_last_seen) > CHANNEL_STAND and not _goal_blocked(_last_seen):
				want = _go(me, _last_seen)
			else:
				_search_t = 0.0
				if me.distance_to(_map.spawn_point) > 250.0:
					want = _go(me, _map.spawn_point)

	want += _repulsion(me, foes)
	var edge := _edge_push(me, EDGE_PROBE)
	if _map.nav:
		# The grid already keeps the route off the water and round rails and braziers, and the tactics weigh ring-out
		# lines; the old island pushes (2.5x away from any water in reach) would pin bots in the bridges and the sand
		# strips. Keep a light nudge, and never against the way we are walking.
		var path_dir := want.normalized() if want.length() > 0.05 else Vector2.ZERO
		var nudge := edge * 0.8 + _knock_line(me, foes) * 0.5
		if path_dir != Vector2.ZERO and nudge.dot(path_dir) < 0.0:
			nudge -= path_dir * nudge.dot(path_dir)
		want += nudge + _dodge(me) * 2.0
		want = want.normalized() if want.length() > 0.05 else Vector2.ZERO
	else:
		want += edge * 2.5 + _edge_push(me, EDGE_FAR) * 0.9 + _knock_line(me, foes) * 1.3
		want += _dodge(me) * 2.5
		want = _around_cover(want.normalized() if want.length() > 0.05 else Vector2.ZERO, me)

	# on the drop: stand still and hold fire so the channel runs (a foe in reach breaks it anyway, see Player.take_damage)
	if state == State.OBJECTIVE and _objective is PvpPickup and _objective.channel_time > 0.0 and me.distance_to(pickup.pos) < CHANNEL_STAND:
		_steer = Vector2.ZERO
		_unstick_t = 0.0
		_mark_t = 0.0
		if _dash_priority == DashPriority.TACTICAL:
			_dash_priority = DashPriority.NONE
		_p.cancel_charge()
		held.fill(false)
		return

	if _check_progress(me, want):
		want = Vector2.ZERO
	_steer = (_unstick_dir if _unstick_t > 0.0 else want).limit_length(1.0)

	_attack(me, tpos, dist, edge)

func _objective_valid() -> bool:
	if not is_instance_valid(_objective) or _objective.is_queued_for_deletion():
		return false
	if _objective is CrownPickup:
		return _arena.get("_crown_obj") == _objective and _objective.grace <= 0.0
	return _arena._pickups.get(_objective.id) == _objective

## The tactical layer: walk to the spot BotTactics picked (Monte Carlo position search, re-planned every PLAN_EVERY),
## strafe a little once there, and keep the hero's own habits: a melee bot dashes in on a target with no dash left,
## an Assassin peels away between bursts.
func _tactical(me: Vector2, tpos: Vector2, dist: float, foes: Array[Player], hp_frac: float) -> Vector2:
	if state == State.HOLD:
		return _position_tactically(me, tpos, foes, hp_frac)
	if state == State.ENGAGE and _target and _p.hero.stalk and dist < 220.0:
		if _p.stalking() or _p.veiled():
			return _go(me, tpos) if dist > _p.hero.attack_range * 0.8 else Vector2.ZERO
		if _target.frozen():
			_bursting = true
		return _flank(me, tpos, dist, _dir(me, tpos))
	if _target and _disabled(_target) and dist < engage_range(_p.hero):   # combo window: it cannot answer, so close in and unload
		_bursting = true
		var basic := _p.spell_in(0)
		var projection := basic.range_projection() if basic else Vector2.ONE
		if _p.hero.attack_type == "melee" and ((tpos - me) / projection).length() > _p.hero.attack_range * 0.6:
			if dist > 200.0:
				_try_dash(_dir(me, tpos), 0.7)
			return _go(me, tpos)
	if _team_peel != null and is_instance_valid(_team_peel) and not _team_peel.down and _team_peel.hp < _team_peel.max_hp * 0.5:
		return _go(me, _team_peel.global_position)   # an ally is dying: get between it and its attacker
	if _p.hero.stalk and _target and _p._stalk_cd > 0.0 and _p._stalk_cd <= 0.45 and dist > 260.0 and dist < 520.0 and skill > 0.4:
		return _dir(me, tpos).orthogonal() * _orbit * 0.7 - _dir(me, tpos) * 0.2   # circle at the edge until faded, then dive
	if _target and dist > engage_range(_p.hero):   # far away: just go and get them (the planner is for the fight itself)
		_spot = Vector2.INF
		return _go(me, tpos)
	if _target and _p.hero.attack_type == "ranged" and _target.hero and _target.hero.attack_type == "melee" \
			and dist < _target.hero.attack_range + 40.0 and skill > 0.3:
		_try_dash(_dir(tpos, me) + _dir(me, tpos).orthogonal() * _orbit * 0.5, 0.6)   # a melee foe in its swing: dash out, keep kiting
	if _target and _target.dash_charges == 0 and _p.dash_charges > 1 and _p.hero.attack_type == "melee" and dist > 220.0 and dist < 420.0:
		_try_dash(_dir(me, tpos), 0.5)   # close the gap
	return _position_tactically(me, tpos, foes, hp_frac)

func _position_tactically(me: Vector2, tpos: Vector2, foes: Array[Player], hp_frac: float) -> Vector2:
	if _plan_t <= 0.0 or _spot == Vector2.INF:
		_plan_t = PLAN_EVERY * randf_range(0.8, 1.2)
		_spot = BotTactics.best(_map, tactics_ctx(me, foes, hp_frac), _rng, _spot)
	var arrival := 4.0 if state == State.HOLD and me.distance_to(_map.spawn_point) > _map.hold_radius() else 30.0
	if me.distance_to(_spot) < arrival:
		return _dir(me, tpos).orthogonal() * _orbit * 0.4 if _target and state != State.HOLD else Vector2.ZERO
	return _go(me, _spot)

## What BotTactics needs to know, from this bot's point of view.
func tactics_ctx(me: Vector2, foes: Array[Player], hp_frac: float) -> Dictionary:
	var list: Array = []
	for f in foes:
		if f != _target and me.distance_to(f.global_position) > 1100.0:
			continue   # far bystanders do not matter for where to stand; the target always does
		list.append({"pos": f.global_position, "vel": f.velocity, "aim": f.aim_dir, "reach": _threat_reach(f), "target": f == _target})
	var ranged := _p.hero.attack_type == "ranged"
	var ideal := _p.hero.attack_range * (0.62 if ranged else 0.6)
	var basic := _p.spell_in(0)
	if not ranged and basic and _target and _target.global_position != me:
		var toward := me.direction_to(_target.global_position)
		ideal /= (toward / basic.range_projection()).length()
	var ctx := {"me": me, "speed": _p.speed, "hp_frac": hp_frac, "ranged": ranged,
		"ideal": ideal,
		"dash_px": _shortcut_distance(), "avoid": _blocked_goal if _blocked_t > 0.0 else Vector2.INF,
		"assassin": _p.hero.archetype == "Assassin", "foes": list,
		"objective": Vector2.INF, "objective_w": 0.0, "hold_at": Vector2.INF, "hold_r": 0.0, "fear": STATE_FEAR[state] * MOOD_FEAR[mood]}
	var crown: CrownPickup = _arena.get("_crown_obj")
	if crown != null and crown.grace <= 0.0:
		ctx.objective = crown.global_position
		ctx.objective_w = 2.5 * MOOD_LOOT[mood]
	if _holding_crown():   # the king holds the centre: away from foes, off the moat's edge
		ctx.hold_at = _map.spawn_point
		ctx.hold_r = _map.hold_radius()
	return ctx

## Beyond this distance from its target a bot walks straight at it (on the nav route) instead of planning a spot:
## a ranged hero's reach plus a margin, a melee hero's a fixed approach ring.
static func engage_range(hero: Hero) -> float:
	if hero == null:
		return 500.0
	return hero.attack_range + 250.0 if hero.attack_type == "ranged" else 450.0

## How far a foe can hurt from: melee its reach plus a step, ranged its range (capped).
func _threat_reach(f: Player) -> float:
	if f.hero == null:
		return 150.0
	return f.hero.attack_range + 60.0 if f.hero.attack_type == "melee" else minf(f.hero.attack_range, 600.0)

## The state machine, as a pure function so it can be tested. Urgent states (Potato, Hold, Retreat) switch at once;
## the rest wait MIN_STATE_TIME. Retreat lasts until HP is back over RECOVER_HP or nobody is near (hysteresis).
## facts: has_bomb, holding_crown, has_target, hp_frac, target_dist, objective (a crown / pickup worth going for).
static func next_state(cur: int, time_in: float, facts: Dictionary) -> int:
	if facts.get("has_bomb", false):
		return State.POTATO
	if facts.get("holding_crown", false):
		return State.HOLD
	var hp: float = facts.get("hp_frac", 1.0)
	var near: bool = facts.get("has_target", false) and float(facts.get("target_dist", INF)) < 400.0
	if cur == State.RETREAT and hp < maxf(RECOVER_HP, float(facts.get("retreat_hp", RETREAT_HP)) + 0.15) and facts.get("has_target", false) and float(facts.get("target_dist", INF)) < 600.0:
		return State.RETREAT   # keep backing off until healthier or clear
	var retreat_hp: float = facts.get("retreat_hp", RETREAT_HP)
	if hp < retreat_hp and near:
		return State.RETREAT
	var want := State.ROAM
	if facts.get("objective", false):
		want = State.OBJECTIVE
	elif facts.get("has_target", false):
		want = State.ENGAGE
	var lost_goal: bool = (cur == State.OBJECTIVE and not facts.get("has_objective_goal", facts.get("objective", false))) \
		or (cur == State.ENGAGE and not facts.get("has_target", false))
	if want != cur and time_in < MIN_STATE_TIME and not lost_goal and cur != State.POTATO and cur != State.HOLD and cur != State.RETREAT:
		return cur   # not urgent: finish what we started
	return want

func _set_state(s: int) -> void:
	if s != state:
		_begin_state(s as State)

func _begin_state(next: State) -> void:
	if state == State.ENGAGE and next != State.ENGAGE:
		_clear_bait()
	state = next
	_state_t = 0.0
	_objective = null
	_spot = Vector2.INF
	_last_goal = Vector2.INF
	_route_goal = Vector2.INF
	_mark_pos = Vector2.INF
	_mark_goal = Vector2.INF
	_mark_t = 0.0
	_unstick_t = 0.0

func state_name() -> String:
	return "%s · %s" % [STATE_NAMES[state], MOOD_NAMES[mood]]

## The nearest heal drop, or INF.
func _heal_pickup(me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for pk: PvpPickup in _arena._pickups.values():
		if pk.kind != "heal" or pk.is_queued_for_deletion():
			continue
		var distance := _route_dist(me, pk.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pk.global_position
	return best

func _holding_crown() -> bool:
	return _p.crowned and _arena.get("_cm") == true

## The rogue: slip round to the target's back and stab, then peel away between bursts instead of trading blows.
func _flank(me: Vector2, tpos: Vector2, dist: float, to: Vector2) -> Vector2:
	if not _bursting and dist < 220.0:
		_try_dash(-to + to.orthogonal() * _orbit, 0.5)
		return -to * 0.8 + to.orthogonal() * _orbit * 0.6
	if dist <= _p.hero.attack_range * 0.8 and HeroBasic.Sweep.from_behind(_target, me):
		return Vector2.ZERO
	var back := tpos - _target.aim_dir * 55.0
	if dist < 130.0:   # close already: swing round behind rather than straight in
		return _dir(me, back) * 0.8 + to.orthogonal() * _orbit * 0.35 * (1.0 if _target.aim_dir.dot(to) > 0.0 else 0.0)
	return _go(me, back)

func _attack(me: Vector2, tpos: Vector2, dist: float, edge: Vector2) -> void:
	if _p._charge_slot >= 0:
		return
	held.fill(false)
	_charge_target = null
	var aim_from := me + Vector2(0, 8)
	_aim_goal = tpos if _target else me + (_steer if _steer.length() > 0.1 else Vector2.RIGHT) * 200.0
	if _target == null or _p.buffed("chicken") or _p.hexed() or _p.vanished() or _p.has_bomb or edge.length() > 0.6:
		return
	var los := _los_clear(aim_from, tpos)
	var bait := _should_bait(_target)
	var slot := _engage_attack(aim_from, tpos, dist, los, bait) if state == State.ENGAGE else _priority_attack(tpos, dist, los, bait)
	if slot >= 0:
		var s := _p.spell_in(slot)
		held[slot] = true
		_aim_goal = _aim_for(s, aim_from, tpos)
		if s.charge_time() > 0.0:
			_charge_target = _target
		if slot != Player.ULT_SLOT:
			_note_shot(_target)
	if _bait == Bait.NONE and not holding() and _p.spells.size() > 1 and _p.cooldowns[1] <= 0.04 and _p.spells[1] is EmberField:
		var deny := _contested_pickup(me)   # the mage zones a pickup a foe is about to take
		if deny != Vector2.INF:
			held[1] = true
			_aim_goal = deny
	var err := _rng.randfn(0.0, lerpf(0.2, 0.02, _sharp) + 0.18 * _mistake_weight())
	_charge_aim_error = err
	_aim_goal = aim_from + (_aim_goal - aim_from).rotated(err)

func _priority_attack(tpos: Vector2, dist: float, los: bool, bait: bool) -> int:
	if _p.ult_ready() and _p.spells[Player.ULT_SLOT].worth_casting(_p, tpos) and _ult_timing(dist):
		return Player.ULT_SLOT
	for slot in [1, 0]:
		if _fits_attack_slot(slot, tpos, dist, los, bait):
			return slot
	return -1

func _fits_attack_slot(slot: int, tpos: Vector2, dist: float, los: bool, bait: bool) -> bool:
	if slot >= _p.spells.size() or _p.cooldowns[slot] > 0.04:
		return false
	if slot == 0 and not _bursting and not (_p.spell_in(0) is HeroBasic and _p.hero.stalk and _rogue_stab_opening()):
		return false
	if slot == 1 and bait and dist > 160.0 and not _disabled(_target):
		return false   # draw out a reflex dash with the basic
	return _fits(_p.spell_in(slot), dist, los, tpos)

func _engage_attack(from: Vector2, tpos: Vector2, dist: float, los: bool, bait: bool) -> int:
	var planned := _bait_attack(from, tpos, dist, los, bait)
	if planned != NO_BAIT_SLOT:
		return planned
	var best_slot := -1
	var best_score := 0.0
	var mistake := _mistake_weight()
	var rush := mistake > 0.0 and _rng.randf() < 0.55 * mistake
	for slot in _p.spells.size():
		var spell := _p.spell_in(slot)
		if spell == null:
			continue
		if slot == Player.ULT_SLOT:
			if not _p.ult_ready() or _p.cooldowns[slot] > 0.04 or not _ult_timing(dist, false):
				continue
		elif not _fits_attack_slot(slot, tpos, dist, los, bait):
			continue
		var aim := _aim_for(spell, from, tpos)
		if slot == Player.ULT_SLOT and not spell.worth_casting(_p, aim):
			continue
		if not spell.can_cast(_p, aim):
			continue
		var score := _attack_utility(slot, spell, from, tpos, aim)
		if rush and score > 0.0:
			return slot   # commit to the first viable attack before spotting a better opening
		if score > best_score:
			best_score = score
			best_slot = slot
	return best_slot

func _bait_attack(from: Vector2, tpos: Vector2, dist: float, los: bool, learned_bait: bool) -> int:
	if _target == null:
		return NO_BAIT_SLOT
	if _bait_target != _target:
		_clear_bait()
	match _bait:
		Bait.WATCH:
			return -1
		Bait.PUNISH:
			return 1 if not _dash_cue_active and _bait_attack_fits(1, from, tpos, dist, los) else -1
		Bait.BASIC:
			if _bait_attack_fits(0, from, tpos, dist, los):
				return 0
			_clear_bait()
	if _bait_retry > 0.0 or _p.focus_firing() or _disabled(_target) or _dash_visible(_target):
		return NO_BAIT_SLOT
	var recent_dash := _dash_cue_target == _target and _dash_cue_age < BAIT_DASH_MEMORY
	if (learned_bait or recent_dash) and _bait_attack_fits(0, from, tpos, dist, los) and _bait_attack_fits(1, from, tpos, dist, los):
		_bait = Bait.BASIC
		_bait_target = _target
		_bait_t = BAIT_BASIC_WINDOW
		_bait_retry = BAIT_RETRY
		return 0
	return NO_BAIT_SLOT

func _bait_attack_fits(slot: int, from: Vector2, tpos: Vector2, dist: float, los: bool) -> bool:
	if not _fits_attack_slot(slot, tpos, dist, los, false) or _p.cooldowns[slot] > 0.0:
		return false
	var spell := _p.spell_in(slot)
	if spell == null or (slot == 1 and (_p.weapon_active(1) or spell is Riposte or spell is Tumble or spell is RubberBand or spell is ShadowStep)):
		return false
	var aim := _aim_for(spell, from, tpos)
	return spell.can_cast(_p, aim) and _attack_utility(slot, spell, from, tpos, aim) > 0.0

func _tick_bait(delta: float) -> void:
	_bait_retry -= delta
	if _bait != Bait.NONE:
		_bait_t -= delta
		if _bait_t <= 0.0 or _bait_target != _target or state != State.ENGAGE:
			_clear_bait()
			held.fill(false)
			_react = 0.0
	if _dash_cue_target != _target:
		_dash_cue_target = _target
		_dash_cue_age = INF
		_dash_cue_active = false
	_dash_cue_age += delta
	if _target == null or state != State.ENGAGE:
		_dash_cue_active = false
		return
	var dashing := _dash_visible(_target)
	var started := dashing and not _dash_cue_active
	_dash_cue_active = dashing
	if not started:
		return
	_dash_cue_age = 0.0
	if _bait == Bait.WATCH:
		if _rng.randf() < lerpf(0.15, 1.0, skill) and _rng.randf() < MOOD_PUNISH[mood]:
			_bait = Bait.PUNISH
			_bait_t = BAIT_PUNISH_WINDOW
		else:
			_clear_bait()
	elif _bait == Bait.PUNISH:
		held[1] = false   # a second dash can interrupt a punish queued between decisions

func _dash_visible(foe: Player) -> bool:
	if foe._puppet:
		return foe.velocity.length_squared() > DASH_PX_S * DASH_PX_S
	return foe._ghost and foe._dash_time > 0.0 and foe._dash_speed == Player.DASH_SPEED and foe._leap_settle_time <= 0.0

func on_spell_cast(slot: int) -> void:
	if _bait == Bait.BASIC and slot == 0:
		_bait = Bait.WATCH
		_bait_t = DODGE_WINDOW
		if is_instance_valid(_bait_target):
			_dash_cue_active = _dash_visible(_bait_target)
		held[0] = false
	elif _bait == Bait.PUNISH and slot == 1:
		_clear_bait()
		held[1] = false

func _clear_bait() -> void:
	_bait = Bait.NONE
	_bait_target = null
	_bait_t = 0.0

func _mistake_weight() -> float:
	var inexperience := 1.0 - clampf(skill / 0.9, 0.0, 1.0)
	return inexperience * inexperience

## Hit chance gates the payoff. Damage, combo timing and ring-outs each contribute in 0..1.
func _attack_utility(slot: int, spell: Spell, from: Vector2, pos: Vector2, aim: Vector2) -> float:
	var basic := spell as HeroBasic
	var step := basic.combo_step() if basic else 0
	var damage := roundi(basic.damage * basic.finisher_mult) if step == 2 else spell.damage
	if basic and basic.back_mult > 1.0 and _rogue_stab_opening():
		damage = roundi(damage * basic.back_mult)
	if spell is Assassinate:
		damage = Assassinate.shot_damage(damage, float(_target.hp) / maxf(_target.max_hp, 1.0))
	var speed := _projectile_speed(spell)
	var flight := maxf(from.distance_to(pos) - 28.0, 0.0) / speed if speed > 0.0 else 0.0
	var delay := _impact_delay(spell, from.distance_to(pos)) + flight
	var immobilized := maxf(maxf(_target._stun_left, _target._frozen_left), maxf(_target._rooted_left, _target._chrono_left))
	var free_time := maxf(delay - immobilized, 0.0)
	var predicted := pos + _target.velocity.limit_length(_target.speed) * free_time
	var hit := _attack_hit_chance(spell, from, pos, aim, predicted, delay, free_time, speed)
	if hit <= 0.0:
		return 0.0
	if slot == Player.ULT_SLOT:
		var minimum_hit := MIN_FINISHING_ULT_HIT if damage >= _target.hp else MIN_ULT_HIT
		# A low-health enemy can still leave Meteor's one-second telegraph before impact.
		if spell is Meteor:
			minimum_hit = MIN_METEOR_HIT
		if hit < minimum_hit:
			return 0.0
	var value := clampf(float(damage) / 42.0, 0.0, 1.0)
	if slot == Player.ULT_SLOT:
		value = maxf(value, 0.78)
	elif slot == 1:
		value = maxf(value, 0.46) # signatures can slow, stun or reposition as well as deal damage
	var combo := _attack_combo(spell, step, delay, immobilized)
	var ringout := _attack_ringout(spell, damage, step, from, predicted, aim)
	# A ring-out needs both the hit and the predicted launch angle. Discount it again on uncertain shots.
	return hit * (0.34 + 0.26 * value + 0.24 * combo + 0.16 * ringout * hit)

func _attack_hit_chance(spell: Spell, from: Vector2, pos: Vector2, aim: Vector2, predicted: Vector2, delay: float, free_time: float, speed: float) -> float:
	# These spells apply their effect to us. Enemy immunity is irrelevant to the cast itself.
	if spell is Tumble or spell is Riposte or spell is RubberBand or spell is GuardianAngel or spell is Fiendform \
			or spell is FocusFire or spell is SmokeScreen or spell is ShadowStep:
		return 1.0
	var protected_until := maxf(_target._spin_left, _target._phase_left)
	if not (spell is Stillwake or spell is ConnectionLost):
		protected_until = maxf(protected_until, maxf(_target._angel_left, _target._lives_guard))
		protected_until = maxf(protected_until, _target._parry_left)
		if not _target._puppet:
			protected_until = maxf(protected_until, _target._iframes)
	if protected_until > delay:
		return 0.0
	if speed > 0.0 and not (spell is HammerThrow or spell is ReboundShield or spell is FsWeapon and not spell.needs_los) \
			and not _los_clear(from, aim):
		return 0.0   # even a clear line to the target can be blocked along the lead
	var lateral := absf(_target.velocity.cross(from.direction_to(pos)))
	var mobility := clampf(lateral / maxf(_target.speed, 1.0), 0.0, 1.0)
	var exposure := 0.50 + 0.95 * mobility
	if speed > 0.0 and _target.dash_charges > 0:
		exposure += 0.20
	if spell is HeroBasic and spell.mode == "arc":
		var reach := ((predicted - from) / spell.range_projection()).length()
		if reach > spell.radius + 20.0:
			return 0.0
		exposure += smoothstep(spell.radius * 0.75, spell.radius + 20.0, reach)
	if spell is PowerShot and from.distance_to(predicted) > PowerShot.reach_at(1.0) + 28.0:
		return 0.0
	return _attack_coverage(spell, predicted, aim) / (1.0 + free_time * exposure)

## Where a telegraphed area actually lands after the spell clamps its aim.
func _attack_coverage(spell: Spell, predicted: Vector2, aim: Vector2) -> float:
	var origin := _p.global_position
	var offset := predicted - aim
	var radius := 0.0
	if spell is EmberField:
		offset = predicted - origin - (aim - origin).limit_length(EmberField.MAX_RANGE)
		radius = EmberField.RADIUS
	elif spell is Meteor:
		offset = predicted - Meteor.spot(origin, aim)
		radius = Meteor.RADIUS
	elif spell is Judgement:
		offset = predicted - Judgement.landing(origin, aim, _map.off_ground)
		radius = Judgement.HIT_RADIUS
	elif spell is Stillwake:
		offset = (predicted - Stillwake.spot(origin, aim)) / ChaosFx.GROUND_SCALE
		radius = Stillwake.RADIUS
	elif spell is LightningBolt:
		offset = predicted - LightningBolt.spot(origin, aim)
		radius = LightningBolt.RADIUS
	elif spell is ArrowRain:
		offset = predicted - ArrowRain.spot(origin, aim)
		radius = ArrowRain.RADIUS
	elif spell is EbbAndFlow:
		var off := predicted - origin - Vector2(0, 8)
		var axis := origin.direction_to(aim).angle()
		var spoke := axis + snappedf(off.angle() - axis, TAU / EbbAndFlow.SPOKES)
		return 1.0 if EbbAndFlow.on_spoke(off, spoke, 0.0, EbbAndFlow.LENGTH) else 0.0
	if radius <= 0.0:
		return 1.0
	return 1.0 - smoothstep(radius * 0.6, radius + 14.0, offset.length())

func _attack_combo(spell: Spell, step: int, delay: float, immobilized: float) -> float:
	if spell is ShadowRush:
		return 0.9   # eligibility already requires a reachable backstab on the other side
	if spell is SmokeScreen:
		return 0.8 if _p.hp < _p.max_hp * 0.45 else 0.0
	if step == 2:
		return 1.0
	if step == 1:
		return 0.45
	if spell is EbbAndFlow and _target._weak_left > delay:
		return 1.0
	var ult := _p.spell_in(Player.ULT_SLOT)
	if spell is KeelSlam and ult is EbbAndFlow and _p.ult_ready() and _target._weak_left <= EbbAndFlow.OUT_TIME:
		return 1.0
	if spell is Stillwake:
		return 0.9 if _p.spell_in(1) is RiftBolt and _p.cooldowns[1] <= 1.0 and not _target.time_stopped() else 0.0
	if spell is Tumble:
		return 0.8 if _p._empowered_left <= 0.0 and _p.cooldowns[0] <= 0.25 else 0.0
	# Favor attacks that connect before a setup expires, with a larger reward for committing a signature or ult.
	return clampf((immobilized - delay) / 0.35, 0.0, 1.0) * (0.85 if spell.cooldown > 1.0 else 0.3)

func _impact_delay(spell: Spell, dist: float) -> float:
	if spell is HeroBasic:
		return spell.windup if spell.mode == "arc" else 0.0
	if spell is PowerShot:
		return spell.charge_time() / _p.draw_rate()
	if spell is SnipeShot:
		return SnipeShot.CHARGE
	if spell is Assassinate:
		return Assassinate.AIM
	if spell is ShieldCharge:
		return minf(dist / ShieldCharge.SPEED, ShieldCharge.TIME)
	if spell is EbbAndFlow:
		return minf(dist / EbbAndFlow.LENGTH, 1.0) * EbbAndFlow.OUT_TIME
	if spell is EmberField:
		return EmberField.DELAY
	if spell is Meteor:
		return Meteor.DELAY
	if spell is Judgement:
		return Judgement.LEAP
	if spell is ArrowRain:
		return ArrowRain.DELAY
	if spell is LightningBolt:
		return LightningBolt.DELAY
	if spell is FaultLine:
		return FaultLine.delay()
	return 0.0

## Use each launch's direction and slide distance. Ordinary basics flinch, so they get no ring-out credit.
func _attack_ringout(spell: Spell, damage: int, step: int, from: Vector2, pos: Vector2, aim: Vector2) -> float:
	var dir := from.direction_to(pos)
	var extra := 0.0
	if spell is HeroBasic:
		if spell.pull > 0.0:
			return _water_along_launch(pos, -dir, spell.pull)
		if spell.mode != "arc" or step != 2:
			return 0.0
		extra = HeroBasic.FINISHER_SHOVE
	elif spell is PowerShot:
		extra = PowerShot.shove_at(1.0)
	elif spell is SnipeShot:
		extra = SnipeShot.SHOVE
	elif spell is EbbAndFlow:
		extra = EbbAndFlow.OUT_SHOVE
	elif spell is ShieldCharge:
		extra = ShieldCharge.SHOVE
	elif spell is Hook:
		dir = -dir
		extra = sqrt(2.0 * Player.KNOCK_DECEL * maxf(from.distance_to(pos) - Hook.STOP, 0.0))
	elif spell is Meteor:
		var launch := Meteor.launch(pos - Meteor.spot(_p.global_position, aim))
		dir = launch.normalized()
		extra = launch.length()
	elif spell is Judgement:
		var landing := Judgement.landing(_p.global_position, aim, _map.off_ground)
		dir = landing.direction_to(pos) if landing.distance_squared_to(pos) > 1.0 else Vector2.RIGHT
		extra = Judgement.SHOVE
	elif spell is EmberField or spell is LightningBolt:
		dir = aim.direction_to(pos)
	elif spell is HammerThrow or spell is DaggerThrow or spell is StiflingDagger or spell is FanOfKnives \
			or spell is Purification or spell is ArrowRain or spell is FsWeapon or damage <= 0:
		return 0.0
	var health_after := float(_target.hp - damage) / maxf(_target.max_hp, 1.0)
	var launch_speed := Player.knock_for(damage, health_after) * _target.form_knock(_p) + extra
	if launch_speed < Player.KNOCK_SHORE_MIN:
		return 0.0
	return _water_along_launch(pos, dir, launch_speed * launch_speed / (2.0 * Player.KNOCK_DECEL))

func _water_along_launch(pos: Vector2, dir: Vector2, distance: float) -> float:
	if dir == Vector2.ZERO or distance <= 0.0:
		return 0.0
	var feet := pos + Vector2(0, 14)
	var steps := ceili(distance / 24.0)
	for i in range(1, steps + 1):
		var at := feet + dir * minf(i * 24.0, distance)
		if _map.is_water(at):
			if not _los_clear(feet, at):
				return 0.0
			for rail in _map.rails:
				if Geometry2D.segment_intersects_segment(feet, at, rail[0], rail[1]) != null:
					return 0.0
			return 1.0
	return 0.0

## Keep the draw committed while it has a shot. Releasing the input fires, so a lost shot must cancel explicitly.
func _continue_charge() -> void:
	var slot := _p._charge_slot
	var spell := _p.spell_in(slot)
	held.fill(false)
	if not can_see_foe(_charge_target) or _charge_target.has_bomb or _charge_target == _passed_target or spell == null \
			or _p.buffed("chicken") or _p.hexed() or _p.vanished() or _p.has_bomb:
		_p.cancel_charge()
		return
	var from := _p.global_position + Vector2(0, 8)
	var target := _charge_target.global_position
	var distance := from.distance_to(target)
	if not _los_clear(from, target) or (spell is PowerShot and distance > PowerShot.reach_at(1.0)):
		_p.cancel_charge()
		return
	held[slot] = true
	var aim := target
	if spell is PowerShot and distance < 180.0 and _p.charge_show >= 0.65:
		held[slot] = false   # loose a useful charge before the foe closes into melee
	if spell is PowerShot:
		var velocity := _lead_velocity(_charge_target)
		aim = lead(from, target, velocity, PowerShot.speed_at(1.0 if held[slot] else _p.charge_show))
	_aim_goal = from + (aim - from).rotated(_charge_aim_error)

## When to spend the ult, on top of the spell's own worth_casting: a damage-window ult (Demon Form, Focus Volley,
## Connection Lost, Ravaging Tide) waits until the target is in our own reach and not already nearly dead (no wasted
## window on a kill the basic finishes), unless we are low ourselves and it is now or never. Easy bots sit on it longer.
func _ult_timing(dist: float, hesitate := true) -> bool:
	var hp_frac := float(_p.hp) / maxf(_p.max_hp, 1.0)
	var u: Spell = _p.spells[Player.ULT_SLOT]
	if u is SmokeScreen:
		var smoke_reach := SmokeScreen.RADIUS + 55.0 if hp_frac < 0.45 else _p.hero.attack_range + 55.0
		return not _p.veiled() and dist <= smoke_reach
	if hp_frac < 0.3:
		return true   # use it or lose it
	if u is EbbAndFlow and _target and (_target.weakened() or _disabled(_target)):
		return true   # combo: Anchor Slam (weaken) / a stun, then the tide
	if u is Stillwake and _p.cooldowns[1] > 1.0:
		return false   # combo: keep the Time Sphere until Chaos Blast is ready to follow it
	if u is Fiendform or u is FocusFire or u is ConnectionLost or u is EbbAndFlow:
		if dist > _p.hero.attack_range * 1.1 + (60.0 if _p.hero.attack_type == "melee" else 0.0):
			return false
		if _target and float(_target.hp) / maxf(_target.max_hp, 1.0) < 0.2:
			return false
	return not hesitate or randf() < lerpf(0.35, 1.0, skill)

## Does this skill make sense at this range? Bolts need a clear line, blasts and arcs do not.
func _fits(s: Spell, dist: float, los: bool, tpos := Vector2.INF) -> bool:
	if s is FsWeapon:
		return dist >= s.min_range and dist <= s.max_range and (los or not s.needs_los)
	if s is Hook:
		return dist > 130.0 and dist < Hook.RANGE - 40.0 and los   # drag in whoever is out of bonk reach
	var hb := s as HeroBasic
	if hb:
		if hb.mode == "arc":
			var projected_dist := dist
			if hb.chaos_cleave_fx and tpos != Vector2.INF:
				projected_dist = ChaosFx.ground_distance(tpos - _p.global_position - Vector2(0, 8))
			return projected_dist < hb.radius + 6.0
		return dist < hb.bolt_speed * hb.bolt_life * 0.92 and los
	if s is EmberField:
		return dist < EmberField.MAX_RANGE - 20.0 and (dist > 70.0 or _p.hp < _p.max_hp)
	if s is ChainLightning:
		return dist < _p.hero.attack_range - 10.0
	if s is Purification:   # heal and burn: when hurt with someone close, or to finish a brawl
		return dist < Purification.RADIUS - 10.0 and _p.hp < _p.max_hp * 0.85
	if s is Riposte:   # brace when a foe is in its own striking distance
		return dist < 170.0
	if s is BallLightning:   # zip in to start, or out when hurt (the move goal already points away then)
		return (dist > 180.0 and dist < BallLightning.RANGE) or (_p.hp < _p.max_hp * 0.35 and dist < 200.0)
	if s is Tumble:   # roll when something is close: the empowered shot follows
		return dist < 260.0
	if s is DaggerThrow:
		return dist < s.range_px - 20.0 and los
	if s is HammerThrow:   # in its lane, out or back
		return dist < s.range_px - 10.0
	if s is FanOfKnives:   # point blank most knives land on one foe
		return dist < 260.0 and los
	if s is StiflingDagger:   # throw it at a runner, then close in
		return dist > 120.0 and dist < StiflingDagger.RANGE - 20.0 and los
	if s is LightningBolt:
		return dist < LightningBolt.MAX_RANGE - 20.0
	if s is ArrowRain:   # the Scout's RMB
		return dist < ArrowRain.MAX_RANGE - 20.0
	if s is SnipeShot:
		return dist > 260.0 and dist < 1000.0 and los
	if s is PowerShot:
		return dist > 180.0 and dist < PowerShot.reach_at(1.0) - 80.0 and los
	if s is PacketLoss:   # it finds its own way after the lag
		return dist < s.range_px - 20.0
	if s is SixSeven:   # blink in next to a foe so the yell catches it, or blink out (stunning the chaser) when hurt
		return (dist > 120.0 and dist < SixSeven.RANGE + SixSeven.RADIUS * 0.6) or (_p.hp < _p.max_hp * 0.35 and dist < SixSeven.RADIUS)
	if s is RubberBand:   # anchor before diving in, or when hurt (it pulls him back out)
		return dist < 300.0 and _p.hp < _p.max_hp * 0.6
	if s is ReboundShield:   # best with a second foe close enough for a bounce, fine on one
		return dist > 90.0 and dist < ReboundShield.RANGE - 30.0
	if s is KeelSlam:
		return dist < KeelSlam.RADIUS - 10.0
	if s is WildOrb:   # dive onto a foe, or out when hurt (the move goal already points away then)
		return (dist > 160.0 and dist < WildOrb.RANGE) or (_p.hp < _p.max_hp * 0.3 and dist < 220.0)
	if s is MirrorTorment:
		return dist < MirrorTorment.MAX_RANGE - 20.0
	if s is RiftBolt:
		return dist < RiftBolt.RANGE - 30.0 and los
	if s is Cluckcurse:
		return dist < Cluckcurse.RANGE - 30.0 and los
	if s is ShieldCharge:
		# close the gap and stun, or (better) pin a foe that stands with a rock behind it
		return dist > 110.0 and dist < (330.0 if _backed_by_edge(tpos, _dir(_p.global_position, tpos)) else 215.0) and los
	if s is ShadowStep:
		return dist > 170.0 and dist < ShadowStep.MAX_RANGE - 30.0
	if s is ShadowRush:
		# rush through a foe that is looking at us: we land at its frozen back. Facing away already: just walk up and stab
		return _target != null and dist > _p.hero.attack_range and dist < ShadowRush.RANGE and tpos.is_finite() and _rush_sets_up_stab(tpos)
	return false

func _rogue_stab_opening() -> bool:
	return _target != null and (_p.stalking() or _p.veiled() or HeroBasic.Sweep.from_behind(_target, _p.global_position))

func _rush_sets_up_stab(tpos: Vector2) -> bool:
	var from := _p.global_position
	var dir := from.direction_to(tpos)
	var visible: Array[Node2D] = []
	visible.assign(_foes())
	var intended := from + dir * ShadowRush.length_along(from, dir, visible)
	if _map.off_ground(intended + Vector2(0, 14)):
		return false
	var landing := _p.blink_target(intended)
	return landing.distance_to(tpos) <= _p.hero.attack_range and HeroBasic.Sweep.from_behind(_target, landing) \
		and _target in ShadowRush.hits(from, landing, visible)

## Water or a rock within a launch's reach behind `pos`, seen from `dir`.
func _backed_by_edge(pos: Vector2, dir: Vector2) -> bool:
	if pos == Vector2.INF:
		return false
	for reach in [140.0, 280.0, 420.0]:
		if _map.is_water(pos + Vector2(0, 14) + dir * reach):
			return true
	return not _los_clear(pos, pos + dir * 140.0)

## A pickup a foe is closer to than we are, but still within reach of an Ember Field. INF if none.
func _contested_pickup(me: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for pk: PvpPickup in _arena._pickups.values():
		if pk.kind == "chicken" or pk.kind == "bomb":
			continue
		var d := me.distance_to(pk.global_position)
		if d > EmberField.MAX_RANGE - 30.0 or d >= best_d:
			continue
		for f in _foes():
			if f.global_position.distance_to(pk.global_position) < 230.0 and f.global_position.distance_to(pk.global_position) < d:
				best = pk.global_position
				best_d = d
				break
	return best

## Where to aim: ahead of a moving target for slow shots, and at where it will be for delayed blasts.
func _aim_for(s: Spell, from: Vector2, tpos: Vector2) -> Vector2:
	var vel := _lead_velocity(_target)
	if s is SmokeScreen:
		return _p.global_position.lerp(tpos, 0.5)
	if s is EmberField:
		return tpos + (vel * EmberField.DELAY).limit_length(170.0)
	if s is Meteor:
		return tpos + (vel * Meteor.DELAY * 0.6).limit_length(Meteor.RADIUS * 0.8)   # half-lead: they will try to walk out
	if s is SnipeShot:
		return tpos + (vel * (SnipeShot.CHARGE + 0.1)).limit_length(300.0)   # the line is locked when the charge starts
	if s is ArrowRain:
		return tpos + (vel * ArrowRain.DELAY).limit_length(120.0)
	if s is LightningBolt:
		return tpos + (vel * LightningBolt.DELAY).limit_length(120.0)
	if s is ShadowStep or s is ShadowRush:
		return tpos
	if s is Tumble:   # roll away from the threat; the empowered shot goes back at it
		return from + (from - tpos).normalized() * Tumble.ROLL
	if s is BallLightning and _p.hp < _p.max_hp * 0.35:
		return from + (from - tpos).normalized() * BallLightning.RANGE   # hurt: it is the escape
	if s is SixSeven and _p.hp < _p.max_hp * 0.35 and from.distance_to(tpos) < SixSeven.RADIUS:
		return from + (from - tpos).normalized() * SixSeven.RANGE   # the yell stuns them on the way out
	if s is WildOrb and _p.hp < _p.max_hp * 0.3:
		return from + (from - tpos).normalized() * WildOrb.RANGE   # hurt: it is the escape
	if s is FaultLine or s is MirrorTorment:
		return tpos + (vel * 0.8).limit_length(120.0)
	var speed := _projectile_speed(s)
	return lead(from, tpos, vel, speed) if speed > 0.0 else tpos

func _lead_velocity(foe: Player) -> Vector2:
	return foe.velocity * smoothstep(0.15, 0.85, skill)

func _projectile_speed(s: Spell) -> float:
	if s is Hook:
		return Hook.SPEED
	if s is RiftBolt:
		return RiftBolt.SPEED
	if s is Cluckcurse:
		return Cluckcurse.SPEED
	if s is ReboundShield:
		return ReboundShield.SPEED
	if s is DaggerThrow:
		return DaggerThrow.SPEED
	if s is HammerThrow:
		return HammerThrow.OUT_SPEED
	if s is FanOfKnives:
		return FanOfKnives.SPEED
	if s is PowerShot:
		return PowerShot.speed_at(1.0)
	if s is SnipeShot:
		return SnipeShot.SPEED
	if s is FsWeapon:
		return s.lead_speed
	var hb := s as HeroBasic
	return hb.bolt_speed if hb and hb.mode == "bolt" else 0.0

## Intercept point for a shot of `speed` at a target moving with `vel`.
static func lead(from: Vector2, pos: Vector2, vel: Vector2, speed: float) -> Vector2:
	var t := from.distance_to(pos) / maxf(speed, 1.0)
	for i in 2:
		t = from.distance_to(pos + vel * t) / maxf(speed, 1.0)
	return pos + (vel * t).limit_length(220.0)

func _pick_target(foes: Array[Player], me: Vector2) -> void:
	if _retarget > 0.0 and is_instance_valid(_target) and not _target.down and not _target.has_bomb and _target in foes:
		return
	_retarget = 0.7
	_team_peel = null
	var finish_range := engage_range(_p.hero)
	var best: Player = null
	var best_s := -INF
	for f in foes:
		if f.has_bomb or f == _passed_target:
			continue
		var d := _route_dist(me, f.global_position)
		if not is_finite(d):
			continue
		var wounded := 1.0 - float(f.hp) / maxf(f.max_hp, 1.0)
		var finish_chance := 1.0 - smoothstep(finish_range, finish_range + 250.0, d)
		var s := 900.0 / (d + 120.0) + wounded * 3.0 * finish_chance
		if f.crowned:
			s += 2.5   # a bounty
		if f.buffed("giant"):
			s -= 1.5
		if f == _target:
			s += 1.0
		if _p.team >= 0:
			s += 1.0 * _hunters(f)   # team modes: focus the same foe
			s += 2.5 if _threatens_ally(f) else 0.0   # peel: the foe hitting a hurt teammate
		else:
			s -= 0.9 * _hunters(f)   # free-for-all: spread out, the bots do not all pile on the human
		if _disabled(f):
			s += 1.5   # stunned / hexed / frozen: punish it
		if f.hp < f.max_hp * 0.4 and _busy(f):
			s += 1.2 * finish_chance   # third party: a hurt foe locked in someone else's fight is a cheap kill
		if f.guarded() or f.time_stopped():
			s -= 1.5   # immune right now (Guardian Grace, Blade Spin) or frozen in a Time Sphere: not worth the walk
		if s > best_s:
			best_s = s
			best = f
	if _target != best:
		_chase_gap = INF
		_chase_t = 0.0
		_spot = Vector2.INF
	_target = best

## Can `f` not fight back right now? (A combo window: stunned, frozen, hexed, held in a Time Sphere, rooted.)
static func _disabled(f: Player) -> bool:
	return f.stunned() or f.frozen() or f.hexed() or f.time_stopped() or f.rooted()

var _team_peel: Player = null   ## team modes: a hurt ally to stand beside (set by _threatens_ally), else null

## Team modes: is `f` beating on a teammate of ours that is below 40% HP? Remembers that teammate for the peel.
func _threatens_ally(f: Player) -> bool:
	for o in _p.get_tree().get_nodes_in_group("players"):
		var a := o as Player
		if a and a != _p and not a.down and a.team == _p.team and a.hp < a.max_hp * 0.4 \
				and a.global_position.distance_to(f.global_position) < 220.0 and _p.global_position.distance_to(a.global_position) < 600.0:
			_team_peel = a if _p.hero.max_hp >= 120 else null   # only the sturdy ones body-block; the rest just shoot the attacker
			return true
	return false

# --- habits

## Watch every foe for dashes, and score them as reactions when they come right after one of our shots.
func _observe(foes: Array[Player]) -> void:
	var now := Time.get_ticks_msec()
	for f in foes:
		if f.ai != null:
			continue   # only humans have habits worth learning
		var id := f.peer_id
		if f.velocity.length() > DASH_PX_S and now - int(_seen_dash.get(id, 0)) > 400:
			_seen_dash[id] = now
			var h: Dictionary = habits.get(id, {"shots": 0, "dodged": 0, "dashes": []})
			h.dashes.append(now)
			h.dashes = h.dashes.filter(func(t: int) -> bool: return now - t < 10000)   # only recent ones matter
			if now - int(_shot_at.get(id, -100000)) < DODGE_WINDOW * 1000.0:
				h.dodged += 1
			habits[id] = h

## Remember that we just shot at `f` (a reaction dash within DODGE_WINDOW counts as a dodge).
func _note_shot(f: Player) -> void:
	if f == null or f.ai != null:
		return
	_shot_at[f.peer_id] = Time.get_ticks_msec()
	var h: Dictionary = habits.get(f.peer_id, {"shots": 0, "dodged": 0, "dashes": []})
	h.shots += 1
	habits[f.peer_id] = h

## Does `f` answer our shots with a dash, and does it still have one? Then hold the big skill and bait with the basic.
## Its charges are not replicated, so they are estimated from the dashes we saw (Player.MAX_DASH, DASH_RECHARGE).
func _should_bait(f: Player) -> bool:
	if f == null or f.ai != null or skill < 0.5:
		return false
	var h: Dictionary = habits.get(f.peer_id, {})
	if h.is_empty() or int(h.shots) < 4 or float(h.dodged) / float(h.shots) < 0.35:
		return false
	var now := Time.get_ticks_msec()
	var recent := 0
	for t: int in h.dashes:
		if now - t < Player.DASH_RECHARGE * 1000.0:
			recent += 1
	return recent < Player.MAX_DASH   # it still has a dash in hand: wait

## True when `f` is fighting someone else right now (another player close to it, not us).
func _busy(f: Player) -> bool:
	for o in _p.get_tree().get_nodes_in_group("players"):
		var q := o as Player
		if q and q != _p and q != f and not q.down and q.global_position.distance_to(f.global_position) < 260.0:
			return true
	return false

## How many other bots are already after `f`.
func _hunters(f: Player) -> int:
	var n := 0
	for o in _p.get_tree().get_nodes_in_group("players"):
		var b := o as Player
		if b and b != _p and b.ai and not b.down and b.ai._target == f:
			n += 1
	return n

func _route_dist(me: Vector2, pos: Vector2) -> float:
	if _goal_blocked(pos):
		return INF
	return _map.nav_travel_length(me, pos, _shortcut_distance())

func _goal_blocked(pos: Vector2) -> bool:
	return _blocked_t > 0.0 and pos.distance_to(_blocked_goal) < WorldMap.NAV_CELL * 1.5

func _foes() -> Array[Player]:
	var out: Array[Player] = []
	for n in _p.get_tree().get_nodes_in_group("players"):
		var f := n as Player
		if can_see_foe(f):
			out.append(f)
	return out

func _valid_foe(f: Player) -> bool:
	return is_instance_valid(f) and f != _p and f.is_inside_tree() and not f.is_queued_for_deletion() \
		and not f.down and not (_p.team >= 0 and f.team == _p.team)

func can_see_foe(f: Player) -> bool:
	return _valid_foe(f) and not f.vanished() and not f.hidden_from(_p) and (not f.stalking() \
		or _p.sees_hidden(f) or _p.global_position.distance_squared_to(f.global_position) <= STALK_NOTICE_DISTANCE * STALK_NOTICE_DISTANCE)

func _nearest(foes: Array[Player], me: Vector2, without_bomb: bool) -> Player:
	var best: Player = null
	var best_distance := INF
	for f in foes:
		if without_bomb and f.has_bomb:
			continue
		var distance := _route_dist(me, f.global_position)
		if not is_finite(distance):
			continue
		if best == null or distance < best_distance:
			best_distance = distance
			best = f
	return best

## The reachable pickup with the highest score.
func _best_pickup(me: Vector2, hp_frac: float) -> Dictionary:
	var best := {"item": null, "pos": Vector2.INF, "score": 0.0}
	if _p.has_bomb or _p.buffed("chicken"):
		return best
	var crown: CrownPickup = _arena.get("_crown_obj")   # Crown mode: a free crown is the objective, worth more than any drop
	if is_instance_valid(crown) and not crown.is_queued_for_deletion() and crown.grace <= 0.0:
		var distance := _route_dist(me, crown.global_position)
		if is_finite(distance):
			best = {"item": crown, "pos": crown.global_position, "score": 1200.0 / (distance + 200.0)}
	for pk: PvpPickup in _arena._pickups.values():
		if pk.is_queued_for_deletion():
			continue
		var value: float = PICKUP_VALUE.get(pk.kind, 0.0)
		if PvpPickup.is_weapon(pk.kind):
			value = 0.9 + 0.5 * PvpPickup.tier_of(pk.kind)
		elif FsLoot.is_passive(pk.kind):
			value = 0.6 if _p.hero.passive_name != "" else 1.4   # already has one: a swap is worth less
		elif FsLoot.is_ult(pk.kind):
			value = 0.5 if _p.ult_ready() else 1.9
		if pk.kind == "heal":
			value = 0.15 if hp_frac > 0.9 else 1.0 + (1.0 - hp_frac) * 3.0
		if value <= 0.0:
			continue
		var score: float = value * MOOD_LOOT[mood] * 600.0 / (_route_dist(me, pk.global_position) + 200.0)
		if score > best.score:
			best = {"item": pk, "pos": pk.global_position, "score": score}
	return best

## Keep away from potato carriers, the bad pickups and blasts that have not gone off yet.
func _repulsion(me: Vector2, foes: Array[Player]) -> Vector2:
	var push := Vector2.ZERO
	if not _p.has_bomb:
		for f in foes:
			if f.has_bomb:
				var d := me.distance_to(f.global_position)
				if d < 330.0:
					push += _dir(f.global_position, me) * (1.6 + (330.0 - d) / 330.0)
					if d < 140.0:
						_try_dash(_dir(f.global_position, me).orthogonal() * (1.0 if randf() < 0.5 else -1.0) + _dir(f.global_position, me), 0.9, DashPriority.DODGE)
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
				_try_dash(_dir(e.global_position, me), 0.9, DashPriority.DODGE)
	for n in _p.get_tree().get_nodes_in_group("zones"):
		var z := n as Node2D
		if z == null or z.get("caster") == _p:
			continue
		if z.has_method("bot_avoid"):   # a zone that knows its own shape (a line, a trail, a big sphere)
			push += z.bot_avoid(me) * 2.2
		elif me.distance_to(z.global_position) < EmberField.RADIUS + 50.0:
			push += _dir(z.global_position, me) * 2.0
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
	for n in _p.get_tree().get_nodes_in_group("dodgeables"):   # kit shots that are not Projectiles (shield, hex, packet, orb)
		var nd := n as Node2D
		if nd == null or nd.get("caster") == _p:
			continue
		var v: Vector2 = nd.get("velocity")
		if v.length() < 1.0:
			continue
		var dv := v.normalized()
		var rel := me - nd.global_position
		var along := rel.dot(dv)
		if along < 0.0 or along > v.length() * worst_t:
			continue
		var lateral := rel - dv * along
		if lateral.length() < 48.0:
			worst_t = along / v.length()
			side = lateral.normalized() if lateral.length() > 2.0 else dv.orthogonal()
	if side == Vector2.ZERO or randf() > lerpf(0.1, 0.85, _sharp) * 1.4:   # Normal dodges ~52% of shots (was 83%)
		return Vector2.ZERO
	if worst_t < 0.3:
		_try_dash(side, 1.0, DashPriority.DODGE)
	return side

# --- geometry / safety

## Asks for a dash toward `dir` (never on cooldown and only sometimes, `chance` scaled by skill).
func _try_dash(dir: Vector2, chance: float, priority := DashPriority.TACTICAL) -> void:
	if priority <= _dash_priority or not _p.can_start_dash() or dir.length_squared() < 0.01:
		return
	if priority != DashPriority.RESCUE and (_dash_cd > 0.0 or randf() > chance * lerpf(0.4, 1.0, skill) * MOOD_DASH[mood]):
		return
	_dash_dir = dir.normalized()
	_dash_priority = priority

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
				push -= away * (1.0 - d / 700.0)   # step toward the hitter: a longer run of ground behind us, harder the closer it is
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
		if perp.length() < _map.cover_r + 36.0:
			var away := -perp.normalized() if perp.length() > 1.0 else dir.orthogonal()
			dir = (dir + away * 1.4).normalized()
	return dir

func _los_clear(a: Vector2, b: Vector2) -> bool:
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1.0)
	for c in _map.cover:
		var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < _map.cover_r + 10.0:
			return false
	return true

func _shortcut_distance() -> float:
	return DASH_DISTANCE if _p.can_start_dash() and _p.dash_charges > 1 and _dash_cd <= 0.0 else 0.0

## Follow the chosen route until the goal changes cells or a dash or stalled movement invalidates it.
func _go(me: Vector2, goal: Vector2) -> Vector2:
	if not goal.is_finite() or _goal_blocked(goal):
		return Vector2.ZERO
	_last_goal = goal
	if _map.nav == null or _map.nav_clear(me, goal):
		_route_goal = Vector2.INF
		return me.direction_to(goal) if me.distance_to(goal) > 1.0 else Vector2.ZERO
	var dash_px := _shortcut_distance()
	if _hop_t <= 0.0 and dash_px > 0.0:
		_hop_t = 0.4
		var hop := _map.dash_shortcut(me, goal, dash_px)
		if hop != Vector2.ZERO:
			_try_dash(hop, 0.9)
	if not _route_goal.is_finite() or _map.nav_cell(_route_goal) != _map.nav_cell(goal):
		_route_goal = goal
		_route = _map.nav_path(me, goal, false)
		_waypoint = 0
	if _route.is_empty():
		return Vector2.ZERO
	while _waypoint < _route.size() - 1 and me.distance_to(_route[_waypoint]) < WorldMap.NAV_CELL * 0.5:
		_waypoint += 1
	for i in range(mini(_waypoint + 5, _route.size() - 1), _waypoint, -1):
		if _map.nav_clear(me, _route[i]):
			_waypoint = i
			break
	return me.direction_to(_route[_waypoint]) if me.distance_to(_route[_waypoint]) > 4.0 else Vector2.ZERO

func _check_progress(me: Vector2, want: Vector2) -> bool:
	var following_goal := _last_goal.is_finite() and me.distance_to(_last_goal) > CHANNEL_STAND
	if _dash_priority != DashPriority.NONE or _p._dash_time > 0.0 or _p.stunned() or _p.frozen() or _p.rooted() \
			or (not following_goal and (_map.nav != null or want.length_squared() < 0.25)):
		_mark_pos = Vector2.INF
		return false
	if not _mark_pos.is_finite() or _mark_goal.is_finite() != _last_goal.is_finite() \
			or (_mark_goal.is_finite() and _mark_goal.distance_to(_last_goal) > WorldMap.NAV_CELL * 1.5):
		_mark_pos = me
		_mark_goal = _last_goal
		_mark_t = 0.0
		return false
	if _mark_t < 0.6:
		return false
	var stalled := me.distance_to(_mark_pos) < 18.0
	_mark_pos = me
	_mark_t = 0.0
	if not stalled:
		return false
	_spot = Vector2.INF
	if following_goal:
		_blocked_goal = _last_goal
		_blocked_t = 1.5
		_route_goal = Vector2.INF
		_retarget = 0.0
		return true
	_unstick_t = 0.8
	_unstick_dir = want.orthogonal() * _orbit
	_try_dash(_unstick_dir, 0.5)
	return false

func _dir(from: Vector2, to: Vector2) -> Vector2:
	return (to - from).normalized()

## Every frame: don't drown. A slide toward the water gets a dash back, and so does standing in it.
func _safety() -> void:
	var feet := _p.global_position + Vector2(0, 14)
	var slide_end := feet + _p.knock.normalized() * (_p.knock.length_squared() / (2.0 * Player.KNOCK_DECEL)) if _p.knock.length() > 150.0 else feet
	var wet := _map.is_water(feet)
	var sliding_into_water := _map.is_water(slide_end)
	var danger := wet or sliding_into_water or _map.is_water(feet + _p.velocity * 0.25)
	if not danger:
		_rescue_ok = randf() < lerpf(0.6, 1.0, skill)   # decided once per scare: an easy bot sometimes freezes
		return
	held.fill(false)
	_p.cancel_charge()
	_dash_priority = DashPriority.NONE
	if not _rescue_ok:
		return
	# Already wet: look for dry ground. Still on land: dash against the motion that would carry us off it.
	var to_land := _map.dry_dir(feet) if wet else (-feet.direction_to(slide_end) if sliding_into_water else -_p.velocity.normalized())
	if to_land == Vector2.ZERO:
		to_land = feet.direction_to(_map.spawn_point)
	move = to_land
	_try_dash(to_land, 1.0, DashPriority.RESCUE)
