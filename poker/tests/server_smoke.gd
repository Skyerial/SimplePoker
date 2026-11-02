extends SceneTree
## End-to-end check against a real server process over encrypted ENet.
## Run: Godot --headless --path . -s res://tests/server_smoke.gd

const DATA := "user://smoke_server"
const TIMEOUT := 30.0

var game: Node
var server_pid := 0
var step := 0
var elapsed := 0.0
var wait := 0.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DATA)
	DirAccess.remove_absolute(DATA + "/accounts.json")
	server_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--data=" + DATA])
	game = root.get_node("Game")
	game.joined.connect(func(): step = 4)


func _process(delta: float) -> bool:
	elapsed += delta
	wait -= delta
	if elapsed > TIMEOUT:
		return finish("timed out at step %d" % step)
	if wait > 0:
		return false
	match step:
		0:  # give the server a moment to open its port
			wait = 2.0
			step = 1
		1:
			var err: String = game.connect_to_server("127.0.0.1", "Smoke", "secret1", true)
			if err:
				return finish(err)
			step = 2
		2:
			if game.last_error:
				return finish("login failed: " + game.last_error)
			if game.username == "Smoke" and game.chips == Accounts.START_CHIPS:
				game.settings = {mode = "cash", bb = 20, stack = 2000, bots = 1, speed = "Normal", turn_time = 20}
				game.create_table()
				step = 3
		4:  # seated, see the joined signal
			if game.view.get("can_start", false):
				game.start_game()
				step = 5
		5:
			var v: Dictionary = game.view
			if v.get("hand_running", false) and v.me >= 0 and v.seats[v.me].cards.size() == 2 and v.seats[v.me].cards.min() >= 0:
				var others: Array = range(v.seats.size()).filter(func(i): return i != v.me and v.seats[i] != null)
				if not others.all(func(i): return v.seats[i].cards == [-1, -1]):
					return finish("the bot's cards were sent to us")
				game.chips = 0
				game.leave()
				step = 6
		6:
			# We left in the first hand with at most a blind in: leaving folds it, and the
			# table closing as the last human leaves pays the rest back to the bankroll.
			if game.chips > 0:
				var lost: int = Accounts.START_CHIPS - game.chips
				return finish("" if lost >= 0 and lost <= 20 and game.tables.is_empty() else "bankroll is %d after leaving" % game.chips)
			game.refresh_tables()
			wait = 0.5
	return false


func finish(error: String) -> bool:
	if server_pid:
		OS.kill(server_pid)
	print("Server smoke test passed" if error.is_empty() else "FAIL: " + error)
	quit(0 if error.is_empty() else 1)
	return true
