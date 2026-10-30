extends SceneTree
## Run: Godot --headless --path . -s res://tests/run_tests.gd

var failures := 0


func _init() -> void:
	test_hand_ranking()
	test_heads_up_blinds()
	test_min_raise_and_incomplete_all_in()
	test_uncontested()
	test_side_pots()
	test_bot_marathon()
	print("FAILED: %d" % failures if failures else "All tests passed")
	quit(1 if failures else 0)


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


func test_side_pots() -> void:
	var t := PokerTable.new(10, 20)
	t.sit(0, "Aces", 100)
	t.sit(1, "Kings", 300)
	t.sit(2, "Queens", 1000)
	# Dealt from seat 1: 1, 2, 0, 1, 2, 0, then burn + flop, burn + turn, burn + river.
	t.start_hand(Cards.parse_many("Ks Qs As Kh Qh Ah 4c 2c 7d 9s 4d Jc 4h 3d"))
	t.act(0, "raise", 100)  # all-in
	t.act(1, "raise", 300)  # all-in
	t.act(2, "call")
	check(not t.hand_running, "all-in hand runs out to showdown")
	var stacks := t.seats.slice(0, 3).map(func(s): return s.stack)
	check(stacks == [300, 400, 700], "main pot to aces, side pot to kings: got %s" % [stacks])


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
