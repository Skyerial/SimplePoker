class_name TableRoom
extends Node
## One table: owns the PokerTable, the bots and the turn timer, checks every
## action and sends each player a view with only the cards they may see.
## Players are peer ids; whatever the room sends them goes out through `send`.
## With `accounts` set, cash-table chips come from and go back to bankrolls.

signal send(peer: int, method: StringName, args: Array)

const BOT_NAMES := ["Rosa", "Big Tony", "Mila", "Dex", "Hank"]
const EMOTES := ["Nice hand", "Hmm…", "Haha", "Grr", "GG", "Wow", "Oops", "Bluff?"]
const BOT_DELAY := 0.7
const NEXT_HAND_DELAY := 3.0
const TIME_BANK := 30.0
const BANK_REFILL := 2.0  ## seconds back per hand, up to TIME_BANK
const SEAT_HOLD := 180.0  ## seconds a disconnected player's seat is kept at cash tables
const EMOTE_COOLDOWN := 3.0
const LEVEL_HANDS := {"Turbo": 6, "Normal": 10, "Slow": 15}
const BLIND_STEPS := [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0, 64.0, 96.0, 128.0]
const STREET_NAMES := ["Pre-flop", "Flop", "Turn", "River"]

var id: int
var title: String
var host: int  ## peer who may press Start: whoever made the table
var settings: Dictionary  ## mode ("cash"/"tournament"), bb, stack, bots, speed, turn_time
var accounts: Accounts  ## null offline: chips are free
var table: PokerTable
var started := false
var finished := false
var idle := true  ## no hand running and none scheduled
var bots := {}  # seat -> PokerBot
var peer_seat := {}  # peer id -> seat, -1 while watching
var peer_names := {}  # peer id -> name
var waiting := {}  # peer id -> name, sits down between hands (cash)
var away := {}  # seat -> msec its player disconnected
var bank := {}  # seat -> time bank seconds left
var busted := []  # seats in the order they went out (tournament)
var revealed := {}
var last_action := {}
var last_emote := {}  # peer -> msec
var deadline := 0  # msec when the player to act times out, 0 for none
var turn_start := 0
var _dirty := false


@warning_ignore("integer_division")
func _init(room_id: int, owner_peer: int, owner_name: String, table_settings: Dictionary, accts: Accounts) -> void:
	id = room_id
	host = owner_peer
	title = "%s's table" % owner_name
	settings = table_settings
	accounts = accts
	table = PokerTable.new(settings.bb / 2, settings.bb)
	table.rng.randomize()
	table.event.connect(_on_event)


func _process(_delta: float) -> void:
	if deadline > 0 and Time.get_ticks_msec() >= deadline:
		var seat := table.to_act
		bank[seat] = 0.0
		_log("%s ran out of time" % table.seats[seat].name)
		_auto_act(seat, table.hand_number)


## A line for the server's table list.
func summary() -> Dictionary:
	var seated := table.seats.filter(func(s): return s != null).size()
	return {id = id, title = title, mode = settings.mode, blinds = "%d/%d" % [table.small_blind, table.big_blind],
		buy_in = settings.stack, seated = seated, started = started}


func has_away(player_name: String) -> bool:
	return away.keys().any(func(seat): return table.seats[seat].name == player_name)


## Hands chips still at the table back to their bankrolls. Mid-hand that's
## each player's stack from before the hand, so the hand is void.
func close() -> void:
	for i in PokerTable.MAX_SEATS:
		if table.seats[i] and not bots.has(i):
			_settle(i)


## Intents from a player at this table.
func handle(peer: int, what: String, args: Array) -> void:
	match [what] + args:
		["act", var action, var amount]:
			_on_act(peer, str(action), int(amount))
		["chat", var text]:
			_on_chat(peer, str(text))
		["emote", var i]:
			_on_emote(peer, int(i))
		["rebuy"]:
			_on_rebuy(peer)
		["start"]:
			if peer == host:
				start_game()


# --- what the room sends ---------------------------------------------------

func _to_all(method: StringName, args: Array) -> void:
	for peer in peer_seat:
		send.emit(peer, method, args)


func _log(text: String) -> void:
	_to_all("_recv_log", [text])


func _mark_dirty() -> void:
	if not _dirty:
		_dirty = true
		_send_views.call_deferred()


