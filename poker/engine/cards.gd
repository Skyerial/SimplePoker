class_name Cards
## A card is an int 0..51: rank = card >> 2 (0 = deuce .. 12 = ace), suit = card & 3.

const RANKS := "23456789TJQKA"
const SUITS := ["♣", "♦", "♥", "♠"]
const CATEGORY_NAMES := [
	"High card", "Pair", "Two pair", "Three of a kind", "Straight",
	"Flush", "Full house", "Four of a kind", "Straight flush",
]


static func rank(card: int) -> int:
	return card >> 2


static func suit(card: int) -> int:
	return card & 3


static func to_str(card: int) -> String:
	return RANKS[rank(card)] + SUITS[suit(card)]


## "As" -> ace of spades. Suits are c, d, h, s.
static func parse(s: String) -> int:
	return RANKS.find(s[0]) * 4 + "cdhs".find(s[1])


static func parse_many(s: String) -> Array:
	var cards := []
	for part in s.split(" "):
		cards.append(parse(part))
	return cards


static func new_deck(rng: RandomNumberGenerator) -> Array:
	var deck := range(52)
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var t = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	return deck


## Scores the best 5-card hand out of 5-7 cards. Higher is better, equal is a tie.
## Layout: category in bits 20+, then up to five ranks of 4 bits each.
static func evaluate(cards: Array) -> int:
	var counts := PackedInt32Array()
	counts.resize(13)
	var suit_counts := PackedInt32Array()
	suit_counts.resize(4)
	var suit_masks := PackedInt32Array()
	suit_masks.resize(4)
	var mask := 0
	for c in cards:
		var r: int = c >> 2
		var s: int = c & 3
		counts[r] += 1
		suit_counts[s] += 1
		suit_masks[s] |= 1 << r
		mask |= 1 << r

	# With 7 cards a flush can't coexist with quads or a full house.
	for s in 4:
		if suit_counts[s] >= 5:
			var sf := _straight_high(suit_masks[s])
			if sf >= 0:
				return _pack(8, [sf])
			return _pack(5, _top_ranks(suit_masks[s], 5))

	var quads := -1
	var trips := []
	var pairs := []
	for r in range(12, -1, -1):
		match counts[r]:
			4: quads = r
			3: trips.append(r)
			2: pairs.append(r)

	if quads >= 0:
		return _pack(7, [quads] + _top_ranks(mask & ~(1 << quads), 1))
	if trips.size() > 0 and (trips.size() > 1 or pairs.size() > 0):
		var pair_rank: int = trips[1] if trips.size() > 1 else -1
		if pairs.size() > 0:
			pair_rank = maxi(pair_rank, pairs[0])
		return _pack(6, [trips[0], pair_rank])
	var straight := _straight_high(mask)
	if straight >= 0:
		return _pack(4, [straight])
	if trips.size() > 0:
		return _pack(3, [trips[0]] + _top_ranks(mask & ~(1 << trips[0]), 2))
	if pairs.size() >= 2:
		var rest: int = mask & ~(1 << pairs[0]) & ~(1 << pairs[1])
		return _pack(2, [pairs[0], pairs[1]] + _top_ranks(rest, 1))
	if pairs.size() == 1:
		return _pack(1, [pairs[0]] + _top_ranks(mask & ~(1 << pairs[0]), 3))
	return _pack(0, _top_ranks(mask, 5))


static func category(score: int) -> int:
	return score >> 20


static func describe(score: int) -> String:
	return CATEGORY_NAMES[category(score)]


static func _pack(cat: int, ranks: Array) -> int:
	var v := cat
	for i in 5:
		v = (v << 4) | (ranks[i] if i < ranks.size() else 0)
	return v


static func _top_ranks(m: int, n: int) -> Array:
	var out := []
	for r in range(12, -1, -1):
		if out.size() == n:
			break
		if m & (1 << r):
			out.append(r)
	return out


## Highest card of the best straight in a rank mask, 3 for the wheel (A-5), -1 if none.
static func _straight_high(m: int) -> int:
	for high in range(12, 3, -1):
		var need := 0b11111 << (high - 4)
		if (m & need) == need:
			return high
	if (m & 0b1111) == 0b1111 and (m & (1 << 12)):
		return 3
	return -1
