extends SceneTree
## Run: Godot --headless --path . -s res://tests/run_tests.gd

var failures := 0


func _initialize() -> void:
	test_hand_ranking()
	test_heads_up_blinds()
	test_min_raise_and_incomplete_all_in()
	test_uncontested()
	test_side_pots()
	test_bot_marathon()
	test_antes()
	test_accounts()
	test_chip_breakdown()


## Node.multiplayer only exists once the tree runs, so the Game test waits for the first frame.
func _process(_delta: float) -> bool:
	test_views_hide_cards()
	test_cash_table_uses_bankroll()
	print("FAILED: %d" % failures if failures else "All tests passed")
	quit(1 if failures else 0)
	return true


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


func score(s: String) -> int:
	return Cards.evaluate(Cards.parse_many(s))


func test_hand_ranking() -> void:
	check(score("As Ks Qs Js Ts 2c 3d") > score("Ac Ad Ah As Kd 2c 3d"), "royal flush beats quads")
	check(Cards.category(score("Ac 2d 3h 4s 5c Kd 9h")) == 4, "wheel is a straight")
	check(score("Ac 2d 3h 4s 5c Kd 9h") < score("2c 3d 4h 5s 6c Kd 9h"), "wheel is the lowest straight")
	check(score("2h 7h 9h Jh Kh Ac Qd") > score("9c Td Jh Qs Kc 2d 3h"), "flush beats straight")
	check(Cards.category(score("Ac Ad Ah Kc Kd Kh 2s")) == 6, "two trips make a full house")
	check(score("Ac Ad 7h 7s 7c 2d 2h") > score("7h 7s 7c Kd Kh 2c 3d"), "full house takes the best pair")
	check(score("Ac Ad Kc Kd Qc Qd 2s") > score("Ac Ad Kc Kd Jc Jd Ts"), "two pair kicker can come from a third pair")
	check(score("2d 3h Tc Jc Qc Kc Ac") == score("4d 5h Tc Jc Qc Kc Ac"), "board plays: tie")


func test_heads_up_blinds() -> void:
	var t := PokerTable.new(10, 20)
	t.sit(0, "A", 1000)
	t.sit(1, "B", 1000)
	t.start_hand()
	check(t.button == 0 and t.seats[0].bet == 10 and t.seats[1].bet == 20, "heads-up: button posts the small blind")
	check(t.to_act == 0, "heads-up: button acts first pre-flop")
	t.act(0, "call")
	t.act(1, "check")
	check(t.street == PokerTable.Street.FLOP and t.to_act == 1, "heads-up: big blind acts first after the flop")


func test_min_raise_and_incomplete_all_in() -> void:
	var t := PokerTable.new(10, 20)
	t.sit(0, "Short", 150)
	t.sit(1, "SB", 1000)
	t.sit(2, "BB", 1000)
	t.sit(3, "UTG", 1000)
	t.start_hand()  # button 0, SB 1, BB 2, UTG 3 acts first
	check(t.to_act == 3, "first to act is left of the big blind")
	check(not t.act(3, "raise", 30), "raise below the minimum is rejected")
	check(t.act(3, "raise", 100), "raise to 100 is accepted")
	check(t.act(0, "raise", 150), "short all-in for less than a full raise is accepted")
	t.act(1, "fold")
	t.act(2, "fold")
	var la := t.legal_actions()
	check(t.to_act == 3 and not la.can_raise and la.call == 50, "incomplete raise doesn't reopen betting")


func test_uncontested() -> void:
	var t := PokerTable.new(10, 20)
	for i in 3:
		t.sit(i, "P%d" % i, 1000)
	t.start_hand()  # button 0, SB 1, BB 2
	t.act(0, "fold")
	t.act(1, "fold")
	check(not t.hand_running and t.seats[2].stack == 1010 and t.seats[1].stack == 990, "big blind wins when everyone folds")
	var paid := []
	t.event.connect(func(e): if e.type in ["pot_award", "returned"]: paid.append([e.type, e.seat, e.amount]))
	t.start_hand()  # button 1, SB 2, BB 0
	t.act(1, "raise", 100)
	t.act(2, "fold")
	t.act(0, "fold")
	check(paid == [["returned", 1, 80], ["pot_award", 1, 50]], "uncalled part of a raise comes back: got %s" % [paid])


func test_side_pots() -> void:
	var t := PokerTable.new(10, 20)
	t.sit(0, "Aces", 100)
	t.sit(1, "Kings", 300)
	t.sit(2, "Queens", 1000)
	# Dealt from seat 1: 1, 2, 0, 1, 2, 0, then burn + flop, burn + turn, burn + river.
	var paid := []
	t.event.connect(func(e): if e.type in ["pot_award", "returned"]: paid.append([e.type, e.seat, e.amount]))
	t.start_hand(Cards.parse_many("Ks Qs As Kh Qh Ah 4c 2c 7d 9s 4d Jc 4h 3d"))
	t.act(0, "raise", 100)  # all-in
	t.act(1, "call")
	t.act(2, "raise", 600)
	t.act(1, "call")  # all-in for 300 total, so 300 of the raise is unmatched
	check(not t.hand_running, "all-in hand runs out to showdown")
	var stacks := t.seats.slice(0, 3).map(func(s): return s.stack)
	check(stacks == [300, 400, 700], "main pot to aces, side pot to kings: got %s" % [stacks])
	check(paid == [["returned", 2, 300], ["pot_award", 0, 300], ["pot_award", 1, 400]],
			"queens' uncalled 300 comes back, not as a pot win: got %s" % [paid])


