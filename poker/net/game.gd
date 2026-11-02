extends Node
## Autoload `Game`. One of three roles:
## - offline: runs a TableRoom against bots on this machine, you are peer 1.
## - client: logs in to the game server, browses its tables and forwards your
##   actions to the table you sit at. The UI only ever reads `view`.
## - server (run with `-- --server`): runs every table, the accounts and the
##   bankrolls. Players never talk to each other, only to the server.

signal view_changed
signal log_added(text: String)
signal emote_shown(seat: int, emote: String)
signal closed(reason: String)
signal lobby_changed  ## logged in, or the table list or bankroll changed
signal joined  ## the server seated us at a table

const PORT := 7777
const CERT_NAME := "poker-server"
const MAX_TABLES := 20
const MAX_LOGIN_FAILS := 5

## Table settings from the lobby, for an offline game or a new online table.
var settings := {mode = "cash", bb = 20, stack = 2000, bots = 5, speed = "Normal", turn_time = 20}

var view := {}  ## what this machine shows, see TableRoom._view_for()
var last_error := ""  ## why we were sent back to the lobby
var username := ""  ## logged-in account, "" when not
var chips := 0  ## bankroll, as of the last table list
var tables := []  ## the server's table list, see TableRoom.summary()
var _login := []  ## [name, password, register] sent once connected

# Offline and server.
var is_server := false
var accounts: Accounts
var rooms := {}  # id -> TableRoom
var peer_room := {}  # peer -> room id
var users := {}  # peer -> account name (server)
var login_fails := {}  # peer -> count (server)
var _next_room := 1


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): _send_login.rpc_id(1, _login[0], _login[1], _login[2]))
	multiplayer.connection_failed.connect(func(): _close("Couldn't reach the server."))
	multiplayer.server_disconnected.connect(func(): _close("Lost the connection to the server."))
	if "--server" in OS.get_cmdline_user_args():
		start_server.call_deferred()


# --- offline ---------------------------------------------------------------

func play_offline(player_name: String) -> void:
	_reset()
	var room := _new_room(1, player_name, settings, null)
	peer_room[1] = room.id
	room.add_peer(1, player_name)
	room.start_game()


# --- client ----------------------------------------------------------------

## Returns an error message, or "" while connecting. Watch lobby_changed and closed.
func connect_to_server(address: String, player_name: String, password: String, register: bool) -> String:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err == OK:
		err = peer.host.dtls_client_setup(CERT_NAME, _client_tls())
	if err != OK:
		return "Couldn't connect to %s: %s" % [address, error_string(err)]
	multiplayer.multiplayer_peer = peer
	_login = [player_name, password, register]
	return ""


## The server's certificate in the project pins it; without one the link is
## still encrypted, but a fake server in the middle can't be detected.
func _client_tls() -> TLSOptions:
	var cert := X509Certificate.new()
	if FileAccess.file_exists("res://server.crt") and cert.load("res://server.crt") == OK:
		return TLSOptions.client(cert, CERT_NAME)
	return TLSOptions.client_unsafe()


func refresh_tables() -> void:
	_list_tables.rpc_id(1)


func create_table() -> void:
	_create_table.rpc_id(1, settings)


func join_table(room_id: int) -> void:
	_join_table.rpc_id(1, room_id)


func log_out() -> void:
	_reset()


## Leaves the table; online you stay logged in and get the table list.
func leave() -> void:
	if username:
		_intent.rpc_id(1, "leave", [])
		view = {}
	else:
		_reset()


func act(action: String, amount := 0) -> void:
	_send_intent("act", [action, amount])


func send_chat(text: String) -> void:
	_send_intent("chat", [text])


func send_emote(i: int) -> void:
	_send_intent("emote", [i])


func rebuy() -> void:
	_send_intent("rebuy", [])


func start_game() -> void:
	_send_intent("start", [])


func _send_intent(what: String, args: Array) -> void:
	if username:
		_intent.rpc_id(1, what, args)
	else:
		_on_intent(1, what, args)


func _close(reason: String) -> void:
	_reset()
	last_error = reason
	closed.emit(reason)


func _reset() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	for room in rooms.values():
		room.close()
		room.queue_free()
	rooms.clear()
	peer_room.clear()
	username = ""
	tables = []
	view = {}


# --- client -> server --------------------------------------------------------

