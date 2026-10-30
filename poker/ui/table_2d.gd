extends Control
## 2D table: you in seat 0 against five bots. Also runs the local game loop
## (bot turns, next hand) until networking takes that over in milestone 2.

const HUMAN := 0
const START_STACK := 2000
const BOT_NAMES := ["Rosa", "Big Tony", "Mila", "Dex", "Hank"]
const BOT_DELAY := 0.7
const NEXT_HAND_DELAY := 3.0
const STREET_NAMES := ["Pre-flop", "Flop", "Turn", "River"]
const FELT := Color("1f6b3a")
const RAIL := Color("4a2c17")

var table := PokerTable.new(10, 20)
var bots := {}  # seat -> PokerBot
var revealed := {}  # seat -> true once shown at showdown
var last_action := {}  # seat -> text under the name

var card_font := SystemFont.new()
var seat_boxes := []
var seat_info := []
var seat_cards := []
var center: VBoxContainer
var pot_label: Label
var board_cards: RichTextLabel
var hint_label: Label
var rebuy_btn: Button
var log_box: RichTextLabel
var action_bar: HBoxContainer
var fold_btn: Button
var call_btn: Button
var raise_slider: HSlider
var raise_btn: Button
var preset_btns := []


func _ready() -> void:
	card_font.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
	table.rng.randomize()
	table.sit(HUMAN, "You", START_STACK)
	for i in range(1, PokerTable.MAX_SEATS):
		table.sit(i, BOT_NAMES[i - 1], START_STACK, true)
		bots[i] = PokerBot.new((i - 1) % 4)
	_build_ui()
	table.event.connect(_on_event)
	resized.connect(_layout)
	_next_hand()


func _on_event(e: Dictionary) -> void:
	match e.type:
		"hand_start":
			revealed.clear()
			last_action.clear()
			_log("\n[b]Hand #%d[/b]" % e.hand)
		"blind":
			last_action[e.seat] = "posts %d" % e.amount
		"action":
			var text := _action_text(e)
			last_action[e.seat] = text
			_log("%s %s" % [table.seats[e.seat].name, text])
		"board":
			last_action.clear()
			_log("[b]%s:[/b] %s" % [STREET_NAMES[e.street], _cards_bb(e.cards)])
		"turn":
			if bots.has(e.seat):
				get_tree().create_timer(BOT_DELAY).timeout.connect(_bot_turn.bind(e.seat, table.hand_number))
		"showdown":
			for seat in e.order:
				revealed[seat] = true
				_log("%s shows %s (%s)" % [table.seats[seat].name, _cards_bb(table.seats[seat].hole), Cards.describe(e.scores[seat])])
		"pot_award":
			_log("[color=#f0c040]%s wins %d[/color]" % [table.seats[e.seat].name, e.amount])
		"hand_end":
			get_tree().create_timer(NEXT_HAND_DELAY).timeout.connect(_next_hand)
	_refresh()


func _next_hand() -> void:
	if table.hand_running:
		return
	for i in bots:
		if table.seats[i].stack == 0:
			table.seats[i].stack = START_STACK  # bots get a fresh stack from the house
			_log("%s rebuys" % table.seats[i].name)
	if table.seats[HUMAN].stack == 0:
		_refresh()  # wait for the Rebuy button
		return
	table.start_hand()


func _bot_turn(seat: int, hand: int) -> void:
	if not table.hand_running or table.hand_number != hand or table.to_act != seat:
		return
	var d: Array = bots[seat].decide(table, seat)
	if not table.act(seat, d[0], d[1]):
		push_error("Bot made an illegal move: %s" % [d])
		table.act(seat, "check" if table.legal_actions().call == 0 else "fold")


func _human(action: String, amount := 0) -> void:
	table.act(HUMAN, action, amount)


func _rebuy() -> void:
	table.seats[HUMAN].stack = START_STACK
	_next_hand()


# --- view ---------------------------------------------------------------

