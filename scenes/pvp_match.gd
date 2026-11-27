extends Node2D
## One online deathmatch on the fixed arena. Every peer builds the same scene from Net.roster; each owns its own Player.
## Kills are counted on every peer from the same reliable Player.fragged events; only the host decides when the match ends.

const CAM_ZOOM := 0.8             ## <1 = camera higher; at 0.8 a 1280x720 view shows 1600x900 px of the 2048x1472 arena
const PICKUP_EVERY := 15.0        ## Classic defaults (GameMode.CONFIG rules; these back the tests and the fallbacks)
const MAX_PICKUPS := 2
const PICKUP_SPAWN_CLEAR := 380.0 ## pickups never appear this close to a player spawn (the short axis of the spawn ring is only 544 px from the centre)
const PICKUP_COVER_CLEAR := 120.0
const PICKUP_APART := 300.0
const CROWN_MIN_KILLS := 3        ## the kill leader wears the crown from here on (needs a strict lead)
const CATCHUP_GAP := 6.0          ## Friendslop: kills behind the leader for the full catch-up bias
const CATCHUP_NEAR_CHANCE := 0.45 ## chance (at full bias) that a drop falls near the trailing player
const CATCHUP_MIN := 300.0
const CATCHUP_MAX := 600.0
const BOUNTY := 2                 ## kills toward the limit for killing the crown holder
const VERBS_HIT := ["bonked", "deleted", "humbled", "launched", "clapped", "sent to the shadow realm"]
const LINES_FALL := ["%s took a swim", "%s forgot how to walk", "%s tried to fly", "%s found the water"]
const LINES_BOMB := ["%s was blown up by the potato", "%s got the hot potato", "%s went out with a bang"]
const LINES_METEOR := ["%s looked up too late", "%s was flattened by a meteor", "%s caught a falling star"]
const LINES_REFLECT := ["%s cut himself on %s", "%s hit %s a little too hard", "%s bled out on %s's blademail"]

var _cfg := GameMode.cfg(GameMode.CLASSIC)   ## the mode's row (set in _ready from Net.mode)
var _kill_limit := 15
var _fs := false                            ## Friendslop
var _map: WorldMap
var _pickups := {}          ## id -> PvpPickup
var _next_pickup := 1
var _pickup_timer := PICKUP_EVERY / 2.0
var _players := {}          ## peer_id -> Player
var _kills := {}
var _deaths := {}
var _time_left := INF       ## seconds left, INF when the lobby turned the time limit off
var _tdm := false           ## team deathmatch (Net.settings.mode)
var _teams := {}            ## peer -> 0/1, only filled in a team match
var _team_seen := [0, 0]    ## players placed per team so far; picks each one's spawn point
var _running := false
var _over := false
var _winner := 0
var _banner: Label
var _board: MatchHud.Board
var _feed: MatchHud.KillFeed
var _match_menu: MatchOverlay
var _crown := 0             ## peer wearing the crown, 0 = nobody (Classic: the kill leader; Crown mode: whoever picked it up)
var _cm := false            ## Crown mode: the score is seconds worn, the crown is a pickup (see docs/design_pillars_and_crown_mode.md)
var _score := {}            ## Crown mode: peer -> points (a point per second worn, plus the bounty for killing the king)
var _crown_obj: CrownPickup ## Crown mode: the crown lying on the ground, null while somebody wears it (or before it appears)
var _crown_spawn_in := INF  ## host, Crown mode: seconds until the crown first appears
var _crown_free := 0.0      ## host, Crown mode: seconds the crown has lain unworn (it returns to the centre after crown_reset)
var _kill_count := 0        ## every death so far; picks the kill-feed wording the same way on every peer
var _stats := {}            ## peer -> {streak, best, falls, bombs, pickups, emotes, crown}
var _killed_by := {}        ## Vector2i(killer, victim) -> times
var _drops_open := false    ## host: the death gate (drop_after_deaths) has opened, drops fall from now on
var _event := MatchEvent.NONE   ## the match event (MatchEvent), rolled by the host at FIGHT and sent to every peer
var _meteor_timer := 0.0    ## host, Meteor Shower: seconds to the next strike
var _event_card: MatchHud.EventCard

## Kills per team from the per-peer kills; `teams` is peer -> 0/1.
static func team_totals(values: Dictionary, teams: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0]
	for id: int in values:
		if teams.has(id):
			out[teams[id]] += values[id]
	return out

## The winning team (0/1) by kills, then fewer deaths; -1 on a full tie.
static func leading_team(kills: Dictionary, deaths: Dictionary, teams: Dictionary) -> int:
	var k := team_totals(kills, teams)
	if k[0] != k[1]:
		return 0 if k[0] > k[1] else 1
	var d := team_totals(deaths, teams)
	if d[0] != d[1]:
		return 0 if d[0] < d[1] else 1
	return -1

## Spawn points a team uses: the ring split in two halves (all of them when there are no teams).
static func team_points(points: Array[Vector2], team: int) -> Array[Vector2]:
	if team < 0:
		return points
	var half := points.size() / 2
	return points.slice(0, half) if team == 0 else points.slice(half)

## The spawn point that is farthest from every living opponent (respawns land away from the fight).
static func farthest_spawn(points: Array[Vector2], others: Array[Vector2]) -> Vector2:
	var best := points[0]
	var best_d := -1.0
	for p in points:
		var d := INF
		for o in others:
			d = minf(d, p.distance_to(o))
		if d > best_d:
			best_d = d
			best = p
	return best

