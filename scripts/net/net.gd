extends Node
## Autoload "Net": the online session. Steam lobbies carry the connection (SteamMultiplayerPeer from GodotSteam);
## everything after that is plain Godot high-level multiplayer. The host (peer 1) owns the roster and starts matches.
## Dev shim: `-- --enet-host` / `-- --enet-join=127.0.0.1` (plus --name=, --hero=, --autostart=N) skip Steam so two local
## instances can test gameplay. Steam has to be running for the real path.

signal status(text: String)
signal lobby_list(lobbies: Array)     ## [{id, name, members}]
signal roster_changed
signal player_left(peer_id: int)
signal match_go                       ## every peer has finished loading the match scene

const APP_ID := 480                   ## Spacewar (Valve's test app); replace with the real App ID before shipping
const GAME_TAG := "chita-pvp"
const MAX_PLAYERS := 8
const MIN_PLAYERS := 2
const LOBBY_PUBLIC := 2               ## Steam ELobbyType
const LOBBY_OK := 1                   ## EResult OK / chat-room-enter success
const PORT := 24567                   ## dev ENet only
const MENU_SCENE := "res://scenes/main_menu.tscn"
const HERO_SCENE := "res://scenes/hero_pick.tscn"
const MATCH_SCENE := "res://scenes/pvp_match.tscn"

var roster := {}                      ## peer_id -> {name: String, hero: String, slot: int}
var my_name := "Player"
var my_hero := "wizard"
var in_match := false
var lobby_id := 0
var last_status := ""
var dev_enet := false
var autostart := 0

var _steam: Object                    ## the GodotSteam singleton, null when the extension is missing
var _steam_ready := false
var _loaded := {}                     ## host only: peers whose match scene is built
var _entering := false                ## host only: the arena switch has been sent

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _reset("Could not connect to the host"))
	multiplayer.server_disconnected.connect(func() -> void: _reset("The host left"))
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--name="):
			my_name = a.get_slice("=", 1)
		elif a.begins_with("--hero="):
			my_hero = a.get_slice("=", 1)
		elif a.begins_with("--autostart="):
			autostart = int(a.get_slice("=", 1))
		elif a == "--enet-host":
			dev_enet = true
		elif a.begins_with("--enet-join="):
			dev_enet = true
	if dev_enet:
		_dev_connect.call_deferred(args)
		return
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
		var res: Dictionary = _steam.steamInitEx(APP_ID, true)   # true: GodotSteam pumps callbacks itself
		_steam_ready = res.get("status", 1) == 0
		if _steam_ready:
			my_name = _steam.getPersonaName()
			_steam.lobby_created.connect(_on_lobby_created)
			_steam.lobby_joined.connect(_on_lobby_joined)
			_steam.lobby_match_list.connect(_on_lobby_match_list)
			_steam.join_requested.connect(func(id: int, _friend: int) -> void: join(id))
		else:
			push_warning("Steam init failed: %s" % res)

## True when hosting/joining can work (Steam is up, or the dev ENet shim is on).
func available() -> bool:
	return _steam_ready or dev_enet

func is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not roster.is_empty()

func local_id() -> int:
	return multiplayer.get_unique_id()

# --- Steam lobby -----------------------------------------------------------------

func host() -> void:
	if not _steam_ready:
		_say("Steam is not running (start Steam, then restart the game)")
		return
	_say("Creating lobby...")
	_steam.createLobby(LOBBY_PUBLIC, MAX_PLAYERS)

func refresh_lobbies() -> void:
	if not _steam_ready:
		return
	_steam.addRequestLobbyListStringFilter("game", GAME_TAG, 0)
	_steam.addRequestLobbyListDistanceFilter(3)   # worldwide
	_steam.addRequestLobbyListResultCountFilter(20)
	_steam.requestLobbyList()

func join(id: int) -> void:
	if _steam_ready and lobby_id == 0:
		_say("Joining...")
		_steam.joinLobby(id)

## Join by typed/pasted lobby ID. Returns false if the text is not a number.
func join_by_id(text: String) -> bool:
	if not text.strip_edges().is_valid_int():
		_say("That is not a lobby ID")
		return false
	join(text.strip_edges().to_int())
	return true

func invite_friends() -> void:
	if _steam_ready and lobby_id != 0:
		_steam.activateGameOverlayInviteDialog(lobby_id)

