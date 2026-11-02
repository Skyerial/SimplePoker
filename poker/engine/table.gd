class_name PokerTable
extends RefCounted
## Authoritative No-Limit Texas Hold'em table. Pure logic: no nodes, no
## rendering, no networking. Views and bots read the state and listen to `event`.

signal event(e: Dictionary)

const MAX_SEATS := 6
enum Street { PREFLOP, FLOP, TURN, RIVER, SHOWDOWN }


class Seat:
    var name := ""
    var stack := 0
    var is_bot := false
    var hole := []
    var in_hand := false  ## dealt in and not folded
    var all_in := false
    var bet := 0  ## chips put in on this strdww deet
    var total := 0  ## chips put in this hand
    var acted := false  ## acted since the last full raise

    func _init(player_name: String, chips: int, bot: bool) -> void:
        name = player_name
        stack = chips
        is_bot = bot


var seats := []
var small_blind: int
var big_blind: int
var ante := 0  ## dead money from every player before the blinds (tournaments)
var button := -1
var sb_seat := -1
var bb_seat := -1
var board := []
var street: int = Street.PREFLOP
var to_act := -1
var current_bet := 0
var min_raise := 0
var last_aggressor := -1
var hand_running := false
var hand_number := 0
var rng := RandomNumberGenerator.new()
var _deck := []


func _init(sb := 10, bb := 20) -> void:
    small_blind = sb
    big_blind = bb
    seats.resize(MAX_SEATS)


func sit(i: int, player_name: String, chips: int, bot := false) -> void:
    assert(seats[i] == null)
    seats[i] = Seat.new(player_name, chips, bot)


## Only between hands. Returns the chips the player leaves with.
func stand(i: int) -> int:
    assert(not hand_running)
    var chips: int = seats[i].stack
    seats[i] = null
    return chips


func pot() -> int:
    var sum := 0
    for s in seats:
        if s:
            sum += s.total
    return sum


## What the player to act may do. Amounts for raises are "raise to" totals for this street.
func legal_actions() -> Dictionary:
    var s: Seat = seats[to_act]
    var max_to := s.bet + s.stack
    var others_can_act := _count(func(i): return i != to_act and _can_act(i))
    return {
        call = mini(current_bet - s.bet, s.stack),
        can_raise = not s.acted and max_to > current_bet and others_can_act > 0,
        min_raise_to = mini(current_bet + min_raise, max_to),
        max_raise_to = max_to,
    }


## `stacked` is a test hook: cards in the order they are dealt.
func start_hand(stacked := []) -> bool:
    if hand_running:
        return false
    var players := range(MAX_SEATS).filter(func(i): return seats[i] != null and seats[i].stack > 0)
    if players.size() < 2:
        return false

    hand_number += 1
    hand_running = true
    board.clear()
    street = Street.PREFLOP
    last_aggressor = -1
    for s in seats:
        if s:
            s.hole.clear()
            s.in_hand = false
            s.all_in = false
            s.bet = 0
            s.total = 0
            s.acted = false
    for i in players:
        seats[i].in_hand = true

    button = _next(button, _in_hand)
    # Heads-up the button posts the small blind.
    sb_seat = button if players.size() == 2 else _next(button, _in_hand)
    bb_seat = _next(sb_seat, _in_hand)
    if stacked:
        _deck = stacked.duplicate()
        _deck.reverse()
    else:
        _deck = Cards.new_deck(rng)

    event.emit({type = "hand_start", hand = hand_number, button = button})
    if ante > 0:
        for i in players:
            var s: Seat = seats[i]
            var n := mini(ante, s.stack)
            s.stack -= n
            s.total += n
            s.all_in = s.stack == 0
        event.emit({type = "ante", amount = ante})
    _post(sb_seat, small_blind)
    _post(bb_seat, big_blind)
    current_bet = big_blind
    min_raise = big_blind

    var first := _next(button, _in_hand)
    for _round in 2:
        var i := first
        for _p in players.size():
            seats[i].hole.append(_deck.pop_back())
            i = _next(i, _in_hand)
    event.emit({type = "deal"})
    _advance(bb_seat)
    return true


## action: "fold", "check", "call" or "raise" (amount = raise-to total, also used to bet).
func act(i: int, action: String, amount := 0) -> bool:
    if not hand_running or i != to_act:
        return false
    var s: Seat = seats[i]
    var la := legal_actions()
    var kind := action
    match action:
        "fold":
            s.in_hand = false
        "check":
            if la.call > 0:
                return false
        "call":
            if la.call == 0:
                return false
            _put(s, la.call)
        "raise":
            if not la.can_raise or amount < la.min_raise_to or amount > la.max_raise_to:
                return false
            kind = "bet" if current_bet == 0 else "raise"
            var raise_size := amount - current_bet
            _put(s, amount - s.bet)
            # An all-in for less than a full raise doesn't reopen betting.
            if raise_size >= min_raise:
                min_raise = raise_size
                for o in seats:
                    if o:
                        o.acted = false
            current_bet = amount
            last_aggressor = i
        _:
            return false
    s.acted = true
    event.emit({type = "action", seat = i, action = kind, to = s.bet, all_in = s.all_in})
    _advance(i)
    return true


