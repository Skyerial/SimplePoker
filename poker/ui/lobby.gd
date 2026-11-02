extends Control
## Start screen: play against bots, or log in to the game server and pick or
## create a table there. The table settings serve both.

const SAVE := "user://lobby.cfg"

var cfg := ConfigFile.new()
var name_edit: LineEdit
var server_edit: LineEdit
var password_edit: LineEdit
var mode_opt: OptionButton
var speed_opt: OptionButton
var bb_spin: SpinBox
var stack_spin: SpinBox
var bots_spin: SpinBox
var timer_spin: SpinBox
var login_box: VBoxContainer
var tables_box: VBoxContainer
var account_label: Label
var table_list: ItemList
var error_label: Label


func _ready() -> void:
	cfg.load(SAVE)
	var bg := ColorRect.new()
	bg.color = Color("14181f")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	# Two columns side by side, so everything fits the default window height.
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	var box := VBoxContainer.new()
	var online := VBoxContainer.new()
	for col in [box, online]:
		col.custom_minimum_size = Vector2(460, 0)
		col.add_theme_constant_override("separation", 10)
		cols.add_child(col)
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(PRESET_FULL_RECT)
	wrap.add_child(page)
	add_child(wrap)

	var title := Label.new()
	title.text = "Poker"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(title)
	page.add_child(cols)

	name_edit = LineEdit.new()
	name_edit.max_length = 16
	name_edit.text = cfg.get_value("lobby", "name", "")
	name_edit.placeholder_text = "Your name"
	box.add_child(_row("Name", name_edit))

	box.add_child(_heading("Table settings"))
	mode_opt = _options(["Cash game", "Tournament"])
	box.add_child(_row("Mode", mode_opt))
	bb_spin = _spin(2, 100000, 20, 2)
	box.add_child(_row("Big blind (starting)", bb_spin))
	stack_spin = _spin(100, 10000000, 2000, 100)
	box.add_child(_row("Buy-in / starting stack", stack_spin))
	bots_spin = _spin(0, 5, 5, 1)
	box.add_child(_row("Bots", bots_spin))
	speed_opt = _options(TableRoom.LEVEL_HANDS.keys())
	speed_opt.selected = 1
	box.add_child(_row("Blinds rise (tournament)", speed_opt))
	timer_spin = _spin(5, 120, 20, 5)
	box.add_child(_row("Turn timer (s)", timer_spin))
	box.add_child(_button("Play vs bots", _play_offline))

	online.add_child(_heading("Online"))
	login_box = VBoxContainer.new()
	server_edit = LineEdit.new()
	server_edit.text = cfg.get_value("lobby", "server", "")
	server_edit.placeholder_text = "Server address, e.g. poker.example.com"
	login_box.add_child(_row("Server", server_edit))
	password_edit = LineEdit.new()
	password_edit.secret = true
	password_edit.max_length = 64
	password_edit.text_submitted.connect(func(_t): _connect(false))
	login_box.add_child(_row("Password", password_edit))
	var login_row := HBoxContainer.new()
	login_row.add_child(_button("Log in", _connect.bind(false)))
	login_row.add_child(_button("Register", _connect.bind(true)))
	login_box.add_child(login_row)
	online.add_child(login_box)

	tables_box = VBoxContainer.new()
	account_label = Label.new()
	tables_box.add_child(account_label)
	table_list = ItemList.new()
	table_list.custom_minimum_size = Vector2(0, 140)
	table_list.item_activated.connect(func(_i): _join())
	tables_box.add_child(table_list)
	var table_row := HBoxContainer.new()
	table_row.add_child(_button("Join", _join))
	table_row.add_child(_button("Create table", func():
		_save_settings()
		Game.create_table()))
	table_row.add_child(_button("Refresh", Game.refresh_tables))
	table_row.add_child(_button("Log out", func():
		Game.log_out()
		_refresh()))
	tables_box.add_child(table_row)
	online.add_child(tables_box)

	error_label = Label.new()
	error_label.add_theme_color_override("font_color", Color("ff8a65"))
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	page.add_child(error_label)

	Game.lobby_changed.connect(_refresh)
	Game.closed.connect(_refresh.unbind(1))
	Game.joined.connect(_open_table)
	if Game.username:
		Game.refresh_tables()
	_refresh()


func _refresh() -> void:
	login_box.visible = Game.username.is_empty()
	tables_box.visible = not login_box.visible
	account_label.text = "%s · bankroll %d chips" % [Game.username, Game.chips]
	table_list.clear()
	for t in Game.tables:
		var state := "playing" if t.started else "not started"
		var mode := "Cash" if t.mode == "cash" else "Tournament"
		var i := table_list.add_item("%s · %s · blinds %s · buy-in %d · %d/6 · %s" % [t.title, mode, t.blinds, t.buy_in, t.seated, state])
		table_list.set_item_metadata(i, t.id)
	error_label.text = Game.last_error
	Game.last_error = ""


func _play_offline() -> void:
	_save_settings()
	Game.play_offline(name_edit.text.strip_edges().left(16) if name_edit.text.strip_edges() else "Player")
	_open_table()


func _connect(register: bool) -> void:
	_save_settings()
	var address := server_edit.text.strip_edges()
	if address.is_empty():
		error_label.text = "Enter the server address."
		return
	var err := Game.connect_to_server(address, name_edit.text.strip_edges(), password_edit.text, register)
	password_edit.clear()
	error_label.text = err if err else "Connecting…"


func _join() -> void:
	var picked := table_list.get_selected_items()
	if picked.is_empty():
		error_label.text = "Pick a table first."
		return
	Game.join_table(table_list.get_item_metadata(picked[0]))


func _open_table() -> void:
	get_tree().change_scene_to_file("res://ui/table_2d.tscn")


func _save_settings() -> void:
	Game.settings = {
		mode = ["cash", "tournament"][mode_opt.selected],
		bb = int(bb_spin.value),
		stack = int(stack_spin.value),
		bots = int(bots_spin.value),
		speed = speed_opt.get_item_text(speed_opt.selected),
		turn_time = int(timer_spin.value),
	}
	cfg.set_value("lobby", "name", name_edit.text)
	cfg.set_value("lobby", "server", server_edit.text)
	cfg.save(SAVE)


func _row(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(control)
	return row


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("f0c040"))
	return l


func _options(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(item)
	return o


func _spin(lo: float, hi: float, value: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	return s


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	return b
