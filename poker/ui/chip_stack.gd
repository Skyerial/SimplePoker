class_name ChipStack
extends Control
## Chips for an amount. Bets and the pot use as few chips as possible; a player's own stack
## (`spread`) is split like a cashier would, with some of every smaller chip, so it holds the same
## chips they bet with and grows into more and taller piles as they win.

# Preloaded: a texture loaded inside _draw() is freed before the frame renders.
const DENOMS := [
    [5000, preload("res://assets/Chips/chips_stacked_blue.png")],
    [1000, preload("res://assets/Chips/chips_stacked_orange.png")],
    [500, preload("res://assets/Chips/chips_stacked_purple.png")],
    [100, preload("res://assets/Chips/chips_stacked_black.png")],
    [25, preload("res://assets/Chips/chips_stacked_green.png")],
    [5, preload("res://assets/Chips/chips_stacked_red.png")],
    [1, preload("res://assets/Chips/chips_stacked_white.png")],
]
const CHIP := 30.0
const STEP := 4.0  ## how far each chip sits above the one below
const ROW_UP := 14.0  ## each row further back sits this much higher
const LABEL := 18.0

var spread := false
var per_row := 4
var max_rows := 3  ## rows further back, for big stacks
var max_tall := 8  ## chips per pile
const SPREAD_PILE := 8  ## how many of each small chip a spread stack aims for
var show_amount := true
var amount := 0:
    set(v):
        amount = v
        visible = v > 0
        queue_redraw()

func _init(p_spread := false, p_per_row := 4, p_max_rows := 3, p_max_tall := 8) -> void:
    spread = p_spread
    per_row = p_per_row
    max_rows = p_max_rows
    max_tall = p_max_tall
    custom_minimum_size = Vector2(CHIP * (per_row + 0.5), _base_y() + CHIP + LABEL)
    mouse_filter = MOUSE_FILTER_IGNORE

## Chip counts per DENOMS entry, adding up to `value`.
static func breakdown(value: int, p_spread: bool) -> Array:
    var counts := []
    counts.resize(DENOMS.size())
    counts.fill(0)
    var left := value
    if not p_spread:
        for i in DENOMS.size():
            counts[i] = left / DENOMS[i][0]
            left -= counts[i] * DENOMS[i][0]
        return counts
    # Smallest first: take what the next chip up can't cover, then whole "colour-ups" of it
    # while the pile stays short. Whatever is left goes to the bigger chips.
    for i in range(DENOMS.size() - 1, -1, -1):
        var d: int = DENOMS[i][0]
        if i == 0:
            counts[i] = left / d
        else:
            var per_next: int = DENOMS[i - 1][0] / d
            var n: int = (left / d) % per_next
            while n + per_next <= SPREAD_PILE and (n + per_next) * d <= left:
                n += per_next
            counts[i] = n
        left -= counts[i] * d
    return counts

func _base_y() -> float:
    return STEP * max_tall + ROW_UP * (max_rows - 1)

## [[x, y of the bottom chip, chip count, texture], ...] in drawing order (back rows first).
func _piles() -> Array:
    var columns := []
    var counts := breakdown(amount, spread)
    for i in DENOMS.size():
        var n: int = counts[i]
        while n > 0 and columns.size() < per_row * max_rows:
            columns.append([mini(n, max_tall), DENOMS[i][1]])
            n -= max_tall
    var piles := []
    var rows := ceili(columns.size() / float(per_row))
    for r in range(rows - 1, -1, -1):
        var row := columns.slice(r * per_row, (r + 1) * per_row)
        var x := (size.x - row.size() * CHIP) / 2 + (CHIP / 2 if r % 2 else 0.0)
        for col in row:
            piles.append([x, _base_y() - r * ROW_UP, col[0], col[1]])
            x += CHIP
    return piles

## The part that actually gets drawn (chips and amount), in local coordinates.
func visual_rect() -> Rect2:
    var r := Rect2(size.x / 2 - 22, _base_y(), 44, CHIP + (LABEL if show_amount else 0.0))
    for p in _piles():
        r = r.merge(Rect2(p[0], p[1] - (p[2] - 1) * STEP, CHIP, CHIP))
    return r

func _draw() -> void:
    for p in _piles():
        for k in p[2]:
            draw_texture_rect(p[3], Rect2(p[0], p[1] - k * STEP, CHIP, CHIP), false)
    if show_amount:
        draw_string(get_theme_default_font(), Vector2(0, _base_y() + CHIP + 14), str(amount),
            HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color.WHITE)
