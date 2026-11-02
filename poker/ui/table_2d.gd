extends Control
## 2D table. Draws whatever Game.view says and sends your clicks to Game,
## so it works the same online and against bots.
## You always sit at the bottom; the others follow clockwise.

const FELT := Color("1d7430")
const FELT_MID := Color("34a046")
const RAIL := Color("6b3d22")
const RAIL_W := 26.0
const BAND := 110.0  ## felt between the edge and the betting line, where the cards and chips sit
const CARD_DIR := "res://assets/Cards/"
const CARD_BACK := preload("res://assets/Cards/card backs/blue_back_suits.png")
const SUIT_FILES := ["clubs", "diamond", "heart", "spade"]  # same order as Cards.SUITS
const SEAT_CARD := Vector2(60, 81)
const BOARD_CARD := Vector2(64, 86)
const EMOTE_TIME := 3.0

var card_font := SystemFont.new()
var seat_boxes := []
var seat_names := []
var seat_notes := []
var seat_avatars := []
var seat_stacks := []
var seat_cards := []
var seat_timers := []
var seat_emotes := []
var seat_bets := []
var center: VBoxContainer
var pot_label: Label
var pot_chips: ChipStack
var board_cards: HBoxContainer
var hint_label: Label
var status_label: Label
var start_btn: Button
var rebuy_btn: Button
var log_box: RichTextLabel
var chat_edit: LineEdit
var top_bar: HBoxContainer
var blinds_label: Label
var action_bar: HBoxContainer
var fold_btn: Button
var call_btn: Button
var raise_slider: HSlider
var raise_btn: Button
var preset_btns := []


func _ready() -> void:
    card_font.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
    _build_ui()
    Game.view_changed.connect(_refresh)
    Game.log_added.connect(func(t): log_box.append_text(t + "\n"))
    Game.emote_shown.connect(_show_emote)
    Game.closed.connect(func(_r): get_tree().change_scene_to_file("res://ui/lobby.tscn"))
    resized.connect(_layout)
    _refresh()


func _process(_delta: float) -> void:
    var v := Game.view
    for i in PokerTable.MAX_SEATS:
        var left := 0.0
        if v.get("deadline", 0) > 0 and v.to_act == i:
            left = (v.deadline - Time.get_ticks_msec()) / 1000.0
        seat_timers[i].visible = left > 0
        seat_timers[i].text = "%ds" % ceili(left)


func _leave() -> void:
    Game.leave()
    get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _show_emote(seat: int, emote: String) -> void:
    var l: Label = seat_emotes[seat]
    l.text = emote
    l.visible = true
    var shown := l.get_instance_id()
    get_tree().create_timer(EMOTE_TIME).timeout.connect(func():
        if is_instance_id_valid(shown) and l.text == emote:
            l.visible = false)


# --- view ---------------------------------------------------------------

func _refresh() -> void:
    var v := Game.view
    var seats: Array = v.get("seats", [])
    for i in PokerTable.MAX_SEATS:
        var s = seats[i] if i < seats.size() else null
        seat_boxes[i].visible = s != null
        if s == null:
            continue
        seat_names[i].text = s.name
        seat_notes[i].text = s.note
        seat_avatars[i].set_player(s.name, i == v.to_act, i == v.button,
            "SB" if i == v.get("sb", -1) else "BB" if i == v.get("bb", -1) else "")
        _show_cards(seat_cards[i], s.cards, SEAT_CARD)
        seat_stacks[i].amount = s.stack
        seat_bets[i].amount = s.get("bet", 0)
        var alpha := 1.0 if s.in_hand or not v.hand_running else 0.45
        seat_boxes[i].modulate.a = alpha
        seat_cards[i].modulate.a = alpha

    pot_label.text = "Pot %d" % v.pot if v.get("pot", 0) > 0 else ""
    # The pot includes this street's bets, which sit in front of the players until the street ends.
    var street := 0
    for s in seats:
        if s != null:
            street += s.get("bet", 0)
    pot_chips.amount = v.get("pot", 0) - street
    _show_cards(board_cards, v.get("board", []), BOARD_CARD)
    hint_label.text = v.get("hint", "")
    status_label.text = v.get("status", "")
    hint_label.visible = hint_label.text != ""  # empty labels still take up a line
    status_label.visible = status_label.text != ""
    start_btn.visible = v.get("can_start", false)
    rebuy_btn.visible = v.get("can_rebuy", false)
    rebuy_btn.text = "Out of chips: rebuy %d" % v.get("buy_in", 0)
    blinds_label.text = v.get("blinds", "")

    var la: Dictionary = v.get("legal", {})
    action_bar.visible = not la.is_empty()
    if not la.is_empty():
        call_btn.text = "Check" if la.call == 0 else "Call %d" % la.call
        for c in [raise_slider, raise_btn] + preset_btns:
            c.visible = la.can_raise
        raise_slider.min_value = la.min_raise_to
        raise_slider.max_value = la.max_raise_to
        raise_slider.value = la.min_raise_to
        _on_slider(raise_slider.value)
    _layout.call_deferred()


