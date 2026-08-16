class_name AddressCrypto
extends RefCounted
## Encrypt/decrypt host connect addresses so raw IP:port strings are never shown
## in the public server browser or invite strings. Uses a simple deterministic
## XOR obfuscation with the project key (same style as AuthManager), so any
## peer can decrypt the default-encrypted address at connect time.
##
## NOTE: This is obfuscation, not strong cryptography — it stops casual casual
## reading/"IP stealing" in the browser/list, which is the goal. The key is
## shared with all clients by definition of a P2P game.

const KEY: String = "TDotG_P2P_ENC_2024!"


## Encrypt a plaintext "ip:port" string into a transport-safe obfuscated string.
static func encrypt(plain: String) -> String:
	if plain.is_empty():
		return ""
	var key_bytes: PackedByteArray = KEY.to_utf8_buffer()
	var data: PackedByteArray = plain.to_utf8_buffer()
	var out: PackedByteArray = PackedByteArray()
	out.resize(data.size())
	for i: int in data.size():
		out[i] = data[i] ^ key_bytes[i % key_bytes.size()]
	return out.hex_encode()


## Decrypt a value produced by encrypt(). Passes through plaintext unchanged if
## the value was not encrypted (e.g. a bare IP or loopback), so mixed data is safe.
static func decrypt(encoded: String) -> String:
	if encoded.is_empty():
		return ""
	# If it's already plaintext-looking (contains ':' or '.', no hex chars), return as-is.
	if _looks_plaintext(encoded):
		return encoded
	var key_bytes: PackedByteArray = KEY.to_utf8_buffer()
	var data: PackedByteArray = encoded.hex_decode()
	if data.is_empty():
		return encoded
	var out: PackedByteArray = PackedByteArray()
	out.resize(data.size())
	for i: int in data.size():
		out[i] = data[i] ^ key_bytes[i % key_bytes.size()]
	return out.get_string_from_utf8()


static func _looks_plaintext(value: String) -> bool:
	if value.is_empty():
		return true
	# Encrypted hex is only [0-9a-f]. Any character outside that set means plaintext.
	for c: String in value:
		if not (c in "0123456789abcdefABCDEF"):
			return true
	return false