## The crown holder: the strict kill leader with at least CROWN_MIN_KILLS, else 0. `kills` is peer -> kills.
static func crown_holder(kills: Dictionary) -> int:
	var best := 0
	var best_k := 0
	var second := 0
	for id: int in kills:
		var k: int = kills[id]
		if k > best_k:
			second = best_k
			best_k = k
			best = id
		elif k > second:
			second = k
	return best if best_k >= CROWN_MIN_KILLS and best_k > second else 0

## One kill-feed line. `killer` is "" when nobody gets the credit; `n` picks the wording.
static func kill_line(cause: String, killer: String, victim: String, n: int) -> String:
	match cause:
		"fall":
			var text: String = LINES_FALL[n % LINES_FALL.size()] % victim
			return text if killer == "" else "%s (pushed by %s)" % [text, killer]
		"bomb":
			return LINES_BOMB[n % LINES_BOMB.size()] % victim
		"meteor":
			return LINES_METEOR[n % LINES_METEOR.size()] % victim
		"reflect":   # Blademail: the victim hit `killer` and bled for it
			return LINES_REFLECT[n % LINES_REFLECT.size()] % [victim, killer if killer != "" else "a blademail"]
	return "%s %s %s" % [killer, VERBS_HIT[n % VERBS_HIT.size()], victim]

static func new_stats() -> Dictionary:
	return {"streak": 0, "best": 0, "falls": 0, "bombs": 0, "pickups": 0, "emotes": 0, "crown": 0.0}

## The peer with the highest value[key] that reaches `minimum` (ties go to the lowest peer id), or 0.
static func _top(values: Dictionary, minimum: float) -> int:
	var best := 0
	for id: int in values:
		if values[id] >= minimum and (best == 0 or values[id] > values[best] or (values[id] == values[best] and id < best)):
			best = id
	return best

## End-of-match awards, at most 6: [{title, who, detail}]. stats: peer -> new_stats(); kills/deaths: peer -> int;
## killed_by: Vector2i(killer, victim) -> int; names: peer -> String. Only awards somebody actually earned.
static func awards(stats: Dictionary, kills: Dictionary, deaths: Dictionary, killed_by: Dictionary, names: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var by := func(key: String) -> Dictionary:
		var d := {}
		for id: int in stats:
			d[id] = stats[id][key]
		return d
	var add := func(title: String, id: int, detail: String) -> void:
		if id != 0:
			out.append({"title": title, "who": names.get(id, "?"), "detail": detail})
	var id := _top(kills, 1)
	add.call("Top Fragger", id, "%d kills" % kills.get(id, 0))
	id = _top(by.call("best"), 3)
	add.call("Killing Spree", id, "%d in a row" % stats.get(id, {}).get("best", 0))
	var pair := Vector2i.ZERO
	var pair_n := 2
	for k: Vector2i in killed_by:
		if killed_by[k] > pair_n or (killed_by[k] == pair_n and pair != Vector2i.ZERO and k.x < pair.x):
			pair = k
			pair_n = killed_by[k]
	if pair != Vector2i.ZERO:
		add.call("Nemesis", pair.x, "killed %s %d times" % [names.get(pair.y, "?"), pair_n])
	id = _top(by.call("crown"), 10.0)
	add.call("Long Live the King", id, "%d s on the throne" % int(stats.get(id, {}).get("crown", 0.0)))
	id = _top(deaths, 3)
	add.call("Punching Bag", id, "%d deaths" % deaths.get(id, 0))
	id = _top(by.call("falls"), 1)
	add.call("Aquaman", id, "%d swims" % stats.get(id, {}).get("falls", 0))
	id = _top(by.call("bombs"), 1)
	add.call("Well Done", id, "blown up %d times" % stats.get(id, {}).get("bombs", 0))
	id = _top(by.call("pickups"), 3)
	add.call("Hoarder", id, "%d pickups" % stats.get(id, {}).get("pickups", 0))
	id = _top(by.call("emotes"), 4)
	add.call("Chatterbox", id, "%d emotes" % stats.get(id, {}).get("emotes", 0))
	var top: Array[Dictionary] = []
	for i in mini(6, out.size()):
		top.append(out[i])
	return top

func _ready() -> void:
	_cfg = GameMode.cfg(Net.mode)
	_fs = GameMode.is_friendslop(Net.mode)
	_cm = GameMode.is_crown(Net.mode)
	_kill_limit = 0 if _cm else Net.settings.kill_limit   # the lobby's limits rule in every mode; Crown mode ends on points
	_pickup_timer = _cfg.first_pickup
	_drops_open = int(_cfg.drop_after_deaths) <= 0
	MatchEvent.current = MatchEvent.NONE
	_map = Arenas.create(Net.arena)   # the lobby's pick (docs/iso_level_editing.md)
	_map.name = "Arena"   # fixed names: RPC and replication paths must match on every peer
	add_child(_map)
	_map.generate_arena()
	_tdm = Net.is_team_mode()
	if Net.settings.time_limit > 0:
		_time_left = float(Net.settings.time_limit)

	var ids := Net.roster.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return Net.roster[a].slot < Net.roster[b].slot)
	for id: int in ids:
		_spawn(id, Net.roster[id])

	var cam := GameCamera.new()
	cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
	add_child(cam)
	var me: Player = _players.get(Net.local_id())
	if me:
		cam.target = me
		cam.global_position = me.global_position
		cam.reset_physics_interpolation()
		var hud := Hud.new()
		hud.with_sheet = false
		hud.online = true
		add_child(hud)
		hud.add_player(me)

	var ui := CanvasLayer.new()
	ui.layer = 10
	_board = MatchHud.Board.new()
	_board.arena = self
	ui.add_child(_board)
	var radar := Radar.new()
	radar.arena = self
	ui.add_child(radar)
	var arrows := DropArrows.new()
	arrows.player = me
	ui.add_child(arrows)
	_feed = MatchHud.KillFeed.new()
	ui.add_child(_feed)
	_event_card = MatchHud.EventCard.new()
	ui.add_child(_event_card)
	_banner = ArenaUi.heading("", 48)
	_banner.theme = ArenaUi.THEME
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.text = "Waiting for players..."
	ui.add_child(_banner)
	add_child(FogOverlay.new())   # the Fog event's mist (hidden unless Fog is on)
	ui.add_child(ChatBox.new())
	Net.chat_received.connect(func(line: Dictionary) -> void:
		var talker: Player = _players.get(line.peer)
		if talker:
			talker.say(line.text))
	_match_menu = MatchOverlay.new()
	_match_menu.pause_tree = Net.solo
	_match_menu.configure("Paused" if Net.solo else "Match Settings", Net.leave)
	ui.add_child(_match_menu)
	add_child(ui)

	_set_players_active(false)
	Net.match_go.connect(_on_go, CONNECT_ONE_SHOT)
	Net.player_left.connect(_on_player_left)
	Net.report_loaded()