func _on_slider(value: float) -> void:
    var to := int(value)
    if to == int(raise_slider.max_value):
        raise_btn.text = "All-in %d" % to
    else:
        raise_btn.text = ("Bet %d" if Game.view.current_bet == 0 else "Raise to %d") % to


func _preset(pot_fraction: float) -> void:
    var v := Game.view
    raise_slider.value = v.current_bet + (v.pot + v.legal.call) * pot_fraction


## -1 is a face-down card.
## Reuses the card nodes: freeing and re-adding them on every refresh made the rows jump for a frame.
func _show_cards(box: HBoxContainer, cards: Array, card_size: Vector2) -> void:
    while box.get_child_count() > cards.size():
        var old := box.get_child(-1)
        box.remove_child(old)
        old.queue_free()
    while box.get_child_count() < cards.size():
        var t := TextureRect.new()
        t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        t.custom_minimum_size = card_size
        box.add_child(t)
    for i in cards.size():
        box.get_child(i).texture = CARD_BACK if cards[i] < 0 else _card_texture(cards[i])


func _card_texture(c: int) -> Texture2D:
    var r := Cards.rank(c)  # 0 = deuce .. 12 = ace; the files number ace 1, deuce 2 .. king 13
    var n := 1 if r == 12 else r + 2
    return load("%scard_%s_%d.png" % [CARD_DIR, SUIT_FILES[Cards.suit(c)], n])


func _log_width() -> float:
    return minf(300, size.x * 0.25)


## The whole table, rail included: a rounded-end oval right of the chat log.
func _table_rect() -> Rect2:
    var left := _log_width() + 84  # side margins: name plates on the curved ends stick out
    return Rect2(left, 50, size.x - left - 70, size.y - 140)  # and room for the action bar


func _felt_rect() -> Rect2:
    return _table_rect().grow(-RAIL_W)


## [point `t` (0..1) of the way round a rounded-end oval, the oval's perimeter],
## starting bottom middle and going clockwise (left first).
static func _track(r: Rect2, t: float) -> Array:
    var rad := minf(r.size.x, r.size.y) / 2
    var half := r.size.x / 2 - rad  # half the straight part
    var c := r.get_center()
    var perimeter := 4 * half + TAU * rad
    var s := fposmod(t, 1.0) * perimeter
    if s < half:
        return [c + Vector2(-s, rad), perimeter]
    s -= half
    if s < PI * rad:
        return [c + Vector2(-half, 0) + Vector2.from_angle(PI / 2 + s / rad) * rad, perimeter]
    s -= PI * rad
    if s < 2 * half:
        return [c + Vector2(-half + s, -rad), perimeter]
    s -= 2 * half
    if s < PI * rad:
        return [c + Vector2(half, 0) + Vector2.from_angle(-PI / 2 + s / rad) * rad, perimeter]
    s -= PI * rad
    return [c + Vector2(half - s, rad), perimeter]