@rpc("any_peer", "reliable")
func _send_login(player_name: String, password: String, register: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not is_server or users.has(peer):
		return
	var err := accounts.register(player_name, password) if register else accounts.login(player_name, password)
	if not err and player_name.to_lower() in users.values().map(func(u): return u.to_lower()):
		err = "That account is already logged in."
	if err:
		login_fails[peer] = login_fails.get(peer, 0) + 1
		_recv_login.rpc_id(peer, err, "")
		# ponytail: per-connection limit only; add a per-IP/per-name lockout if anyone hammers it.
		if login_fails[peer] >= MAX_LOGIN_FAILS:
			multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	var user := accounts.name_of(player_name)
	users[peer] = user
	print("%s logged in" % user)
	_recv_login.rpc_id(peer, "", user)
	for room in rooms.values():
		if room.has_away(user):
			_enter(peer, room)
			return
	_send_tables(peer)


@rpc("any_peer", "reliable")
func _list_tables() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if users.has(peer):
		_send_tables(peer)


@rpc("any_peer", "reliable")
func _create_table(s: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not users.has(peer) or peer_room.has(peer):
		return
	if rooms.size() >= MAX_TABLES:
		_recv_tables.rpc_id(peer, _table_list(), accounts.chips(users[peer]), "The server is full, join a table instead.")
		return
	_enter(peer, _new_room(peer, users[peer], _clean_settings(s), accounts))


@rpc("any_peer", "reliable")
func _join_table(room_id: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if users.has(peer) and not peer_room.has(peer) and rooms.has(room_id):
		_enter(peer, rooms[room_id])


@rpc("any_peer", "reliable")
func _intent(what: String, args: Array) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if is_server and users.has(peer):
		_on_intent(peer, what, args)


func _on_intent(peer: int, what: String, args: Array) -> void:
	var room: TableRoom = rooms.get(peer_room.get(peer, -1))
	if room == null:
		return
	if what == "leave":
		_exit(peer, true)
		_send_tables(peer)
	else:
		room.handle(peer, what, args)


# --- server -> client --------------------------------------------------------

## Sends a room message to a player: straight to the UI offline, over RPC online.
func _deliver(peer: int, method: StringName, args: Array) -> void:
	if is_server:
		callv("rpc_id", [peer, method] + args)
	else:
		callv(method, args)


@rpc("authority", "reliable")
func _recv_login(err: String, user: String) -> void:
	if err:
		_close(err)
		return
	username = user
	lobby_changed.emit()


@rpc("authority", "reliable")
func _recv_tables(list: Array, bankroll: int, err: String) -> void:
	tables = list
	chips = bankroll
	last_error = err
	lobby_changed.emit()


@rpc("authority", "reliable")
func _recv_joined() -> void:
	joined.emit()


@rpc("authority", "reliable")
func _recv_view(v: Dictionary) -> void:
	view = v
	view.deadline = Time.get_ticks_msec() + int(v.time_left * 1000) if v.time_left > 0 else 0
	view_changed.emit()


@rpc("authority", "reliable")
func _recv_log(text: String) -> void:
	log_added.emit(text)


@rpc("authority", "reliable")
func _recv_emote(seat: int, emote: String) -> void:
	emote_shown.emit(seat, emote)


# --- server ------------------------------------------------------------------

func start_server() -> void:
	is_server = true
	var dir := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			dir = arg.trim_prefix("--data=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(dir + "backups")
	if FileAccess.file_exists(dir + "accounts.json"):
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		DirAccess.copy_absolute(dir + "accounts.json", dir + "backups/accounts-%s.json" % stamp)
	accounts = Accounts.new(dir + "accounts.json")
	if accounts.error:
		_stop_server(accounts.error)
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 64)
	if err == OK:
		err = peer.host.dtls_server_setup(_server_tls(dir))
	if err != OK:
		_stop_server("Couldn't open UDP port %d: %s" % [PORT, error_string(err)])
		return
	multiplayer.multiplayer_peer = peer
	print("Poker server running on UDP port %d. Data: %s" % [PORT, ProjectSettings.globalize_path(dir)])


func _stop_server(reason: String) -> void:
	printerr(reason)
	get_tree().quit(1)


## Makes a self-signed certificate on the first start. Copy server.crt into
## the project folder to let clients check they reach this server.
func _server_tls(dir: String) -> TLSOptions:
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if key.load(dir + "server.key") != OK or cert.load(dir + "server.crt") != OK:
		var crypto := Crypto.new()
		key = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key, "CN=%s,O=Poker,C=NL" % CERT_NAME, "20260101000000", "20460101000000")
		key.save(dir + "server.key")
		cert.save(dir + "server.crt")
	return TLSOptions.server(key, cert)


func _new_room(owner: int, owner_name: String, s: Dictionary, accts: Accounts) -> TableRoom:
	var room := TableRoom.new(_next_room, owner, owner_name, s, accts)
	room.send.connect(_deliver)
	_next_room += 1
	rooms[room.id] = room
	add_child(room)
	return room


func _enter(peer: int, room: TableRoom) -> void:
	peer_room[peer] = room.id
	_recv_joined.rpc_id(peer)
	room.add_peer(peer, users[peer])


## Takes a player off their table; an empty table closes and pays everyone out.
func _exit(peer: int, leaving: bool) -> void:
	var room: TableRoom = rooms.get(peer_room.get(peer, -1))
	peer_room.erase(peer)
	if room == null:
		return
	room.remove_peer(peer, leaving)
	if room.peer_seat.is_empty():
		room.close()
		rooms.erase(room.id)
		room.queue_free()


func _on_peer_disconnected(peer: int) -> void:
	if not is_server:
		return
	_exit(peer, false)
	if users.has(peer):
		print("%s logged out" % users[peer])
	users.erase(peer)
	login_fails.erase(peer)


func _send_tables(peer: int) -> void:
	_recv_tables.rpc_id(peer, _table_list(), accounts.chips(users[peer]), "")


func _table_list() -> Array:
	return rooms.values().map(func(r): return r.summary())


## Players send their own settings, so keep them in sane ranges.
@warning_ignore("integer_division")
func _clean_settings(s: Dictionary) -> Dictionary:
	return {
		mode = "tournament" if s.get("mode") == "tournament" else "cash",
		bb = clampi(int(s.get("bb", 20)) / 2 * 2, 2, 100000),
		stack = clampi(int(s.get("stack", 2000)), 100, 10000000),
		bots = clampi(int(s.get("bots", 5)), 0, 5),
		speed = s.get("speed") if TableRoom.LEVEL_HANDS.has(s.get("speed")) else "Normal",
		turn_time = clampi(int(s.get("turn_time", 20)), 5, 120),
	}