func _spawn(id: int, info: Dictionary) -> void:
	var p := Player.new()
	p.name = str(id)
	p.online = true
	p.player_index = info.slot
	p.hero = Hero.by_id(_cfg.hero if _cfg.hero != "" else info.hero)
	p.display_name = info.name
	if _tdm:
		p.team = int(info.get("team", 0))
		p.friendly_fire = Net.settings.friendly_fire
		_teams[id] = p.team
		var pts := team_points(_map.spawn_points, p.team)
		p.position = pts[_team_seen[p.team] % pts.size()]
		_team_seen[p.team] += 1
	else:
		p.position = _map.spawn_points[info.slot % _map.spawn_points.size()]
	p.peer_id = id
	if info.get("bot", false):
		p.ai = BotBrain.new()
		p.ai.setup(p, self, info.get("skill", 0.6))   # a bot keeps the local peer's authority, so every RPC and hit runs here
	else:
		p.set_multiplayer_authority(id)
	p.respawn_point = _pick_spawn.bind(id)
	p.water_check = _map.is_water
	p.ground_check = _map.off_ground
	p.fragged.connect(_on_fragged)
	p.bomb_touch.connect(_on_bomb_touch.bind(p))
	_map.add_child(p)
	_players[id] = p
	_kills[id] = 0
	_deaths[id] = 0
	_score[id] = 0.0
	_stats[id] = new_stats()
	if _cm:
		p.crown_speed = _cfg.crown_speed
	p.emoted.connect(_on_emoted)

func _pick_spawn(id: int) -> Vector2:
	var others: Array[Vector2] = []
	for k: int in _players:
		if k != id and not _players[k].down and not (_tdm and _teams.get(k) == _teams.get(id)):
			others.append(_players[k].global_position)
	var team: int = _teams.get(id, -1)
	var pts := team_points(_map.spawn_points, team)
	return farthest_spawn(pts, others) if not others.is_empty() else pts[0]

func _set_players_active(on: bool) -> void:
	for p: Player in _players.values():
		p.set_physics_process(on)

func _on_go() -> void:
	_running = true
	_set_players_active(true)
	Sfx.play("fight")
	if _cm:
		_say("FIGHT!   the crown drops in %d s" % int(_cfg.crown_delay), 1.6)
		if multiplayer.is_server():
			_crown_spawn_in = _cfg.crown_delay
	else:
		_say("FIGHT!   grab the drops!" if _fs else ("FIGHT!   (1-4: emotes)" if Net.solo else "FIGHT!   (1-4: emotes, Enter: chat)"), 1.6)
	if multiplayer.is_server() and bool(_cfg.get("events", false)):
		_net_event.rpc(MatchEvent.roll(randf()))   # the host's dice; the rule itself is fixed (docs §6.4)

## The match event on every peer: the FIGHT card, the HUD chip (reads MatchEvent.current) and the host's timers.
@rpc("authority", "call_local", "reliable")
func _net_event(id: String) -> void:
	_event = id if MatchEvent.valid(id) else MatchEvent.NONE
	MatchEvent.current = _event
	_meteor_timer = MatchEvent.METEOR_EVERY
	if _event != MatchEvent.NONE:
		_event_card.show_event(_event)
		Sfx.play("crown", Vector2.INF, -2.0, 0.8)