func _oval(r: Rect2, color: Color, line_width := 0) -> void:
    var sb := StyleBoxFlat.new()
    sb.bg_color = color
    sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) / 2))
    sb.corner_detail = 32
    sb.anti_aliasing = true
    if line_width > 0:
        sb.draw_center = false
        sb.border_color = color
        sb.set_border_width_all(line_width)
    draw_style_box(sb, r)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("14181f"))
    var table := _table_rect()
    draw_style_box(_shadow_box(table), table)
    _oval(table, RAIL.darkened(0.35))
    _oval(table.grow(-3), RAIL)
    _oval(table.grow(-RAIL_W * 0.55), RAIL.lightened(0.08))
    var felt := _felt_rect()
    _oval(felt, FELT.darkened(0.35))
    # Felt brighter towards the middle, faked with shrinking ovals.
    var steps := 14
    var room := minf(felt.size.x, felt.size.y) / 2 - 8
    for k in steps:
        _oval(felt.grow(-6 - room * k / steps), FELT.lerp(FELT_MID, float(k) / (steps - 1)))
    _oval(felt.grow(-BAND), Color(1, 1, 1, 0.8), 2)


## How far a centred box of `box_size` reaches in direction `dir`.
static func _half_width(box_size: Vector2, dir: Vector2) -> float:
    return absf(dir.x) * box_size.x / 2 + absf(dir.y) * box_size.y / 2


func _shadow_box(r: Rect2) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color.TRANSPARENT
    sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) / 2))
    sb.shadow_color = Color(0, 0, 0, 0.5)
    sb.shadow_size = 18
    sb.shadow_offset = Vector2(0, 8)
    return sb


func _layout() -> void:
    var felt := _felt_rect()
    var lane := felt.grow(-BAND / 2)  # middle of the band between the edge and the line
    var me: int = maxi(Game.view.get("me", 0), 0)
    center.position = felt.get_center() - center.size / 2
    for i in PokerTable.MAX_SEATS:
        var shown: bool = seat_boxes[i].visible
        # Your seat at the bottom, then clockwise (to your left) around the table.
        var t := float(posmod(i - me, PokerTable.MAX_SEATS)) / PokerTable.MAX_SEATS
        var at := _track(lane, t)
        var cards: Control = seat_cards[i]
        # On the curved ends the cards sit diagonally and are too big for the band: nudge them
        # outward (over the rail) rather than across the betting line.
        var outward: Vector2 = (at[0] - felt.get_center()).normalized()
        at[0] += outward * maxf(0, _half_width(cards.size, outward) - BAND / 2 + 4)
        cards.position = at[0] - cards.size / 2
        cards.visible = shown
        seat_emotes[i].position = at[0] - seat_emotes[i].size / 2
        # Name plate off the table: on the rail's outer edge, or further out where the cards reach that far.
        var plate: Control = seat_boxes[i]
        var edge: float = (_track(_table_rect(), t)[0] - at[0]).length()
        var clear := _half_width(cards.size, outward) + _half_width(plate.size, outward) + 4
        plate.position = at[0] + outward * maxf(edge, clear) - plate.size / 2
        # The player's money sits in the band too, at their right hand.
        var stack: ChipStack = seat_stacks[i]
        var pile := stack.visual_rect()
        var gap: float = (cards.size.x / 2 + pile.size.x / 2 + 6) / at[1]
        stack.position = _track(lane, t - gap)[0] - pile.get_center()
        stack.visible = shown and stack.amount > 0
        # Bets go towards the middle, just clear of the cards, which puts them over the line.
        var bet: ChipStack = seat_bets[i]
        var inward: Vector2 = (felt.get_center() - at[0]).normalized()
        var chips := bet.visual_rect()
        var reach := _half_width(cards.size, inward) + _half_width(chips.size, inward) + 8
        bet.position = at[0] + inward * reach - chips.get_center()
        bet.visible = shown and bet.amount > 0
    action_bar.position = Vector2((size.x - action_bar.size.x) / 2, size.y - action_bar.size.y - 12)
    var log_w := _log_width()
    log_box.position = Vector2(12, 12)
    log_box.size = Vector2(log_w, size.y * 0.45)
    chat_edit.position = Vector2(12, 18 + log_box.size.y)
    chat_edit.size = Vector2(log_w, 0)
    top_bar.position = Vector2(size.x - top_bar.size.x - 12, 12)
    queue_redraw()


