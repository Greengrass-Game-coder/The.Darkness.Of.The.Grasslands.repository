extends Node
## GiftSystem — lets a player buy a paid cartridge and gift it to a friend
## instead of keeping it themselves.
##
## Two delivery paths, both requiring the friend to ACCEPT:
##   • Local:  gifts to another local profile persist in user://pending_gifts.json
##             and are accepted/denied when that profile plays the arcade.
##
## All coin deductions happen in the arcade room (via _spend_coins); this module
## handles persistence, applying unlocks, and refunds on arbitrary profiles.

signal local_gift_created(gift: Dictionary)
signal inbox_changed()

const GIFTS_FILE: String = "user://pending_gifts.json"

## Cartridge metadata shared with the arcade room (cost + profile unlock key).
const CARTRIDGES: Array[Dictionary] = [
	{"name": "TETRINO 2", "cost": 2, "owned_key": "tetrino_owns_paid"},
	{"name": "TETRINO 3", "cost": 3, "owned_key": "tetrino_owns_paid3"},
]


func _ready() -> void:
	pass


func cost_for(cartridge_name: String) -> int:
	for c: Dictionary in CARTRIDGES:
		if str(c["name"]) == cartridge_name:
			return int(c["cost"])
	return 0


func owned_key_for(cartridge_name: String) -> String:
	for c: Dictionary in CARTRIDGES:
		if str(c["name"]) == cartridge_name:
			return str(c["owned_key"])
	return ""


func cartridge_name_for(owned_key: String) -> String:
	for c: Dictionary in CARTRIDGES:
		if str(c["owned_key"]) == owned_key:
			return str(c["name"])
	return "?"


# ── Local pending-gift persistence ─────────────────────────────────────────

func load_gifts() -> Array:
	if not FileAccess.file_exists(GIFTS_FILE):
		return []
	var f := FileAccess.open(GIFTS_FILE, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	return []


func save_gifts(gifts: Array) -> void:
	var f := FileAccess.open(GIFTS_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(gifts, "\t"))
		f.close()


## Create a pending local gift. The gifter's coins are spent separately by the
## caller; here we just record the gift so the recipient can accept or deny.
func create_local_gift(gifter: String, recipient: String, cartridge_name: String) -> Dictionary:
	var gifts: Array = load_gifts()
	var gift: Dictionary = {
		"id": str(Time.get_ticks_usec()) + "_" + str(randi()),
		"gifter": gifter,
		"recipient": recipient,
		"cartridge": cartridge_name,
		"cost": cost_for(cartridge_name),
		"owned_key": owned_key_for(cartridge_name),
		"status": "pending",
		"source": "local",
	}
	gifts.append(gift)
	save_gifts(gifts)
	local_gift_created.emit(gift)
	inbox_changed.emit()
	return gift


func pending_for(recipient: String) -> Array:
	var out: Array = []
	var rl: String = recipient.to_lower()
	for g in load_gifts():
		if str(g.get("recipient", "")).to_lower() == rl and g.get("status", "") == "pending":
			out.append(g)
	return out


func set_gift_status(gift: Dictionary, status: String) -> void:
	var gifts: Array = load_gifts()
	for g in gifts:
		if g.get("id", "") == gift.get("id", ""):
			g["status"] = status
			break
	save_gifts(gifts)
	inbox_changed.emit()


## Accept a gift: grant the cartridge to the recipient's profile permanently.
func accept_gift(gift: Dictionary) -> bool:
	var recipient: String = str(gift.get("recipient", ""))
	var key: String = str(gift.get("owned_key", ""))
	if recipient.is_empty() or key.is_empty():
		return false
	apply_unlock(recipient, key)
	set_gift_status(gift, "accepted")
	return true


## Deny a gift: refund the gifter's coins and mark the gift denied.
func deny_gift(gift: Dictionary) -> bool:
	var gifter: String = str(gift.get("gifter", ""))
	var cost: int = int(gift.get("cost", 0))
	if not gifter.is_empty() and cost > 0:
		refund(gifter, cost)
	set_gift_status(gift, "denied")
	return true


# ── Profile helpers (arbitrary local profiles) ─────────────────────────────

func current_username() -> String:
	var auth: Node = get_node_or_null("/root/AuthManager")
	if auth != null:
		return str(auth.get("current_username"))
	return ""


## Permanently grant an unlock to a profile (the current one, or a saved one).
func apply_unlock(username: String, owned_key: String) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var sm: Node = get_node_or_null("/root/SaveManager")
	if gs != null and username.to_lower() == str(gs.get("logged_in_username")).to_lower():
		gs.set(owned_key, true)
		if sm != null:
			sm.autosave(username)
		return
	var data: Dictionary = SaveManager.load_player_data(username)
	if data.is_empty():
		return
	data[owned_key] = true
	SaveManager.save_player_data(username, data)


## Refund coins to a profile by lowering its spent counter (raises spendable).
func refund(username: String, cost: int) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var sm: Node = get_node_or_null("/root/SaveManager")
	if gs != null and username.to_lower() == str(gs.get("logged_in_username")).to_lower():
		gs.tetrino_coins_spent = maxi(int(gs.tetrino_coins_spent) - cost, 0)
		if sm != null:
			sm.autosave(username)
		return
	var data: Dictionary = SaveManager.load_player_data(username)
	if data.is_empty():
		return
	data["tetrino_coins_spent"] = maxi(int(data.get("tetrino_coins_spent", 0)) - cost, 0)
	SaveManager.save_player_data(username, data)


## All local profile usernames (for the recipient picker).
func list_local_profiles() -> Array[String]:
	var out: Array[String] = []
	for n: String in SaveManager.list_saved_players():
		if not n.to_lower().begins_with("."):
			out.append(n)
	return out


## Does a local profile already own a cartridge (by owned_key)?
func local_owns(username: String, owned_key: String) -> bool:
	if username.to_lower() == current_username().to_lower():
		var gs: Node = get_node_or_null("/root/GameState")
		return bool(gs.get(owned_key)) if gs != null else false
	var data: Dictionary = SaveManager.load_player_data(username)
	if data.is_empty():
		return false
	return bool(data.get(owned_key, false))



