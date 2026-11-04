class_name PokerBot
extends RefCounted
## Picks an action for one seat using only what that player can see:
## its own hole cards, the board, the pot and how many opponents are left.
## Each bot is a character with a main style and a few moods it slips into
## on tilt, when short-stacked, or now and then for no reason.

enum Style { ROCK, CALLING_STATION, GRINDER, MANIAC, NIT, TRAPPER, BLUFFER, GAMBLER }
const STYLE_NAMES := ["Rock", "Calling station", "Grinder", "Maniac", "Nit", "Trapper", "Bluffer", "Gambler"]

## Strength = equity x players in the hand, so 1.0 is an average hand.
## play: strength needed to enter pre-flop. raise: strength needed to raise.
## margin: equity needed above pot odds to call. aggression: chance to raise
## when strong enough. bluff: chance to raise regardless. trap: chance to just
## check/call a raise-worthy hand before the river. size: raise as share of the pot.
const PROFILES := {
	Style.ROCK: {play = 1.2, raise = 1.6, margin = 0.08, aggression = 0.5, bluff = 0.02, trap = 0.1, size = [0.5, 0.8]},
	Style.CALLING_STATION: {play = 0.75, raise = 1.9, margin = -0.12, aggression = 0.2, bluff = 0.02, trap = 0.3, size = [0.4, 0.7]},
	Style.GRINDER: {play = 1.0, raise = 1.35, margin = 0.03, aggression = 0.8, bluff = 0.08, trap = 0.1, size = [0.6, 0.9]},
	Style.MANIAC: {play = 0.7, raise = 1.1, margin = -0.08, aggression = 0.9, bluff = 0.25, trap = 0.0, size = [0.7, 1.3]},
	Style.NIT: {play = 1.45, raise = 1.8, margin = 0.12, aggression = 0.6, bluff = 0.0, trap = 0.2, size = [0.5, 0.7]},
	Style.TRAPPER: {play = 1.0, raise = 1.4, margin = 0.0, aggression = 0.7, bluff = 0.04, trap = 0.65, size = [0.7, 1.1]},
	Style.BLUFFER: {play = 0.9, raise = 1.3, margin = 0.02, aggression = 0.7, bluff = 0.35, trap = 0.0, size = [0.8, 1.2]},
	Style.GAMBLER: {play = 0.8, raise = 1.25, margin = -0.05, aggression = 0.8, bluff = 0.15, trap = 0.0, size = [1.5, 3.0]},
}

## Seat fillers: each has a main style and 2-3 moods.
const CHARACTERS := [
	{name = "Rosa", main = Style.ROCK, moods = [Style.GRINDER, Style.TRAPPER]},
	{name = "Big Tony", main = Style.MANIAC, moods = [Style.GAMBLER, Style.CALLING_STATION]},
	{name = "Mila", main = Style.GRINDER, moods = [Style.TRAPPER, Style.BLUFFER]},
	{name = "Dex", main = Style.CALLING_STATION, moods = [Style.MANIAC, Style.ROCK]},
	{name = "Hank", main = Style.NIT, moods = [Style.ROCK, Style.GAMBLER]},
	{name = "Lou", main = Style.TRAPPER, moods = [Style.GRINDER, Style.NIT]},
	{name = "Vera", main = Style.BLUFFER, moods = [Style.MANIAC, Style.GRINDER, Style.ROCK]},
	{name = "Gus", main = Style.GAMBLER, moods = [Style.MANIAC, Style.CALLING_STATION]},
	{name = "Priya", main = Style.GRINDER, moods = [Style.NIT, Style.BLUFFER]},
	{name = "Old Walt", main = Style.NIT, moods = [Style.CALLING_STATION, Style.TRAPPER]},
	{name = "Jules", main = Style.CALLING_STATION, moods = [Style.BLUFFER, Style.GAMBLER]},
	{name = "Kiki", main = Style.MANIAC, moods = [Style.BLUFFER, Style.TRAPPER, Style.GAMBLER]},
]

## Minimum buy-in of each venue tier (GDD): Novice, Casual, Regular, Skilled, Shark, Pro.
const TIER_BUY_INS := [0, 4000, 20000, 80000, 400000, 2000000]
const TIER_NAMES := ["Novice", "Casual", "Regular", "Skilled", "Shark", "Pro"]

var character: Dictionary
var style: int
var level := 0  ## 0 Novice .. 5 Pro
var samples := 30  ## Monte Carlo runs per decision
var noise := 0.15  ## random error added to the equity estimate
var mistake := 0.12  ## chance to flip a call/fold decision
var bankroll := 0  ## chips left for rebuys at cash tables
var rng := RandomNumberGenerator.new()


func _init(who: Dictionary, skill := 0) -> void:
	character = who
	style = who.main
	level = clampi(skill, 0, 5)
	var f := level / 5.0
	samples = 30 + 70 * level
	noise = 0.15 * (1.0 - f)
	mistake = 0.12 * (1.0 - f)
	rng.randomize()


static func level_for(buy_in: int) -> int:
	var l := 0
	for i in TIER_BUY_INS.size():
		if buy_in >= TIER_BUY_INS[i]:
			l = i
	return l


## Picks this hand's style. `lost` is the share of its stack lost last hand.
func new_hand(stack: int, big_blind: int, lost: float) -> void:
	var chance := 0.15
	if lost >= 0.5:
		chance = 0.6  # tilted
	elif stack < big_blind * 15:
		chance = 0.4  # short-stacked
	style = character.moods[rng.randi() % character.moods.size()] if rng.randf() < chance else character.main


## Returns [action, amount] for PokerTable.act().
func decide(table: PokerTable, seat: int) -> Array:
	var p: Dictionary = PROFILES[style]
	var me = table.seats[seat]
	var la := table.legal_actions()
	var opponents := 0
	for i in PokerTable.MAX_SEATS:
		if i != seat and table.seats[i] and table.seats[i].in_hand:
			opponents += 1
	var eq := clampf(equity(me.hole, table.board, opponents) + rng.randf_range(-noise, noise), 0.0, 1.0)
	var strength := eq * (opponents + 1)
	var call: int = la.call

	if la.can_raise:
		var strong: bool = strength >= p.raise and rng.randf() < p.aggression
		if strong and table.street != PokerTable.Street.RIVER and rng.randf() < p.trap:
			return ["check" if call == 0 else "call", 0]  # slow-play
		if strong or rng.randf() < p.bluff:
			return ["raise", _raise_to(table, la)]
	if call == 0:
		return ["check", 0]
	var pot_odds := float(call) / (table.pot() + call)
	var preflop := table.street == PokerTable.Street.PREFLOP
	# Pre-flop equity against every random hand is pessimistic, so small calls ride on strength alone.
	var priced_in: bool = eq >= pot_odds + p.margin or (preflop and call <= table.big_blind * 4)
	var good: bool = (strength >= p.play or not preflop) and priced_in
	if rng.randf() < mistake:
		good = not good
	if good:
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
	var size: Array = PROFILES[style].size
	var to := table.current_bet + int(pot_after_call * rng.randf_range(size[0], size[1]))
	to = roundi(float(to) / table.small_blind) * table.small_blind
	if to >= la.max_raise_to * 0.8:
		to = la.max_raise_to  # close to all-in anyway: shove
	return clampi(to, la.min_raise_to, la.max_raise_to)