func _send_views() -> void:
	_dirty = false
	for peer in peer_seat:
		send.emit(peer, "_recv_view", [_view_for(peer)])


## The table as `peer` may see it: other players' hole cards are -1 until shown.
func _view_for(peer: int) -> Dictionary:
	var me: int = peer_seat.get(peer, -1)
	var seats := []
	for i in PokerTable.MAX_SEATS:
		var s = table.seats[i]
		if s == null:
			seats.append(null)
			continue
		var cards := []
		if not s.hole.is_empty() and (s.in_hand or revealed.has(i)):
			cards = s.hole.duplicate() if i == me or revealed.has(i) else [-1, -1]
		var note: String = last_action.get(i, "")
		if away.has(i):
			note = "disconnected"
		elif busted.has(i):
			note = "out"
		seats.append({name = s.name, stack = s.stack, cards = cards, in_hand = s.in_hand, note = note})
	var v := {
		seats = seats, me = me, button = table.button, to_act = table.to_act,
		board = table.board.duplicate(), pot = table.pot(), current_bet = table.current_bet,
		hand_running = table.hand_running, blinds = _blinds_text(), status = _status(peer),
		can_start = peer == host and not started, can_rebuy = false, buy_in = settings.stack, hint = "", legal = {},
		time_left = (deadline - Time.get_ticks_msec()) / 1000.0 if deadline > 0 else 0.0,
	}
	if me >= 0:
		var s = table.seats[me]
		v.can_rebuy = settings.mode == "cash" and started and s.stack == 0 and not (table.hand_running and s.in_hand)
		if s.in_hand and table.board.size() >= 3:
			v.hint = Cards.describe(Cards.evaluate(s.hole + table.board))
		if table.hand_running and table.to_act == me:
			v.legal = table.legal_actions()
	return v


func _status(peer: int) -> String:
	if not started:
		return "Press Start when everyone has joined." if peer == host else "Waiting for %s to start" % peer_names.get(host, "the host")
	if finished:
		var lines := ["%s wins the tournament!" % table.seats[_alive()[0]].name]
		for k in busted.size():
			lines.append("%d. %s" % [k + 2, table.seats[busted[-1 - k]].name])
		return "\n".join(lines)
	if waiting.has(peer):
		return "You'll be seated after this hand"
	if peer_seat.get(peer, -1) < 0:
		return "Watching"
	if not table.hand_running and _alive().size() < 2:
		return "Waiting for players"
	return ""


func _blinds_text() -> String:
	var t := "Blinds %d/%d" % [table.small_blind, table.big_blind]
	if table.ante > 0:
		t += " · ante %d" % table.ante
	return t


# --- players coming and going ----------------------------------------------

func add_peer(peer: int, player_name: String) -> void:
	peer_names[peer] = player_name
	peer_seat[peer] = -1
	for seat in away:
		if table.seats[seat].name == player_name:
			away.erase(seat)
			peer_seat[peer] = seat
			_log("%s is back" % player_name)
			_mark_dirty()
			return
	if not started or (settings.mode == "cash" and not table.hand_running):
		_sit_human(peer, player_name)
	elif settings.mode == "cash":
		waiting[peer] = player_name
		_log("%s joins after this hand" % player_name)
	else:
		_log("%s is watching" % player_name)
	if started and idle:
		_next_hand()
	_mark_dirty()


## `leaving` gives the seat up at the next hand instead of holding it.
func remove_peer(peer: int, leaving: bool) -> void:
	if not peer_seat.has(peer):
		return
	var seat: int = peer_seat[peer]
	peer_seat.erase(peer)
	waiting.erase(peer)
	if seat >= 0:
		if not started or (leaving and settings.mode == "cash" and not table.hand_running):
			_stand(seat)
		else:
			away[seat] = Time.get_ticks_msec() - (int(SEAT_HOLD * 1000) + 1 if leaving else 0)
			if table.to_act == seat:
				_auto_act(seat, table.hand_number)
	_log("%s left" % peer_names[peer])
	peer_names.erase(peer)
	if peer == host and not peer_seat.is_empty():
		host = peer_seat.keys()[0]
	_mark_dirty()