func test_bot_marathon() -> void:
	var t := PokerTable.new(10, 20)
	t.rng.seed = 42
	var bots := []
	for i in 6:
		t.sit(i, "Bot%d" % i, 2000, true)
		var b := PokerBot.new(i % 4)
		b.samples = 20
		b.rng.seed = i
		bots.append(b)
	var chips := 12000
	for h in 200:
		for s in t.seats:
			if s.stack == 0:
				s.stack = 2000
				chips += 2000
		t.start_hand()
		var steps := 0
		while t.hand_running and steps < 200:
			var d: Array = bots[t.to_act].decide(t, t.to_act)
			if not t.act(t.to_act, d[0], d[1]):
				check(false, "hand %d: illegal bot move %s" % [h, d])
				return
			steps += 1
		check(not t.hand_running, "hand %d finishes" % h)
		var total: int = t.seats.reduce(func(acc, s): return acc + s.stack, 0)
		if total != chips:
			check(false, "hand %d: chips not conserved (%d != %d)" % [h, total, chips])
			return


func test_antes() -> void:
	var t := PokerTable.new(10, 20)
	t.ante = 5
	t.sit(0, "A", 1000)
	t.sit(1, "B", 1000)
	t.sit(2, "Short", 3)
	t.start_hand()
	check(t.pot() == 5 + 5 + 3 + 10, "antes go in the pot (short big blind posts nothing more): got %d" % t.pot())
	check(t.seats[2].all_in and t.seats[2].in_hand, "player all-in from the ante stays in the hand")


func test_views_hide_cards() -> void:
	var g = root.get_node("Game")
	g.settings = {mode = "cash", bb = 20, stack = 2000, bots = 2, speed = "Normal", turn_time = 20}
	g.play_offline("Me")
	var room: TableRoom = g.rooms.values()[0]
	var me: int = room.peer_seat[1]
	var v: Dictionary = room._view_for(1)
	check(v.seats[me].cards.size() == 2 and v.seats[me].cards.min() >= 0, "you see your own cards")
	for i in PokerTable.MAX_SEATS:
		if i != me and v.seats[i] != null:
			check(v.seats[i].cards == [-1, -1], "seat %d's cards are hidden from you" % i)
	room.peer_seat[99] = -1
	var w: Dictionary = room._view_for(99)
	room.peer_seat.erase(99)
	check(w.legal.is_empty() and w.seats.all(func(s): return s == null or s.cards == [-1, -1]), "a watcher sees no hole cards")
	g.leave()


const ACCOUNTS_FILE := "user://test_accounts.json"


func test_accounts() -> void:
	DirAccess.remove_absolute(ACCOUNTS_FILE)
	var a := Accounts.new(ACCOUNTS_FILE)
	check(a.register("Sky", "secret1") == "", "register works")
	check(a.register("sky", "secret2") != "", "names are unique ignoring case")
	check(a.register("x", "secret1") != "" and a.register("Bob", "123") != "", "short names and passwords are refused")
	check(a.login("SKY", "secret1") == "" and a.name_of("SKY") == "Sky", "login ignores name case")
	check(a.login("Sky", "wrong!") != "" and a.login("Nobody", "secret1") != "", "wrong password or name fails")
	check(not a.data.sky.hash.contains("secret1"), "password isn't stored as plain text")
	check(a.chips("Sky") == Accounts.START_CHIPS, "new accounts get the starting bankroll")
	check(not a.buy_in("Sky", "1", 999999), "can't buy in for more than the bankroll")
	check(a.buy_in("Sky", "1", 2000) and a.chips("Sky") == 3000, "buy-in comes out of the bankroll")
	a.set_stack("Sky", "1", 3500)
	a.save()
	var b := Accounts.new(ACCOUNTS_FILE)
	check(b.chips("Sky") == 6500, "after a crash the table stack goes back to the bankroll")
	check(b.login("Sky", "secret1") == "", "accounts survive a restart")
	DirAccess.remove_absolute(ACCOUNTS_FILE)


func test_cash_table_uses_bankroll() -> void:
	DirAccess.remove_absolute(ACCOUNTS_FILE)
	var a := Accounts.new(ACCOUNTS_FILE)
	a.register("Sky", "secret1")
	a.register("Poor", "secret1")
	a.buy_in("Poor", "x", 4900)
	var room := TableRoom.new(7, 5, "Sky", {mode = "cash", bb = 20, stack = 2000, bots = 1, speed = "Normal", turn_time = 20}, a)
	root.add_child(room)
	room.add_peer(5, "Sky")
	room.add_peer(6, "Poor")
	check(room.peer_seat[5] >= 0 and a.chips("Sky") == 3000, "sitting at a cash table pays the buy-in")
	check(room.peer_seat[6] == -1 and a.chips("Poor") == 100, "a player who can't cover the buy-in watches")
	room.remove_peer(5, true)
	check(a.chips("Sky") == 5000, "standing up returns the stack")
	room.free()
	DirAccess.remove_absolute(ACCOUNTS_FILE)


func test_chip_breakdown() -> void:
	for value in [0, 1, 7, 10, 20, 135, 1980, 2000, 7730, 123456]:
		for spread in [false, true]:
			var counts: Array = ChipStack.breakdown(value, spread)
			var total := 0
			for i in counts.size():
				total += counts[i] * ChipStack.DENOMS[i][0]
			check(total == value, "chips for %d (spread %s) add up, got %d" % [value, spread, total])
	var stack: Array = ChipStack.breakdown(2000, true)
	check(stack.slice(3).all(func(n): return n > 0), "a 2000 stack has some of every small chip: %s" % [stack])