func _refresh() -> void:
	for i in PokerTable.MAX_SEATS:
		var s = table.seats[i]
		seat_boxes[i].visible = s != null
		if s == null:
			continue
		var lines := [s.name + (" (D)" if i == table.button else ""), str(s.stack), last_action.get(i, "")]
		seat_info[i].text = "\n".join(lines)
		var cards := ""
		if not s.hole.is_empty() and (s.in_hand or revealed.has(i)):
			cards = _cards_bb(s.hole) if i == HUMAN or revealed.has(i) else "[bgcolor=#2a3f8f]    [/bgcolor] [bgcolor=#2a3f8f]    [/bgcolor]"
		seat_cards[i].text = "[center]%s[/center]" % cards
		seat_boxes[i].modulate.a = 1.0 if s.in_hand or not table.hand_running else 0.45
		seat_boxes[i].self_modulate = Color(1.6, 1.4, 0.5) if i == table.to_act else Color.WHITE

	pot_label.text = "Pot %d" % table.pot() if table.pot() > 0 else ""
	board_cards.text = "[center]%s[/center]" % _cards_bb(table.board)
	var me = table.seats[HUMAN]
	hint_label.text = Cards.describe(Cards.evaluate(me.hole + table.board)) if me.in_hand and table.board.size() >= 3 else ""
	rebuy_btn.visible = not table.hand_running and me.stack == 0

	var my_turn := table.hand_running and table.to_act == HUMAN
	action_bar.visible = my_turn
	if my_turn:
		var la := table.legal_actions()
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
		raise_btn.text = ("Bet %d" if table.current_bet == 0 else "Raise to %d") % to


func _preset(pot_fraction: float) -> void:
	var la := table.legal_actions()
	raise_slider.value = table.current_bet + (table.pot() + la.call) * pot_fraction


func _action_text(e: Dictionary) -> String:
	var text: String = {
		"fold": "folds",
		"check": "checks",
		"call": "calls %d" % e.to,
		"bet": "bets %d" % e.to,
		"raise": "raises to %d" % e.to,
	}[e.action]
	return text + (" (all-in)" if e.all_in else "")


func _cards_bb(cards: Array) -> String:
	var parts := []
	for c in cards:
		var color := "#c62828" if Cards.suit(c) in [1, 2] else "#111111"
		parts.append("[bgcolor=#f4f1e8][color=%s] %s [/color][/bgcolor]" % [color, Cards.to_str(c)])
	return " ".join(parts)


func _log(text: String) -> void:
	log_box.append_text(text + "\n")


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
	for i in PokerTable.MAX_SEATS:
		# Seat 0 at the bottom, then clockwise (to your left) around the table.
		var a := PI / 2 + i * TAU / PokerTable.MAX_SEATS
		var box: Control = seat_boxes[i]
		box.position = c + Vector2(cos(a) * r.x * 1.12, sin(a) * r.y * 1.25) - box.size / 2
	center.position = c - center.size / 2
	action_bar.position = Vector2((size.x - action_bar.size.x) / 2, size.y - action_bar.size.y - 12)
	log_box.position = Vector2(12, 12)
	log_box.size = Vector2(minf(340, size.x * 0.3), size.y * 0.4)
	queue_redraw()


func _build_ui() -> void:
	for i in PokerTable.MAX_SEATS:
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(150, 0)
		var v := VBoxContainer.new()
		var info := Label.new()
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var cards := _card_label(22, 150)
		v.add_child(info)
		v.add_child(cards)
		box.add_child(v)
		add_child(box)
		seat_boxes.append(box)
		seat_info.append(info)
		seat_cards.append(cards)

	center = VBoxContainer.new()
	pot_label = Label.new()
	pot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pot_label.add_theme_font_size_override("font_size", 22)
	board_cards = _card_label(30, 340)
	hint_label = Label.new()
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rebuy_btn = Button.new()
	rebuy_btn.text = "Out of chips: rebuy %d" % START_STACK
	rebuy_btn.pressed.connect(_rebuy)
	for n in [pot_label, board_cards, hint_label, rebuy_btn]:
		center.add_child(n)
	add_child(center)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_override("normal_font", card_font)
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_font_size_override("bold_font_size", 13)
	add_child(log_box)

	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 8)
	fold_btn = Button.new()
	fold_btn.text = "Fold"
	fold_btn.pressed.connect(_human.bind("fold"))
	call_btn = Button.new()
	call_btn.pressed.connect(func(): _human("check" if table.legal_actions().call == 0 else "call"))
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
	raise_btn.pressed.connect(func(): _human("raise", int(raise_slider.value)))
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
