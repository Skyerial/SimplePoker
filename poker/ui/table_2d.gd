extends Control
## 2D table. Draws whatever Game.view says and sends your clicks to Game,
## so it works the same online and against bots.
## You always sit at the bottom; the others follow clockwise.

const FELT := Color("1f6b3a")
const RAIL := Color("4a2c17")
const CARD_BACK := "[bgcolor=#2a3f8f]    [/bgcolor]"
const EMOTE_TIME := 3.0

var card_font := SystemFont.new()
var seat_boxes := []
var seat_info := []
var seat_cards := []
var seat_timers := []
var seat_emotes := []
var center: VBoxContainer
var pot_label: Label
var board_cards: RichTextLabel
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
        var lines := [s.name + (" (D)" if i == v.button else ""), str(s.stack), s.note]
        seat_info[i].text = "\n".join(lines)
        seat_cards[i].text = "[center]%s[/center]" % _cards_bb(s.cards)
        seat_boxes[i].modulate.a = 1.0 if s.in_hand or not v.hand_running else 0.45
        seat_boxes[i].self_modulate = Color(1.6, 1.4, 0.5) if i == v.to_act else Color.WHITE

    pot_label.text = "Pot %d" % v.pot if v.get("pot", 0) > 0 else ""
    board_cards.text = "[center]%s[/center]" % _cards_bb(v.get("board", []))
    hint_label.text = v.get("hint", "")
    status_label.text = v.get("status", "")
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
func _cards_bb(cards: Array) -> String:
    var parts := []
    for c in cards:
        if c < 0:
            parts.append(CARD_BACK)
            continue
        var color := "#c62828" if Cards.suit(c) in [1, 2] else "#111111"
        parts.append("[bgcolor=#f4f1e8][color=%s] %s [/color][/bgcolor]" % [color, Cards.to_str(c)])
    return " ".join(parts)


func _felt_center() -> Vector2:
    return size / 2 - Vector2(0, 20)


func _felt_radius() -> Vector2:
    return Vector2(size.x * 0.32, size.y * 0.25)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("14181f"))
    var r := _felt_radius()
    draw_set_transform(_felt_center(), 0, Vector2(r.x / r.y, 1))
    draw_circle(Vector2.ZERO, r.y + 12, RAIL)
    draw_circle(Vector2.ZERO, r.y, FELT)
    draw_set_transform(Vector2.ZERO)


func _layout() -> void:
    var c := _felt_center()
    var r := _felt_radius()
    var me: int = maxi(Game.view.get("me", 0), 0)
    for i in PokerTable.MAX_SEATS:
        # Your seat at the bottom, then clockwise (to your left) around the table.
        var a := PI / 2 + (i - me) * TAU / PokerTable.MAX_SEATS
        var box: Control = seat_boxes[i]
        box.position = c + Vector2(cos(a) * r.x * 1.12, sin(a) * r.y * 1.25) - box.size / 2
    center.position = c - center.size / 2
    action_bar.position = Vector2((size.x - action_bar.size.x) / 2, size.y - action_bar.size.y - 12)
    var log_w := minf(340, size.x * 0.3)
    log_box.position = Vector2(12, 12)
    log_box.size = Vector2(log_w, size.y * 0.45)
    chat_edit.position = Vector2(12, 18 + log_box.size.y)
    chat_edit.size = Vector2(log_w, 0)
    top_bar.position = Vector2(size.x - top_bar.size.x - 12, 12)
    queue_redraw()


func _build_ui() -> void:
    for i in PokerTable.MAX_SEATS:
        var box := PanelContainer.new()
        box.custom_minimum_size = Vector2(150, 0)
        var v := VBoxContainer.new()
        var emote := Label.new()
        emote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        emote.add_theme_color_override("font_color", Color("ffd166"))
        emote.visible = false
        var info := Label.new()
        info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        var timer := Label.new()
        timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        timer.add_theme_color_override("font_color", Color("ff8a65"))
        var cards := _card_label(22, 150)
        for n in [emote, info, timer, cards]:
            v.add_child(n)
        box.add_child(v)
        add_child(box)
        seat_boxes.append(box)
        seat_info.append(info)
        seat_cards.append(cards)
        seat_timers.append(timer)
        seat_emotes.append(emote)

    center = VBoxContainer.new()
    pot_label = Label.new()
    pot_label.add_theme_font_size_override("font_size", 22)
    board_cards = _card_label(30, 340)
    hint_label = Label.new()
    status_label = Label.new()
    start_btn = Button.new()
    start_btn.text = "Start"
    start_btn.pressed.connect(Game.start_game)
    rebuy_btn = Button.new()
    rebuy_btn.pressed.connect(Game.rebuy)
    for n in [pot_label, board_cards, hint_label, status_label, start_btn, rebuy_btn]:
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


func _card_label(font_size: int, width: float) -> RichTextLabel:
    var l := RichTextLabel.new()
    l.bbcode_enabled = true
    l.fit_content = true
    l.scroll_active = false
    l.autowrap_mode = TextServer.AUTOWRAP_OFF
    l.custom_minimum_size = Vector2(width, 0)
    l.add_theme_font_override("normal_font", card_font)
    l.add_theme_font_size_override("normal_font_size", font_size)
    return l