func _build_ui() -> void:
    for i in PokerTable.MAX_SEATS:
        # A seat is the cards on the felt plus a name plate out on the rail (seat_boxes).
        var cards := _card_row()
        cards.custom_minimum_size = Vector2(SEAT_CARD.x * 2 + 4, SEAT_CARD.y)
        add_child(cards)
        var emote := Label.new()
        emote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        emote.add_theme_color_override("font_color", Color("ffd166"))
        emote.add_theme_color_override("font_outline_color", Color.BLACK)
        emote.add_theme_constant_override("outline_size", 6)
        emote.add_theme_font_size_override("font_size", 20)
        emote.visible = false
        var plate := PanelContainer.new()
        var plate_bg := StyleBoxFlat.new()
        plate_bg.bg_color = Color(0, 0, 0, 0.55)
        plate_bg.set_corner_radius_all(22)
        plate_bg.content_margin_left = 4
        plate_bg.content_margin_right = 14
        plate_bg.content_margin_top = 3
        plate_bg.content_margin_bottom = 3
        plate.add_theme_stylebox_override("panel", plate_bg)
        var row := HBoxContainer.new()
        var avatar := Avatar.new()
        var text := VBoxContainer.new()
        text.add_theme_constant_override("separation", -4)
        text.alignment = BoxContainer.ALIGNMENT_CENTER
        var name_label := Label.new()
        var note := Label.new()
        note.add_theme_font_size_override("font_size", 13)
        note.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
        var timer := Label.new()
        timer.add_theme_font_size_override("font_size", 13)
        timer.add_theme_color_override("font_color", Color("ff8a65"))
        for n in [name_label, note, timer]:
            text.add_child(n)
        row.add_child(avatar)
        row.add_child(text)
        plate.add_child(row)
        add_child(plate)
        add_child(emote)  # after the cards so it shows on top of them
        seat_boxes.append(plate)
        seat_names.append(name_label)
        seat_notes.append(note)
        seat_avatars.append(avatar)
        var stack := ChipStack.new(true)
        add_child(stack)
        seat_stacks.append(stack)
        seat_cards.append(cards)
        seat_timers.append(timer)
        seat_emotes.append(emote)
        var bet := ChipStack.new(false, 7, 1, 5)  # flat, so it fits between the cards and the pot
        add_child(bet)
        seat_bets.append(bet)

    center = VBoxContainer.new()
    pot_label = Label.new()
    pot_label.add_theme_font_size_override("font_size", 22)
    pot_chips = ChipStack.new(false, 7, 1, 5)  # one flat row of short piles keeps the middle short
    pot_chips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    pot_chips.show_amount = false  # the pot label says it
    pot_chips.custom_minimum_size.y -= ChipStack.LABEL
    board_cards = _card_row()
    board_cards.custom_minimum_size.y = BOARD_CARD.y  # keeps the layout still before the flop
    hint_label = Label.new()
    status_label = Label.new()
    start_btn = Button.new()
    start_btn.text = "Start"
    start_btn.pressed.connect(Game.start_game)
    rebuy_btn = Button.new()
    rebuy_btn.pressed.connect(Game.rebuy)
    var pot_row := HBoxContainer.new()  # chips beside the label keeps the middle short enough to fit inside the line
    pot_row.alignment = BoxContainer.ALIGNMENT_CENTER
    pot_row.add_child(pot_chips)
    pot_row.add_child(pot_label)
    pot_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
    pot_label.size_flags_vertical = Control.SIZE_FILL
    for n in [pot_row, board_cards, hint_label, status_label, start_btn, rebuy_btn]:
        if n is Label:
            n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        center.add_child(n)
    add_child(center)

    log_box = RichTextLabel.new()
    log_box.bbcode_enabled = true
    log_box.scroll_following = true
    log_box.add_theme_font_override("normal_font", card_font)
    log_box.add_theme_font_size_override("normal_font_size", 13)
    log_box.add_theme_font_size_override("bold_font_size", 13)
    add_child(log_box)

    chat_edit = LineEdit.new()
    chat_edit.placeholder_text = "Chat (Enter to send)"
    chat_edit.max_length = 200
    chat_edit.text_submitted.connect(func(t):
        Game.send_chat(t)
        chat_edit.clear())
    add_child(chat_edit)

    top_bar = HBoxContainer.new()
    top_bar.add_theme_constant_override("separation", 12)
    blinds_label = Label.new()
    var emote_btn := MenuButton.new()
    emote_btn.text = "Emote"
    emote_btn.flat = false
    for e in TableRoom.EMOTES:
        emote_btn.get_popup().add_item(e)
    emote_btn.get_popup().id_pressed.connect(Game.send_emote)
    var leave_btn := Button.new()
    leave_btn.text = "Leave"
    leave_btn.pressed.connect(_leave)
    for n in [blinds_label, emote_btn, leave_btn]:
        top_bar.add_child(n)
    add_child(top_bar)

    action_bar = HBoxContainer.new()
    action_bar.add_theme_constant_override("separation", 8)
    fold_btn = Button.new()
    fold_btn.text = "Fold"
    fold_btn.pressed.connect(Game.act.bind("fold"))
    call_btn = Button.new()
    call_btn.pressed.connect(func(): Game.act("check" if Game.view.legal.call == 0 else "call"))
    raise_slider = HSlider.new()
    raise_slider.custom_minimum_size = Vector2(200, 0)
    raise_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    raise_slider.value_changed.connect(_on_slider)
    var track := StyleBoxFlat.new()  # the default track is nearly invisible on the dark background
    track.bg_color = Color(0.45, 0.45, 0.5)
    track.content_margin_top = 3
    track.content_margin_bottom = 3
    raise_slider.add_theme_stylebox_override("slider", track)
    raise_btn = Button.new()
    raise_btn.custom_minimum_size = Vector2(130, 0)
    raise_btn.pressed.connect(func(): Game.act("raise", int(raise_slider.value)))
    action_bar.add_child(fold_btn)
    action_bar.add_child(call_btn)
    for preset in [["½ Pot", 0.5], ["¾ Pot", 0.75], ["Pot", 1.0], ["All-in", 1000.0]]:
        var b := Button.new()
        b.text = preset[0]
        b.pressed.connect(_preset.bind(preset[1]))
        action_bar.add_child(b)
        preset_btns.append(b)
    action_bar.add_child(raise_slider)
    action_bar.add_child(raise_btn)
    for b in action_bar.get_children():
        b.custom_minimum_size.y = 44
    add_child(action_bar)