func _on_lobby_created(result: int, id: int) -> void:
	if result != LOBBY_OK:
		_say("Could not create the lobby (error %d)" % result)
		return
	lobby_id = id
	_steam.setLobbyData(id, "game", GAME_TAG)
	_steam.setLobbyData(id, "name", "%s's match" % my_name)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.host_with_lobby(id)
	if err != OK:
		_say("Could not host (error %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_add(1, my_name, my_hero)
	_say("Lobby open. Invite friends or wait for players.")

func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if _steam.getLobbyOwner(id) == _steam.getSteamID():
		return   # the lobby's creator also gets this signal
	if response != LOBBY_OK:
		_say("Could not join the lobby (error %d)" % response)
		return
	lobby_id = id
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.connect_to_lobby(id)
	if err != OK:
		_reset("Could not connect (error %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_say("Connecting...")

func _on_lobby_match_list(ids: Array) -> void:
	var out := []
	for id: int in ids:
		out.append({"id": id, "name": _steam.getLobbyData(id, "name"), "members": _steam.getNumLobbyMembers(id)})
	lobby_list.emit(out)

# --- dev ENet shim ---------------------------------------------------------------

func _dev_connect(args: PackedStringArray) -> void:
	var peer := ENetMultiplayerPeer.new()
	for a in args:
		if a == "--enet-host":
			peer.create_server(PORT, MAX_PLAYERS - 1)
			multiplayer.multiplayer_peer = peer
			_add(1, my_name, my_hero)
			_say("Dev host on port %d" % PORT)
		elif a.begins_with("--enet-join="):
			peer.create_client(a.get_slice("=", 1), PORT)
			multiplayer.multiplayer_peer = peer
			_say("Dev connecting...")

# --- roster ----------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass   # clients announce themselves with register() once connected

func _on_connected() -> void:
	register.rpc_id(1, my_name, my_hero)

func _on_peer_disconnected(id: int) -> void:
	player_left.emit(id)
	if multiplayer.is_server():
		_loaded.erase(id)
		if roster.erase(id):
			if in_match:
				_check_go()
			else:
				_broadcast()

func _add(id: int, pname: String, hero: String) -> void:
	var taken := roster.values().map(func(r: Dictionary) -> int: return r.slot)
	var slot := 0
	while slot in taken:
		slot += 1
	roster[id] = {"name": pname, "hero": hero, "slot": slot, "ready": false}
	roster_changed.emit()
	if multiplayer.is_server() and autostart > 0 and roster.size() >= autostart and not in_match:
		start_match.call_deferred()

func _broadcast() -> void:
	roster_changed.emit()
	roster_sync.rpc(roster)

@rpc("any_peer", "reliable")
func register(pname: String, hero: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.size() >= MAX_PLAYERS or in_match:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	_add(id, pname.substr(0, 20), hero)
	_broadcast()

func set_hero(hero: String) -> void:
	my_hero = hero
	if multiplayer.has_multiplayer_peer() and not roster.is_empty():
		if multiplayer.is_server():
			roster[1].hero = hero
			_broadcast()
		else:
			_set_hero.rpc_id(1, hero)

@rpc("any_peer", "reliable")
func _set_hero(hero: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and roster.has(id):
		roster[id].hero = hero
		_broadcast()

@rpc("authority", "reliable")
func roster_sync(r: Dictionary) -> void:
	roster = r
	roster_changed.emit()

# --- match flow ------------------------------------------------------------------

func start_match() -> void:
	if not multiplayer.is_server() or roster.size() < MIN_PLAYERS or in_match:
		return
	if _steam_ready and lobby_id != 0:
		_steam.setLobbyJoinable(lobby_id, false)
	for r: Dictionary in roster.values():
		r.ready = false
	_begin_match.rpc(roster)

@rpc("authority", "call_local", "reliable")
func _begin_match(r: Dictionary) -> void:
	roster = r
	in_match = true
	_loaded.clear()
	_entering = false
	get_tree().change_scene_to_file(HERO_SCENE)

## Hero-pick phase: everyone picks a hero (set_hero) and presses ready; the host then sends everyone into the arena.
func set_ready(value: bool) -> void:
	if multiplayer.is_server():
		roster[1].ready = value
		_broadcast()
	else:
		_set_ready.rpc_id(1, value)

@rpc("any_peer", "reliable")
func _set_ready(value: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and roster.has(id):
		roster[id].ready = value
		_broadcast()

func all_ready() -> bool:
	return not roster.is_empty() and roster.values().all(func(r: Dictionary) -> bool: return r.ready)

func enter_arena() -> void:
	if multiplayer.is_server() and in_match and not _entering:
		_entering = true
		_enter_arena.rpc()

@rpc("authority", "call_local", "reliable")
func _enter_arena() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)

## The match scene calls this once its players exist. RPCs sent before every peer has them would hit missing nodes,
## so the host releases everyone together with match_go.
func report_loaded() -> void:
	if multiplayer.is_server():
		_loaded[1] = true
		_check_go()
	else:
		_peer_loaded.rpc_id(1)

@rpc("any_peer", "reliable")
func _peer_loaded() -> void:
	if multiplayer.is_server():
		_loaded[multiplayer.get_remote_sender_id()] = true
		_check_go()

func _check_go() -> void:
	if roster.keys().all(func(id: int) -> bool: return _loaded.has(id)):
		_loaded.clear()
		_go.rpc()

@rpc("authority", "call_local", "reliable")
func _go() -> void:
	match_go.emit()

func back_to_lobby() -> void:
	if multiplayer.is_server():
		if _steam_ready and lobby_id != 0:
			_steam.setLobbyJoinable(lobby_id, true)
		_back.rpc()

@rpc("authority", "call_local", "reliable")
func _back() -> void:
	in_match = false
	get_tree().change_scene_to_file(MENU_SCENE)

## Drop the connection and return to the lobby screen (also used when the host disappears).
func leave() -> void:
	_reset("")

func _reset(message: String) -> void:
	if _steam_ready and lobby_id != 0:
		_steam.leaveLobby(lobby_id)
	lobby_id = 0
	roster.clear()
	in_match = false
	roster_changed.emit()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)
	if message != "":
		_say(message)

func _say(text: String) -> void:
	last_status = text
	status.emit(text)
