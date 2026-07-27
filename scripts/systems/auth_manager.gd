extends Node

## Account system — encrypted file storage with username/password login.
## One hardcoded admin account: Greengrass / Moon996633.
## All passwords are SHA-256 hashed with per-user salt.
## Autoload — accessible globally as AuthManager.

signal login_succeeded(username: String, is_admin: bool)
signal login_failed(reason: String)
signal logged_out()

const ADMIN_USERNAME: String = "Greengrass"
const ADMIN_PASSWORD: String = "Moon996633"
const ACCOUNTS_FILE: String = "user://accounts.dat"
const SESSION_FILE: String = "user://session.dat"
const ENCRYPTION_KEY: String = "TDotG_2024_S3cur3_K3y!"  # XOR obfuscation key

var current_username: String = ""
var is_admin: bool = false
var _logged_in: bool = false


func _ready() -> void:
	"""Restore login session on startup if available."""
	_auto_login_from_session()


func login(username: String, password: String) -> bool:
	"""Attempt to log in. Returns true on success."""
	if username.is_empty() or password.is_empty():
		login_failed.emit("Username and password cannot be empty.")
		return false
	
	if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
		# Admin login — always works
		_current_user_login(username)
		is_admin = true
		GameState.is_admin = true
		GameState.logged_in_username = username
		login_succeeded.emit(username, true)
		print("AuthManager: Admin login: ", username)
		return true
	
	# Check local accounts file
	var accounts: Dictionary = _load_accounts()
	if accounts.has(username):
		var stored_hash: String = accounts[username]["hash"]
		var salt: String = accounts[username]["salt"]
		var input_hash: String = _hash_password(password, salt)
		if input_hash == stored_hash:
			_current_user_login(username)
			GameState.logged_in_username = username
			login_succeeded.emit(username, false)
			print("AuthManager: User login: ", username)
			return true
		else:
			login_failed.emit("Incorrect password.")
			return false
	else:
		# Auto-register new account
		_create_account(username, password)
		_current_user_login(username)
		GameState.logged_in_username = username
		login_succeeded.emit(username, false)
		print("AuthManager: New account created: ", username)
		return true


func logout() -> void:
	"""Log out the current user."""
	current_username = ""
	is_admin = false
	_logged_in = false
	GameState.is_admin = false
	GameState.logged_in_username = ""
	_clear_session()
	logged_out.emit()
	print("AuthManager: Logged out")


func is_logged_in() -> bool:
	return _logged_in


func _auto_login_from_session() -> bool:
	"""Try to restore a previous session."""
	if not FileAccess.file_exists(SESSION_FILE):
		return false
	var file: FileAccess = FileAccess.open(SESSION_FILE, FileAccess.READ)
	if not file:
		return false
	var username: String = file.get_line().strip_edges()
	file.close()
	if username.is_empty():
		return false
	# Auto-login the stored user
	_current_user_login(username)
	if username == ADMIN_USERNAME:
		is_admin = true
		GameState.is_admin = true
	GameState.logged_in_username = username
	print("AuthManager: Session restored for: ", username)
	return true


func _save_session(username: String) -> void:
	"""Save the current session so login persists across restarts."""
	var file: FileAccess = FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if file:
		file.store_line(username)
		file.close()


func _clear_session() -> void:
	"""Remove the saved session file."""
	if FileAccess.file_exists(SESSION_FILE):
		var dir: DirAccess = DirAccess.open("user://")
		if dir:
			dir.remove("session.dat")


func _current_user_login(username: String) -> void:
	current_username = username
	_logged_in = true
	_save_session(username)


func _create_account(username: String, password: String) -> void:
	"""Create a new account with hashed password."""
	var accounts: Dictionary = _load_accounts()
	var salt: String = _generate_salt()
	var hashed: String = _hash_password(password, salt)
	accounts[username] = {"hash": hashed, "salt": salt}
	_save_accounts(accounts)


func _load_accounts() -> Dictionary:
	"""Load accounts from encrypted file."""
	if not FileAccess.file_exists(ACCOUNTS_FILE):
		return {}
	var file: FileAccess = FileAccess.open_encrypted_with_pass(ACCOUNTS_FILE, FileAccess.READ, ENCRYPTION_KEY)
	if not file:
		push_warning("AuthManager: Could not open accounts file (may not exist yet).")
		return {}
	var json_str: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _save_accounts(accounts: Dictionary) -> void:
	"""Save accounts to encrypted file."""
	var file: FileAccess = FileAccess.open_encrypted_with_pass(ACCOUNTS_FILE, FileAccess.WRITE, ENCRYPTION_KEY)
	if not file:
		push_error("AuthManager: Could not write accounts file.")
		return
	var json_str: String = JSON.stringify(accounts)
	file.store_string(json_str)
	file.close()


func _hash_password(password: String, salt: String) -> String:
	"""Hash a password with SHA-256 and a salt."""
	var combined: String = salt + password + salt
	return combined.sha256_text()


func _generate_salt() -> String:
	"""Generate a random 16-character hex salt."""
	var chars: String = "0123456789abcdef"
	var salt: String = ""
	for i in range(16):
		salt += chars[randi() % chars.length()]
	return salt