## Cash tables make room by sending a bot home. Only call between hands.
func _sit_human(peer: int, player_name: String) -> bool:
	var paid: bool = accounts != null and settings.mode == "cash"
	if paid and accounts.chips(player_name) < settings.stack:
		_log("%s can't cover the %d buy-in and is watching" % [player_name, settings.stack])
		return false
	var seat := table.seats.find(null)
	if seat < 0 and started and settings.mode == "cash" and not bots.is_empty():
		seat = bots.keys()[0]
		_log("%s leaves to make room" % table.seats[seat].name)
		_stand(seat)
	if seat < 0:
		_log("%s is watching (table full)" % player_name)
		return false
	if paid:
		accounts.buy_in(player_name, str(id), settings.stack)
	table.sit(seat, player_name, settings.stack)
	bank[seat] = TIME_BANK
	peer_seat[peer] = seat
	_log("%s sits down" % player_name)
	return true


func _stand(seat: int) -> void:
	if not bots.has(seat):
		_settle(seat)
	table.stand(seat)
	away.erase(seat)
	bank.erase(seat)
	bots.erase(seat)
	for peer in peer_seat:
		if peer_seat[peer] == seat:
			peer_seat[peer] = -1


func _settle(seat: int) -> void:
	if accounts and settings.mode == "cash":
		accounts.settle(table.seats[seat].name, str(id))


func start_game() -> void:
	if started:
		return
	var free := range(PokerTable.MAX_SEATS).filter(func(i): return table.seats[i] == null)
	for k in mini(settings.bots, free.size()):
		table.sit(free[k], BOT_NAMES[k], settings.stack, true)
		bots[free[k]] = PokerBot.new(k % 4)
	if _alive().size() < 2:
		_log("Need at least 2 players: add bots or wait for a friend")
		return
	started = true
	_log("[b]%s started[/b]" % ("Tournament" if settings.mode == "tournament" else "Cash game"))
	_next_hand()


func _on_rebuy(peer: int) -> void:
	var seat: int = peer_seat.get(peer, -1)
	if seat < 0 or settings.mode != "cash":
		return
	var s = table.seats[seat]
	if s.stack > 0 or (table.hand_running and s.in_hand):
		return
	if accounts and not accounts.buy_in(s.name, str(id), settings.stack):
		_log("%s can't cover the %d rebuy" % [s.name, settings.stack])
		return
	s.stack = settings.stack
	_log("%s rebuys" % s.name)
	if idle:
		_next_hand()
	_mark_dirty()


func _on_chat(peer: int, text: String) -> void:
	text = text.strip_edges().left(200)
	if text.is_empty() or not peer_names.has(peer):
		return
	_log("[color=#8ecae6]%s:[/color] %s" % [peer_names[peer], text.replace("[", "[lb]")])


func _on_emote(peer: int, i: int) -> void:
	var seat: int = peer_seat.get(peer, -1)
	var now := Time.get_ticks_msec()
	if seat < 0 or i < 0 or i >= EMOTES.size() or now - last_emote.get(peer, -100000) < EMOTE_COOLDOWN * 1000:
		return
	last_emote[peer] = now
	_to_all("_recv_emote", [seat, EMOTES[i]])


# --- running hands -----------------------------------------------------------

func _on_act(peer: int, action: String, amount: int) -> void:
	var seat: int = peer_seat.get(peer, -1)
	if seat < 0 or table.to_act != seat:
		return
	var over: float = (Time.get_ticks_msec() - turn_start) / 1000.0 - settings.turn_time
	var old := deadline
	deadline = 0
	if not table.act(seat, action, amount):
		deadline = old
		return
	if over > 0:
		bank[seat] = maxf(0.0, bank[seat] - over)


## Checks if possible, otherwise folds. For timeouts and disconnected players.
func _auto_act(seat: int, hand: int) -> void:
	if not table.hand_running or table.hand_number != hand or table.to_act != seat:
		return
	deadline = 0
	table.act(seat, "check" if table.legal_actions().call == 0 else "fold")


func _bot_turn(seat: int, hand: int) -> void:
	if not table.hand_running or table.hand_number != hand or table.to_act != seat:
		return
	var d: Array = bots[seat].decide(table, seat)
	if not table.act(seat, d[0], d[1]):
		push_error("Bot made an illegal move: %s" % [d])
		_auto_act(seat, hand)


