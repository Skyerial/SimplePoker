class_name Accounts
extends RefCounted
## Player accounts and bankrolls, kept in one JSON file on the server.
## Chips at a cash table are tracked per table and saved after every hand;
## on the next start they go back to the bankroll, so a crash loses nothing
## but the hand in progress.

const START_CHIPS := 5000
const MIN_CHIPS := 2000  ## bankroll plus table stacks never drops below this
const HASH_ROUNDS := 20000
const NAME_RULE := "^[A-Za-z0-9_]{3,16}$"

var path: String
var error := ""  ## set when the file exists but can't be read; don't run then
var data := {}  # lowercase name -> {name, salt, hash, chips, at_table = {table id: stack}}
var _crypto := Crypto.new()


func _init(file: String) -> void:
	path = file
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			error = "Can't read %s. Fix or restore it from a backup." % ProjectSettings.globalize_path(path)
			return
		data = parsed
	for a in data.values():
		a.chips = int(a.chips)
		for stack in a.at_table.values():
			a.chips += int(stack)
		a.at_table = {}
		_floor(a)
	save()


## Returns an error message, or "" when the account was made.
func register(player_name: String, password: String) -> String:
	if not RegEx.create_from_string(NAME_RULE).search(player_name):
		return "Names are 3-16 letters, digits or _."
	if password.length() < 6 or password.length() > 64:
		return "Passwords are 6-64 characters."
	if data.has(player_name.to_lower()):
		return "That name is taken."
	var salt := _crypto.generate_random_bytes(16).hex_encode()
	data[player_name.to_lower()] = {name = player_name, salt = salt, hash = _hash(password, salt),
		chips = START_CHIPS, at_table = {}}
	save()
	return ""


## Returns an error message, or "" when the password is right.
func login(player_name: String, password: String) -> String:
	var a = data.get(player_name.to_lower())
	if a == null or not _crypto.constant_time_compare(_hash(password, a.salt).hex_decode(), a.hash.hex_decode()):
		return "Wrong name or password."
	return ""


## The name as it was registered.
func name_of(player_name: String) -> String:
	return data[player_name.to_lower()].name


func chips(player_name: String) -> int:
	return data[player_name.to_lower()].chips


## Moves chips from the bankroll to a table. False if they don't have enough.
func buy_in(player_name: String, table: String, amount: int) -> bool:
	var a = data[player_name.to_lower()]
	_floor(a)
	if a.chips < amount:
		return false
	a.chips -= amount
	a.at_table[table] = int(a.at_table.get(table, 0)) + amount
	save()
	return true


## Records a player's stack at a table. Call save() after a batch.
func set_stack(player_name: String, table: String, stack: int) -> void:
	data[player_name.to_lower()].at_table[table] = stack


## Moves the player's last recorded stack at `table` back to the bankroll.
func settle(player_name: String, table: String) -> void:
	var a = data[player_name.to_lower()]
	a.chips += int(a.at_table.get(table, 0))
	a.at_table.erase(table)
	_floor(a)
	save()


# ponytail: free top-up to MIN_CHIPS whenever you're short; replace with a daily claim (see GDD To do).
func _floor(a: Dictionary) -> void:
	var total: int = a.chips
	for stack in a.at_table.values():
		total += int(stack)
	a.chips += maxi(0, MIN_CHIPS - total)


## Writes a temp file first, so a crash mid-write can't corrupt the accounts.
func save() -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		push_error("Can't write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)


# ponytail: iterated HMAC-SHA256, not real PBKDF2/argon2; swap in argon2 if this ever holds more than friends' play chips.
func _hash(password: String, salt: String) -> String:
	var key := password.to_utf8_buffer()
	var h := salt.to_utf8_buffer()
	for i in HASH_ROUNDS:
		h = _crypto.hmac_digest(HashingContext.HASH_SHA256, key, h)
	return h.hex_encode()
