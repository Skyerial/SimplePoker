class_name PokerBot
extends RefCounted
## Picks an action for one seat using only what that player can see:
## its own hole cards, the board, the pot and how many opponents are left.

enum Style { ROCK, CALLING_STATION, GRINDER, MANIAC }
const STYLE_NAMES := ["Rock", "Calling station", "Grinder", "Maniac"]

## Strength = equity x players in the hand, so 1.0 is an average hand.
## play: strength needed to enter pre-flop. raise: strength needed to raise.
## margin: equity needed above pot odds to call. aggression: chance to raise
## when strong enough. bluff: chance to raise regardless.
const PROFILES := {
	Style.ROCK: {play = 1.2, raise = 1.6, margin = 0.08, aggression = 0.5, bluff = 0.02},
	Style.CALLING_STATION: {play = 0.75, raise = 1.9, margin = -0.12, aggression = 0.2, bluff = 0.02},
	Style.GRINDER: {play = 1.0, raise = 1.35, margin = 0.03, aggression = 0.8, bluff = 0.08},
	Style.MANIAC: {play = 0.7, raise = 1.1, margin = -0.08, aggression = 0.9, bluff = 0.25},
}

var style: int
var samples := 200  ## Monte Carlo runs per decision; the difficulty knob for later tiers.
var rng := RandomNumberGenerator.new()


func _init(bot_style: int) -> void:
	style = bot_style
	rng.randomize()


## Returns [action, amount] for PokerTable.act().
func decide(table: PokerTable, seat: int) -> Array:
	var p: Dictionary = PROFILES[style]
	var me = table.seats[seat]
	var la := table.legal_actions()
	var opponents := 0
	for i in PokerTable.MAX_SEATS:
		if i != seat and table.seats[i] and table.seats[i].in_hand:
			opponents += 1
	var eq := equity(me.hole, table.board, opponents)
	var strength := eq * (opponents + 1)
	var call: int = la.call

	if la.can_raise:
		var strong: bool = strength >= p.raise and rng.randf() < p.aggression
		if strong or rng.randf() < p.bluff:
			return ["raise", _raise_to(table, la)]
	if call == 0:
		return ["check", 0]
	var pot_odds := float(call) / (table.pot() + call)
	var preflop := table.street == PokerTable.Street.PREFLOP
	# Pre-flop equity against every random hand is pessimistic, so small calls ride on strength alone.
	var priced_in: bool = eq >= pot_odds + p.margin or (preflop and call <= table.big_blind * 4)
	if (strength >= p.play or not preflop) and priced_in:
		return ["call", 0]
	return ["fold", 0]


## Share of the pot this hand wins on average against `opponents` random hands.
func equity(hole: Array, board: Array, opponents: int) -> float:
	if opponents == 0:
		return 1.0
	var known := hole + board
	var deck := range(52).filter(func(c): return not known.has(c))
	var need := opponents * 2 + 5 - board.size()
	var won := 0.0
	for _s in samples:
		for k in need:
			var j := rng.randi_range(k, deck.size() - 1)
			var t = deck[k]
			deck[k] = deck[j]
			deck[j] = t
		var full := board + deck.slice(opponents * 2, need)
		var mine := Cards.evaluate(hole + full)
		var ties := 0
		var lost := false
		for o in opponents:
			var theirs := Cards.evaluate([deck[o * 2], deck[o * 2 + 1]] + full)
			if theirs > mine:
				lost = true
				break
			if theirs == mine:
				ties += 1
		if not lost:
			won += 1.0 / (ties + 1)
	return won / samples


func _raise_to(table: PokerTable, la: Dictionary) -> int:
	var pot_after_call: int = table.pot() + la.call
	var to := table.current_bet + int(pot_after_call * rng.randf_range(0.5, 1.0))
	to = roundi(float(to) / table.small_blind) * table.small_blind
	if to >= la.max_raise_to * 0.8:
		to = la.max_raise_to  # close to all-in anyway: shove
	return clampi(to, la.min_raise_to, la.max_raise_to)
