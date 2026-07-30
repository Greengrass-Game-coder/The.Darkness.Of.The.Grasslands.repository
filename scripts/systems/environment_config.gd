extends Node
## EnvironmentConfig ----- autoload that provides a single flag to switch
## between Dev (local/ngrok) and Production (Render/Live) server endpoints.
##
## Usage: EnvironmentConfig.environment = EnvironmentConfig.EnvType.DEV
## The connect_url property returns the correct WebSocket URL automatically.

signal environment_changed(new_environment: int)

enum EnvType {
	PRODUCTION,  # Render live server
	DEV          # Local/ngrok tunnel
}

## Toggle this to switch environments (defaults to DEV for local/ngrok)
@export var environment: int = EnvType.DEV:
	set(v):
		environment = v as int
		environment_changed.emit(v as int)
		print("EnvironmentConfig: Switched to ", get_environment_name(v as int))

## Dev WebSocket URL ----- LocalXpose tunnel
const DEV_WS_URL: String = "wss://ytuqmca2hq.loclx.io"
## Production WebSocket URL (unused, placeholder)
const PROD_WS_URL: String = "wss://ytuqmca2hq.loclx.io"

## Dev HTTP URL
const DEV_HTTP_URL: String = "https://ytuqmca2hq.loclx.io"
## Production HTTP URL (unused, placeholder)
const PROD_HTTP_URL: String = "https://ytuqmca2hq.loclx.io"


func get_environment_name(env: int) -> String:
	match env:
		EnvType.DEV as int:
			return "DEV"
		EnvType.PRODUCTION as int:
			return "PRODUCTION"
	return "UNKNOWN"


func get_ws_url() -> String:
	"""Get the active WebSocket URL based on current environment."""
	match environment:
		EnvType.DEV as int:
			return DEV_WS_URL
		EnvType.PRODUCTION as int:
			return PROD_WS_URL
	return PROD_WS_URL


func get_http_url() -> String:
	"""Get the active HTTP URL (for wake-up or health checks)."""
	match environment:
		EnvType.DEV as int:
			return DEV_HTTP_URL
		EnvType.PRODUCTION as int:
			return PROD_HTTP_URL
	return PROD_HTTP_URL


func is_dev() -> bool:
	return environment == (EnvType.DEV as int)


func is_prod() -> bool:
	return environment == (EnvType.PRODUCTION as int)


func set_dev() -> void:
	environment = EnvType.DEV as int


func set_prod() -> void:
	environment = EnvType.PRODUCTION as int


## Toggle between dev and prod
func toggle() -> void:
	match environment:
		EnvType.DEV as int:
			environment = EnvType.PRODUCTION as int
		EnvType.PRODUCTION as int:
			environment = EnvType.DEV as int