func _on_event(e: Dictionary) -> void:
	match e.type:
		"hand_start":
			revealed.clear()
			last_action.clear()
			for seat in bank:
				bank[seat] = minf(TIME_BANK, bank[seat] + BANK_REFILL)
			_log("\n[b]Hand #%d[/b] · %s" % [e.hand, _blinds_text()])
		"ante":
			_log("Everyone antes %d" % e.amount)
		"blind":
			last_action[e.seat] = "posts %d" % e.amount
		"action":
			var text := _action_text(e)
			last_action[e.seat] = text
			_log("%s %s" % [table.seats[e.seat].name, text])
		"board":
			last_action.clear()
			_log("[b]%s:[/b] %s" % [STREET_NAMES[e.street], " ".join(e.cards.map(Cards.to_str))])
		"turn":
			_on_turn(e.seat)
		"showdown":
			for seat in e.order:
				revealed[seat] = true
				var s = table.seats[seat]
				_log("%s shows %s (%s)" % [s.name, " ".join(s.hole.map(Cards.to_str)), Cards.describe(e.scores[seat])])
		"pot_award":
			_log("[color=#f0c040]%s wins %d[/color]" % [table.seats[e.seat].name, e.amount])
		"hand_end":
			deadline = 0
			_record_busts()
			_save_stacks()
			get_tree().create_timer(NEXT_HAND_DELAY).timeout.connect(_next_hand)
	_mark_dirty()


## Snapshot of every cash stack, so a crash only loses the hand in progress.
func _save_stacks() -> void:
	if not accounts or settings.mode != "cash":
		return
	for i in PokerTable.MAX_SEATS:
		if table.seats[i] and not bots.has(i):
			accounts.set_stack(table.seats[i].name, str(id), table.seats[i].stack)
	accounts.save()


func _on_turn(seat: int) -> void:
	deadline = 0
	if bots.has(seat):
		get_tree().create_timer(BOT_DELAY).timeout.connect(_bot_turn.bind(seat, table.hand_number))
	elif away.has(seat):
		get_tree().create_timer(0.5).timeout.connect(_auto_act.bind(seat, table.hand_number))
	else:
		turn_start = Time.get_ticks_msec()
		deadline = turn_start + int((settings.turn_time + bank.get(seat, 0.0)) * 1000)


func _next_hand() -> void:
	if not started or finished or table.hand_running:
		return
	if settings.mode == "cash":
		for seat in away.keys():
			if Time.get_ticks_msec() - away[seat] > SEAT_HOLD * 1000:
				_log("%s's seat is released" % table.seats[seat].name)
				_stand(seat)
		for peer in waiting.keys():
			_sit_human(peer, waiting[peer])
			waiting.erase(peer)
		for seat in bots:
			if table.seats[seat].stack == 0:
				table.seats[seat].stack = settings.stack  # bots get a fresh stack from the house
				_log("%s rebuys" % table.seats[seat].name)
	else:
		if _alive().size() == 1:
			finished = true
			idle = true
			_log("[b]%s wins the tournament![/b]" % table.seats[_alive()[0]].name)
			_mark_dirty()
			return
		_set_blind_level()
	idle = not table.start_hand()
	_mark_dirty()


@warning_ignore("integer_division")
func _set_blind_level() -> void:
	var level := mini(table.hand_number / LEVEL_HANDS[settings.speed], BLIND_STEPS.size() - 1)
	var bb := maxi(2, roundi(settings.bb * BLIND_STEPS[level]) / 2 * 2)
	if bb != table.big_blind:
		table.big_blind = bb
		table.small_blind = bb / 2
		table.ante = bb / 10 if level >= 4 else 0
		_log("[b]Blinds up: %s[/b]" % _blinds_text())


func _record_busts() -> void:
	if settings.mode != "tournament":
		return
	# ponytail: players busting in the same hand get places in seat order, not by chip count.
	for i in PokerTable.MAX_SEATS:
		var s = table.seats[i]
		if s and s.stack == 0 and not busted.has(i):
			busted.append(i)
			_log("%s is out in place %d" % [s.name, _alive().size() + 1])


func _alive() -> Array:
	return range(PokerTable.MAX_SEATS).filter(func(i): return table.seats[i] != null and table.seats[i].stack > 0)


func _action_text(e: Dictionary) -> String:
	var text: String = {
		"fold": "folds",
		"check": "checks",
		"call": "calls %d" % e.to,
		"bet": "bets %d" % e.to,
		"raise": "raises to %d" % e.to,
	}[e.action]
	return text + (" (all-in)" if e.all_in else "")