func _card_row() -> HBoxContainer:
    var b := HBoxContainer.new()
    b.alignment = BoxContainer.ALIGNMENT_CENTER
    b.add_theme_constant_override("separation", 4)
    return b


## Round player picture: res://assets/avatars/<name>.png if there is one, else their first letter.
class Avatar extends Control:
    const SIZE := 40.0
    var player := ""
    var picture: Texture2D  ## held here: a texture loaded inside _draw() is freed before the frame renders
    var active := false
    var dealer := false
    var blind := ""  ## "SB", "BB" or ""

    func _init() -> void:
        custom_minimum_size = Vector2(SIZE, SIZE)

    func set_player(p_name: String, p_active: bool, p_dealer: bool, p_blind := "") -> void:
        if p_name != player:
            player = p_name
            var path := "res://assets/avatars/%s.png" % p_name.to_lower().validate_filename()
            picture = load(path) if ResourceLoader.exists(path) else null
        active = p_active
        dealer = p_dealer
        blind = p_blind
        queue_redraw()

    func _draw() -> void:
        var c := size / 2
        var r := SIZE / 2
        if active:
            draw_circle(c, r + 3, Color("ffd166"), true, -1, true)
        if picture:
            draw_texture_rect(picture, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false)
        else:
            var hue := float(player.hash() % 360) / 360.0
            draw_circle(c, r, Color.from_hsv(hue, 0.45, 0.7), true, -1, true)
            var letter := player.left(1).to_upper()
            draw_string(get_theme_default_font(), Vector2(0, c.y + 8), letter, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)
        if dealer:
            var d := c + Vector2(r, r) * 0.72
            draw_circle(d, 9, Color.WHITE, true, -1, true)
            draw_string(get_theme_default_font(), d + Vector2(-9, 5), "D", HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Color.BLACK)
        if blind:
            var b := c + Vector2(-r, r) * 0.72
            draw_circle(b, 10, Color("3a86ff") if blind == "SB" else Color("ffbe0b"), true, -1, true)
            draw_string(get_theme_default_font(), b + Vector2(-10, 4), blind, HORIZONTAL_ALIGNMENT_CENTER, 20, 10, Color.WHITE if blind == "SB" else Color.BLACK)