func _advance(from: int) -> void:
    if _count(_in_hand) == 1:
        _award_uncontested()
        return
    var n := _next(from, _needs_action)
    # A lone player who isn't facing a bet has nobody left to bet against.
    var lone_matched: bool = n != -1 and _count(_can_act) == 1 and seats[n].bet >= current_bet
    if n != -1 and not lone_matched:
        to_act = n
        event.emit({type = "turn", seat = n})
        return
    _end_street()


func _end_street() -> void:
    to_act = -1
    for s in seats:
        if s:
            s.bet = 0
            s.acted = false
    current_bet = 0
    min_raise = big_blind
    if street == Street.RIVER:
        _showdown()
        return
    street += 1
    _deck.pop_back()  # burn
    for _c in (3 if street == Street.FLOP else 1):
        board.append(_deck.pop_back())
    last_aggressor = -1
    event.emit({type = "board", street = street, cards = board.duplicate()})
    if _count(_can_act) < 2:
        _end_street()  # everyone is all-in: run the board out
    else:
        _advance(button)


func _showdown() -> void:
    street = Street.SHOWDOWN
    var first := last_aggressor if _in_hand(last_aggressor) else _next(button, _in_hand)
    var order := []
    var scores := {}
    var i := first
    for _n in _count(_in_hand):
        order.append(i)
        scores[i] = Cards.evaluate(seats[i].hole + board)
        i = _next(i, _in_hand)
    event.emit({type = "showdown", order = order, scores = scores})

    _return_uncalled()
    var pots := _build_pots()
    for n in pots.size():
        var p: Dictionary = pots[n]
        var best: int = p.eligible.map(func(e): return scores[e]).max()
        # Winners in seat order from the button's left, so odd chips go there first.
        var winners := []
        var j := button
        for _k in MAX_SEATS:
            j = (j + 1) % MAX_SEATS
            if p.eligible.has(j) and scores[j] == best:
                winners.append(j)
        @warning_ignore("integer_division")
        var share: int = p.amount / winners.size()
        var odd: int = p.amount % winners.size()
        for k in winners.size():
            var won: int = share + (1 if k < odd else 0)
            seats[winners[k]].stack += won
            event.emit({type = "pot_award", seat = winners[k], amount = won, pot = n, pots = pots.size(),
                    score = best, split = winners.size() > 1})
    _finish()


## Main pot and side pots, each {amount, eligible seats}.
func _build_pots() -> Array:
    var levels := []
    for s in seats:
        if s and s.in_hand and not levels.has(s.total):
            levels.append(s.total)
    levels.sort()
    var pots := []
    var prev := 0
    var collected := 0
    for level in levels:
        var amount := 0
        var eligible := []
        for i in MAX_SEATS:
            var s: Seat = seats[i]
            if s == null:
                continue
            amount += clampi(s.total, prev, level) - prev
            if s.in_hand and s.total >= level:
                eligible.append(i)
        if amount > 0:
            pots.append({amount = amount, eligible = eligible})
        collected += amount
        prev = level
    pots[-1].amount += pot() - collected  # folded chips above the last live level
    return pots


func _award_uncontested() -> void:
    _return_uncalled()
    var w := _next(-1, _in_hand)
    var amount := pot()
    seats[w].stack += amount
    event.emit({type = "pot_award", seat = w, amount = amount, uncontested = true, pot = 0, pots = 1})
    _finish()


## The part of the biggest bet nobody else matched goes back to its owner before the pots are paid.
func _return_uncalled() -> void:
    var top := -1
    var second := 0
    for i in MAX_SEATS:
        var s: Seat = seats[i]
        if s == null:
            continue
        if top == -1 or s.total > seats[top].total:
            if top != -1:
                second = maxi(second, seats[top].total)
            top = i
        else:
            second = maxi(second, s.total)
    var extra: int = seats[top].total - second if top != -1 else 0
    if extra > 0:
        seats[top].total -= extra
        seats[top].stack += extra
        event.emit({type = "returned", seat = top, amount = extra})


func _finish() -> void:
    for s in seats:
        if s:
            s.bet = 0
            s.total = 0
    hand_running = false
    to_act = -1
    event.emit({type = "hand_end", hand = hand_number})


func _post(i: int, amount: int) -> void:
    _put(seats[i], amount)
    event.emit({type = "blind", seat = i, amount = seats[i].bet})


func _put(s: Seat, n: int) -> void:
    n = mini(n, s.stack)
    s.stack -= n
    s.bet += n
    s.total += n
    if s.stack == 0:
        s.all_in = true


## Next seat clockwise after `from` matching `pred`, wrapping around to `from` itself last.
func _next(from: int, pred: Callable) -> int:
    for k in range(1, MAX_SEATS + 1):
        var i := (from + k) % MAX_SEATS
        if pred.call(i):
            return i
    return -1


func _count(pred: Callable) -> int:
    var n := 0
    for i in MAX_SEATS:
        if pred.call(i):
            n += 1
    return n


func _in_hand(i: int) -> bool:
    return i >= 0 and seats[i] != null and seats[i].in_hand


func _can_act(i: int) -> bool:
    return _in_hand(i) and not seats[i].all_in


func _needs_action(i: int) -> bool:
    return _can_act(i) and (not seats[i].acted or seats[i].bet < current_bet)