func _on_fragged(victim: Player, killer_peer: int, cause: String) -> void:
	var vid := victim.peer_id
	if victim.ai:
		victim.ai.on_death(cause)
	var killer_player: Player = _players.get(killer_peer)
	if killer_player and killer_player.ai and killer_peer != vid:
		killer_player.ai.on_kill()
	if multiplayer.is_server() and victim.has_bomb:
		var killer: Player = _players.get(killer_peer)
		if killer != null and killer != victim and not killer.down and not killer.has_bomb:
			_net_bomb_move.rpc(vid, killer_peer, victim.bomb_left)   # revenge potato
		else:
			_net_bomb_boom.rpc(vid)
	_deaths[vid] = _deaths.get(vid, 0) + 1
	var vs: Dictionary = _stats[vid]
	vs.streak = 0
	if cause == "fall":
		vs.falls += 1
	elif cause == "bomb":
		vs.bombs += 1
	var credited := killer_peer != 0 and killer_peer != vid and _kills.has(killer_peer)
	var killer_name := _name_of(killer_peer) if credited else ""
	var line := kill_line(cause, killer_name, _name_of(vid), _kill_count)
	_kill_count += 1
	if multiplayer.is_server() and not _over:
		_on_death_for_drops()
	if credited:
		var reign := vid == _crown   # decided before the credit: killing the king pays a bounty
		if _cm:
			_kills[killer_peer] += 1   # kills stay on the board, but only the king's death pays points
			if reign:
				_score[killer_peer] = _score.get(killer_peer, 0.0) + float(_cfg.crown_bounty)
		else:
			_kills[killer_peer] += BOUNTY if reign else 1
		_killed_by[Vector2i(killer_peer, vid)] = _killed_by.get(Vector2i(killer_peer, vid), 0) + 1
		var ks: Dictionary = _stats[killer_peer]
		ks.streak += 1
		ks.best = maxi(ks.best, ks.streak)
		Sfx.play("kill")
		if reign:
			line += "   (+%d bounty!)" % (int(_cfg.crown_bounty) if _cm else BOUNTY)
			_say("%s ended %s's reign!" % [killer_name, _name_of(vid)], 1.8)
		var limit: int = _kill_limit
		if multiplayer.is_server() and limit > 0 and not _over:
			if _tdm:
				var totals := team_totals(_kills, _teams)
				if totals[0] >= limit or totals[1] >= limit:
					_end.rpc(killer_peer, 0 if totals[0] >= limit else 1)
			elif _kills[killer_peer] >= limit:
				_end.rpc(killer_peer, -1)
	_feed.add(line, _color_of(killer_peer if credited else vid))
	if _cm:
		if vid == _crown and multiplayer.is_server() and not _over:
			_net_crown.rpc(0, victim.global_position, _cfg.crown_grace)   # the crown falls where the king fell
	else:
		_update_crown()

## Every player for the results screen, best first: name, the hero they played (in its colour), K / D (and points in
## Crown mode), and whether they won.
func scoreboard(winner: int, win_team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in _players:
		var p: Player = _players[id]
		out.append({"name": _name_of(id), "hero": p.hero.display_name if p.hero else "?",
			"color": p.hero.basic_color if p.hero else ArenaUi.INK, "kills": int(_kills.get(id, 0)), "deaths": int(_deaths.get(id, 0)),
			"score": int(_score.get(id, 0.0)) if _cm else -1, "won": id == winner or (_tdm and win_team >= 0 and p.team == win_team),
			"me": id == Net.local_id()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.score != b.score:
			return a.score > b.score
		if a.kills != b.kills:
			return a.kills > b.kills
		return a.deaths < b.deaths)
	return out

func _name_of(id: int) -> String:
	var p: Player = _players.get(id)
	return p.display_name if p else str(Net.roster.get(id, {}).get("name", "?"))

func _color_of(id: int) -> Color:
	var p: Player = _players.get(id)
	if p and p.team >= 0:
		return Player.TEAM_COLORS[p.team]
	return Player.NAME_COLORS[p.player_index % Player.NAME_COLORS.size()] if p else Color.WHITE

## Recomputed from the replicated kill counts, so every peer agrees without extra messages.
func _update_crown() -> void:
	var present := {}   # a player who left cannot keep the crown
	for id: int in _kills:
		if _players.has(id):
			present[id] = _kills[id]
	var holder := crown_holder(present)
	if holder == _crown:
		return
	_crown = holder
	for id: int in _players:
		_players[id].crowned = id == _crown
	if _crown != 0:
		Sfx.play("crown")
		_say("%s took the crown!" % _name_of(_crown), 1.8)

func _on_emoted(p: Player) -> void:
	var id := p.peer_id
	if _stats.has(id):
		_stats[id].emotes += 1

func _on_player_left(id: int) -> void:
	var p: Player = _players.get(id)
	if p:
		if p.has_bomb and multiplayer.is_server():
			_net_bomb_boom.rpc(id)
		if _cm and id == _crown and multiplayer.is_server() and not _over:
			_net_crown.rpc(0, p.global_position, _cfg.crown_grace)   # a king who leaves drops the crown where he stood
		p.queue_free()
		_players.erase(id)
	if not multiplayer.is_server() or _over:
		return
	if _tdm:
		var alive := [0, 0]
		for k: int in _players:
			alive[_teams[k]] += 1
		if alive[0] == 0 or alive[1] == 0:
			_end.rpc(0, -1 if alive[0] == alive[1] else (0 if alive[1] == 0 else 1))
	elif _players.size() < 2:
		_end.rpc(_players.keys()[0] if not _players.is_empty() else 0, -1)

func _process(delta: float) -> void:
	if _running and not _over:
		_time_left = maxf(_time_left - delta, 0.0)
		if _crown != 0 and _stats.has(_crown):
			_stats[_crown].crown += delta
			if _cm:
				_score[_crown] = _score.get(_crown, 0.0) + delta   # every peer counts the same seconds; only the host calls the end
		if _cm and multiplayer.is_server():
			_tick_crown(delta)
		if _time_left <= 0.0 and multiplayer.is_server():
			if _cm:
				var top := _leader()
				_end.rpc(top, _teams.get(top, -1))
			elif _tdm:
				_end.rpc(0, leading_team(_kills, _deaths, _teams))
			else:
				_end.rpc(_leader(), -1)
		if multiplayer.is_server():
			for id: int in _players:
				var carrier: Player = _players[id]
				if carrier.has_bomb and carrier.bomb_left <= 0.0:
					_net_bomb_boom.rpc(id)
			if _drops_open:
				_pickup_timer -= delta
				if _pickup_timer <= 0.0:
					_pickup_timer = _cfg.pickup_every
					if _pickups.size() < _cfg.max_pickups:
						_host_drop()
			for pk: PvpPickup in _pickups.values():
				if pk.life > 0.0 and pk.life_left <= 0.0:
					_net_despawn_pickup.rpc(pk.id)   # the host's clock is the one that counts
					break
			if _event == MatchEvent.METEOR:
				_meteor_timer -= delta
				if _meteor_timer <= 0.0:
					_meteor_timer = MatchEvent.METEOR_EVERY
					var none: Array[Vector2] = []
					_net_meteor.rpc(pick_pickup_pos(_map, none, 0.0, 0.0))

## Host only, on every death: the drop gate (no drops until drop_after_deaths players have died) and the forced drop
## (one more every drop_per_deaths deaths after that). Kills pace the drops, not only the clock.
func _on_death_for_drops() -> void:
	var after := int(_cfg.drop_after_deaths)
	var per := int(_cfg.drop_per_deaths)
	if not _drops_open:
		if _kill_count >= after:
			_drops_open = true
			_pickup_timer = _cfg.first_pickup
		return
	if per > 0 and (_kill_count - after) % per == 0 and _pickups.size() < _cfg.max_pickups:
		_host_drop()
		_pickup_timer = _cfg.pickup_every

## Host only: rolls and places the next drop. Classic: the kinds of the Classic table; rares and epics on the centre circle
## when the mode says so; a drop sometimes falls near whoever is trailing (the catch-up: first option, never a better kind).
## Friendslop: any kind anywhere, and the catch-up also tilts the kind a tier up. Double Drop (event): the drop comes in a
## pair, on opposite sides of the centre. The kind and the position travel in the spawn RPC, so peers never touch the
## map's RNG or the dice.
func _host_drop() -> void:
	var taken: Array[Vector2] = []
	for pk: PvpPickup in _pickups.values():
		taken.append(pk.position)
	var kind: String
	var pos: Vector2
	var cu := catchup(_living_kills())
	var trailer: Player = _players.get(cu.peer)
	var near_trailer: bool = trailer != null and not trailer.down and randf() < CATCHUP_NEAR_CHANCE * float(cu.boost)
	if _fs:
		if near_trailer:
			kind = PvpPickup.roll_fs(randf(), cu.boost)
			pos = pick_pickup_pos_near(_map, taken, trailer.global_position, _cfg.spawn_clear, _cfg.apart)
		else:
			kind = PvpPickup.roll_fs(randf())
			pos = pick_pickup_pos(_map, taken, _cfg.spawn_clear, _cfg.apart)
	else:
		kind = PvpPickup.roll(randf())
		if bool(_cfg.get("centre_rares", false)) and PvpPickup.tier_of(kind) >= PvpPickup.Tier.RARE:
			pos = pick_pickup_pos_centre(_map, taken)
		elif near_trailer:
			pos = pick_pickup_pos_near(_map, taken, trailer.global_position)
		else:
			pos = pick_pickup_pos(_map, taken)
	_net_spawn_pickup.rpc(_next_pickup, kind, pos)
	if _event == MatchEvent.DOUBLE and _pickups.size() < _cfg.max_pickups:
		taken.append(pos)
		var mirror := _map.spawn_point * 2.0 - pos   # the other side of the centre
		var pos2 := mirror if _map.is_reachable(mirror) and not _map.is_water(mirror) and _clear_of(mirror, taken, _cfg.apart) else pick_pickup_pos(_map, taken, _cfg.spawn_clear, _cfg.apart)
		_net_spawn_pickup.rpc(_next_pickup, PvpPickup.roll(randf()), pos2)

## Meteor Shower (event): every peer shows the telegraph and runs the same blast; damage still lands on each victim's own peer.
@rpc("authority", "call_local", "reliable")
func _net_meteor(pos: Vector2) -> void:
	_map.add_child(Explosion.new().setup(pos, MatchEvent.METEOR_RADIUS, MatchEvent.METEOR_DAMAGE, MatchEvent.METEOR_DELAY, null).as_meteor())
	Sfx.play("crown", pos, -4.0, 0.6)   # the Mage's meteor toll: something is coming

func _living_kills() -> Dictionary:
	var out := {}
	for id: int in _kills:
		if _players.has(id):
			out[id] = _kills[id]
	return out

## The player who trails the leader: {peer, boost}. boost grows 0..1 with the kill gap (full at CATCHUP_GAP kills) and is 0
## when nobody is behind, with fewer than two players, or when the lowest score is shared. Ties for last: lowest peer id.
static func catchup(kills: Dictionary) -> Dictionary:
	if kills.size() < 2:
		return {"peer": 0, "boost": 0.0}
	var lo := 0
	var hi_k := -1
	for id: int in kills:
		hi_k = maxi(hi_k, kills[id])
		if lo == 0 or kills[id] < kills[lo] or (kills[id] == kills[lo] and id < lo):
			lo = id
	var gap: int = hi_k - kills[lo]
	return {"peer": lo if gap > 0 else 0, "boost": clampf(float(gap) / CATCHUP_GAP, 0.0, 1.0)}

## A spot on open ground: away from every player spawn, the cover and other pickups. Classic keeps the defaults (central drops).
static func pick_pickup_pos(map: WorldMap, taken: Array[Vector2], spawn_clear := PICKUP_SPAWN_CLEAR, apart := PICKUP_APART) -> Vector2:
	for i in 150:
		var p := map.random_open_point()
		if _clear_of(p, map.spawn_points, spawn_clear) and _clear_of(p, map.cover, PICKUP_COVER_CLEAR) and _clear_of(p, taken, apart):
			return p
	return map.spawn_point   # arena centre

## Like pick_pickup_pos, but between CATCHUP_MIN and CATCHUP_MAX px from `near` (falls back to any valid spot).
static func pick_pickup_pos_near(map: WorldMap, taken: Array[Vector2], near: Vector2, spawn_clear := PICKUP_SPAWN_CLEAR, apart := PICKUP_APART) -> Vector2:
	for i in 100:
		var p := map.random_open_point()
		var d := p.distance_to(near)
		if d >= CATCHUP_MIN and d <= CATCHUP_MAX and _clear_of(p, map.spawn_points, spawn_clear) and _clear_of(p, map.cover, PICKUP_COVER_CLEAR) and _clear_of(p, taken, apart):
			return p
	return pick_pickup_pos(map, taken, spawn_clear, apart)

## A spot on the centre circle (inside the map's hold radius), off the cover and other drops: where rares and epics fall,
## so the beam says "come to the fort". Falls back to any open spot.
static func pick_pickup_pos_centre(map: WorldMap, taken: Array[Vector2]) -> Vector2:
	var r := map.hold_radius() - 40.0
	for i in 150:
		var p := map.random_open_point()
		if p.distance_to(map.spawn_point) <= r and _clear_of(p, map.cover, PICKUP_COVER_CLEAR) and _clear_of(p, taken, 120.0):
			return p
	return map.spawn_point if _clear_of(map.spawn_point, taken, 60.0) else pick_pickup_pos(map, taken)

static func _clear_of(p: Vector2, points: Array[Vector2], dist: float) -> bool:
	for q in points:
		if p.distance_to(q) < dist:
			return false
	return true

@rpc("authority", "call_local", "reliable")
func _net_spawn_pickup(id: int, kind: String, pos: Vector2) -> void:
	var pk := PvpPickup.new()
	pk.name = "pk%d" % id
	pk.id = id
	pk.kind = kind
	pk.position = pos
	pk.channel_time = GameMode.channel_time(Net.mode, PvpPickup.tier_of(kind))
	pk.life = float(_cfg.get("pickup_life", 0.0))
	pk.touched.connect(_on_pickup_touched)
	_map.add_child(pk)
	_pickups[id] = pk
	_next_pickup = maxi(_next_pickup, id + 1)
	if PvpPickup.tier_of(kind) == PvpPickup.Tier.EPIC:
		_say("EPIC DROP!  %s" % PvpPickup.LABELS[kind], 2.2)
	else:
		_say("%s appeared!" % PvpPickup.LABELS[kind], 1.5)

## A drop nobody took in time: gone on every peer (the host's clock decides).
@rpc("authority", "call_local", "reliable")
func _net_despawn_pickup(id: int) -> void:
	var pk: PvpPickup = _pickups.get(id)
	if pk == null:
		return
	_pickups.erase(id)
	pk.queue_free()

func _on_pickup_touched(id: int, peer: int) -> void:
	_claim.rpc_id(1, id, peer)

## The host serialises claims: the first one for an id wins, later ones find it already gone.
@rpc("any_peer", "call_local", "reliable")
func _claim(id: int, taker: int) -> void:
	if not multiplayer.is_server() or not _pickups.has(id):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != taker and not Net.solo:
		return   # a peer can only claim for its own player (a solo match has the one peer claiming for its bots too)
	var outcome: String = _pickups[id].kind
	if outcome == "mystery":
		outcome = PvpPickup.mystery_outcome(randf(), _fs)   # the host rolls it so every peer sees the same result
	var p: Player = _players.get(taker)
	if outcome == "bomb" and (p == null or p.has_bomb):
		outcome = "damage"   # one potato per player
	_net_take.rpc(id, taker, outcome)

@rpc("authority", "call_local", "reliable")
func _net_take(id: int, peer: int, outcome: String) -> void:
	var pk: PvpPickup = _pickups.get(id)
	if pk == null:
		return
	_pickups.erase(id)
	pk.queue_free()
	Sfx.play("pickup", pk.position)
	if _stats.has(peer):
		_stats[peer].pickups += 1
	var p: Player = _players.get(peer)
	if p:
		if pk.kind == "mystery":
			p.float_text("Mystery box!", PvpPickup.COLORS["mystery"])
		p.apply_pickup(outcome)

# --- hot potato: touching another player passes it on; the host runs the fuse and decides when it blows

func _on_bomb_touch(other: Player, carrier: Player) -> void:
	_bomb_pass.rpc_id(1, carrier.peer_id, other.peer_id)

@rpc("any_peer", "call_local", "reliable")
func _bomb_pass(from_peer: int, to_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != from_peer and not Net.solo:
		return
	var a: Player = _players.get(from_peer)
	var b: Player = _players.get(to_peer)
	if a == null or b == null or not a.has_bomb or b.has_bomb or b.down:
		return
	_net_bomb_move.rpc(from_peer, to_peer, a.bomb_left)

@rpc("authority", "call_local", "reliable")
func _net_bomb_move(from_peer: int, to_peer: int, fuse: float) -> void:
	var a: Player = _players.get(from_peer)
	var b: Player = _players.get(to_peer)
	if a:
		a.clear_bomb()
	if b:
		b.give_bomb(fuse)
		b.float_text("HOT POTATO!", PvpPickup.COLORS["bomb"])

@rpc("authority", "call_local", "reliable")
func _net_bomb_boom(peer: int) -> void:
	var p: Player = _players.get(peer)
	if p == null:
		return
	p.clear_bomb()
	Sfx.play("bomb_boom", p.global_position)
	# no source: it hurts the carrier too, and anyone it kills is a "blown up", not a kill for somebody
	_map.add_child(Explosion.new().setup(p.global_position, 150.0, 70, 0.05, null))

func _leader() -> int:
	if _cm:
		return score_leader(_score, _kills, _players.keys())
	var best := 0
	for id: int in _players:
		if best == 0 or _kills[id] > _kills[best] or (_kills[id] == _kills[best] and _deaths[id] < _deaths[best]):
			best = id
	return best

## Crown mode: the present peer with the most points, then kills, then the lowest id; 0 when `present` is empty.
static func score_leader(score: Dictionary, kills: Dictionary, present: Array) -> int:
	var best := 0
	for id: int in present:
		if best == 0:
			best = id
			continue
		var s: float = score.get(id, 0.0)
		var bs: float = score.get(best, 0.0)
		if s > bs or (s == bs and (kills.get(id, 0) > kills.get(best, 0) or (kills.get(id, 0) == kills.get(best, 0) and id < best))):
			best = id
	return best

# --- Crown mode: the crown is a pickup, the score is seconds worn; the host owns every state change

## Host only: the first appearance, the win check and the return to the centre of a crown nobody picks up.
func _tick_crown(delta: float) -> void:
	if _over:
		return
	if _crown_spawn_in != INF:
		_crown_spawn_in -= delta
		if _crown_spawn_in <= 0.0:
			_crown_spawn_in = INF
			_net_crown.rpc(0, _map.spawn_point, 0.0)
		return
	if _crown != 0:
		if _score.get(_crown, 0.0) >= float(_cfg.score_limit):
			_end.rpc(_crown, _teams.get(_crown, -1))   # in a team match the king's team wins
		return
	if _crown_obj == null:
		return
	_crown_free += delta
	if _crown_free >= float(_cfg.crown_reset):
		_crown_free = 0.0
		if _crown_obj.position.distance_to(_map.spawn_point) > 50.0:
			_net_crown.rpc(0, _map.spawn_point, 0.0)   # every peer announces it from the RPC

func _on_crown_touched(peer: int) -> void:
	_crown_claim.rpc_id(1, peer)

## The host serialises claims: the first living player to touch a free crown wears it.
@rpc("any_peer", "call_local", "reliable")
func _crown_claim(taker: int) -> void:
	if not multiplayer.is_server() or _over or _crown != 0 or _crown_obj == null or _crown_obj.grace > 0.0:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != taker and not Net.solo:
		return   # a peer can only claim for its own player (a solo match has the one peer claiming for its bots too)
	var p: Player = _players.get(taker)
	if p == null or p.down:
		return
	_net_crown.rpc(taker, Vector2.INF, 0.0)

## The crown's new state on every peer: worn by `holder`, or (holder 0) lying at `pos`, untouchable for `grace` seconds.
@rpc("authority", "call_local", "reliable")
func _net_crown(holder: int, pos: Vector2, grace: float) -> void:
	if _crown_obj != null:
		_crown_obj.queue_free()
		_crown_obj = null
	_crown = holder
	_crown_free = 0.0
	for id: int in _players:
		_players[id].crowned = id == holder
	if holder != 0:
		Sfx.play("crown")
		_say("%s took the crown!" % _name_of(holder), 1.8)
		return
	_crown_obj = CrownPickup.new()
	_crown_obj.position = pos
	_crown_obj.grace = grace
	_crown_obj.touched.connect(_on_crown_touched)
	_map.add_child(_crown_obj)
	if grace <= 0.0:
		Sfx.play("crown")
		_say("The crown is up!   grab it!", 1.8)

@rpc("authority", "call_local", "reliable")
func _end(winner: int, win_team: int) -> void:
	_over = true
	_winner = winner
	Sfx.play("win")
	_set_players_active(false)
	var who: String = Net.roster[winner].name if Net.roster.has(winner) else "nobody"
	_match_menu.close()
	var names := {}
	for id: int in _stats:
		var p: Player = _players.get(id)
		names[id] = "%s (%s)" % [_name_of(id), p.hero.display_name] if p and p.hero else _name_of(id)   # awards say who on what
	var results := MatchHud.Results.new()
	results.board = scoreboard(winner, win_team)
	results.title = "%s wins!" % who
	if _tdm:
		results.title = "%s team wins!" % Net.TEAM_NAMES[win_team] if win_team >= 0 else "Draw!"
	results.rows = awards(_stats, _kills, _deaths, _killed_by, names)
	if Net.solo or multiplayer.is_server():
		results.next_label = "Play again" if Net.solo else "Back to lobby"
		results.proceed = _continue_from_results
	_banner.get_parent().add_child(results)
	_banner.modulate.a = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if ChatBox.typing:
		return
	var menu_pressed: bool = event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)
	if menu_pressed:
		get_viewport().set_input_as_handled()
		if _over:
			Net.leave()
		else:
			_match_menu.open()

func _exit_tree() -> void:
	MatchEvent.current = MatchEvent.NONE   # the event is this match's; the next scene starts clean

func _continue_from_results() -> void:
	if Net.solo:
		get_tree().reload_current_scene()
	else:
		Net.back_to_lobby()

func _say(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	create_tween().tween_property(_banner, "modulate:a", 0.0, 0.5).set_delay(seconds)

## Bottom-right radar of the whole plateau: cover, pickups, living enemies (red) and you (white ring).
class Radar extends Control:
	const WIDTH := 220.0
	const MARGIN := 20.0
	var arena: Node
	var _scale := WIDTH / (WorldMap.ARENA_HALF.x * 2.0 * WorldMap.TILE)

	func _ready() -> void:
		size = Vector2(WIDTH, WorldMap.ARENA_HALF.y * 2.0 * WorldMap.TILE * _scale)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		position = get_viewport_rect().size - size - Vector2(MARGIN, MARGIN)
		queue_redraw()

	func _to_radar(world: Vector2) -> Vector2:
		return size / 2.0 + (world - arena._map.spawn_point) * _scale

	func _draw() -> void:
		ArenaUi.panel(self, Rect2(Vector2.ZERO, size))
		draw_set_transform(size * 0.05, 0.0, Vector2.ONE * 0.9)   # the map sits inside the frame
		if MatchEvent.is_on(MatchEvent.FOG):   # Fog: the radar stays (vanishing looks like a bug) but shows nothing
			var fog := MatchEvent.color(MatchEvent.FOG)
			draw_rect(Rect2(Vector2.ZERO, size), Color(fog, 0.12))
			draw_string(ArenaUi.DISPLAY, Vector2(0, size.y / 2.0 + 8.0), "FOG", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(fog, 0.8))
			return
		var cell := maxf(WorldMap.TILE * _scale, 1.0)
		for w: Vector2 in arena._map.water_spots:   # Colosseum: the deadly water
			draw_rect(Rect2(_to_radar(w) - Vector2(cell, cell) / 2.0, Vector2(cell, cell)), Color(0.15, 0.45, 0.65, 0.9))
		for seg in arena._map.rails:
			draw_line(_to_radar(seg[0]), _to_radar(seg[1]), Color(0.7, 0.68, 0.62), 1.5)
		for c: Vector2 in arena._map.cover:
			draw_circle(_to_radar(c), 2.5, Color(0.55, 0.55, 0.5))
		for pk: PvpPickup in arena._pickups.values():
			var p := _to_radar(pk.position)
			var col: Color = PvpPickup.COLORS[pk.kind]
			var tier := PvpPickup.tier_of(pk.kind)
			var r := 5.0 + tier * 2.5   # bigger = rarer; epics also get a gold ring
			var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.BLACK, 1.5)
			if tier >= PvpPickup.Tier.RARE:
				draw_arc(p, r + 3.0, 0.0, TAU, 20, PvpPickup.TIER_COLORS[tier], 1.5)
			if tier == PvpPickup.Tier.EPIC:
				draw_arc(p, r + 6.0, 0.0, TAU, 24, PvpPickup.TIER_COLORS[tier], 1.5)
		if arena._crown_obj != null:   # Crown mode: the crown on the ground is the objective, so it is the loudest mark
			var cp := _to_radar(arena._crown_obj.position)
			draw_circle(cp, 5.0, CrownPickup.GOLD)
			draw_arc(cp, 8.0 + 2.0 * sin(Time.get_ticks_msec() * 0.006), 0.0, TAU, 24, CrownPickup.GOLD, 2.0)
		var me_id := Net.local_id()
		for id: int in arena._players:
			var pl: Player = arena._players[id]
			if pl.down or (id != me_id and pl.hidden_from(arena._players.get(me_id))):
				continue   # a Smoke Screen / Stalk fade hides him from the radar too
			var p := _to_radar(pl.global_position)
			if id == me_id:
				draw_arc(p, 5.0, 0.0, TAU, 20, Color.BLACK, 3.5)
				draw_arc(p, 5.0, 0.0, TAU, 20, Color.WHITE, 1.8)
			else:
				var mine: Player = arena._players.get(me_id)
				var ally: bool = mine != null and mine.team >= 0 and pl.team == mine.team
				draw_circle(p, 3.5, Color(0.35, 0.8, 1.0) if ally else Color(1.0, 0.25, 0.2))
			if id == arena._crown:
				draw_arc(p, 8.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3), 2.5)
