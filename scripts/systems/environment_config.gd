extends Node
## EnvironmentConfig — autoload that provides a single flag to switch
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
		environment = v
		environment_changed.emit(v)
		print("EnvironmentConfig: Switched to ", get_environment_name(v))

## Dev WebSocket URL — ngrok tunnel (wss:// for TLS)
const DEV_WS_URL: String = "wss://enlisted-cardstock-bunny.ngrok-free.dev"
## Production WebSocket URL
const PROD_WS_URL: String = "wss://the-darkness-server.onrender.com"

## Dev HTTP URL (for health checks / ngrok)
const DEV_HTTP_URL: String = "https://enlisted-cardstock-bunny.ngrok-free.dev"
## Production HTTP URL (for Render wake-up)
const PROD_HTTP_URL: String = "https://the-darkness-server.onrender.com"


func get_environment_name(env: int) -> String:
	match env:
		EnvType.DEV:
			return "DEV"
		EnvType.PRODUCTION:
			return "PRODUCTION"
	return "UNKNOWN"


func get_ws_url() -> String:
	"""Get the active WebSocket URL based on current environment."""
	match environment:
		EnvType.DEV:
			return DEV_WS_URL
		EnvType.PRODUCTION:
			return PROD_WS_URL
	return PROD_WS_URL


func get_http_url() -> String:
	"""Get the active HTTP URL (for wake-up or health checks)."""
	match environment:
		EnvType.DEV:
			return DEV_HTTP_URL
		EnvType.PRODUCTION:
			return PROD_HTTP_URL
	return PROD_HTTP_URL


func is_dev() -> bool:
	return environment == EnvType.DEV


func is_prod() -> bool:
	return environment == EnvType.PRODUCTION


func set_dev() -> void:
	environment = EnvType.DEV


func set_prod() -> void:
	environment = EnvType.PRODUCTION


## Toggle between dev and prod
func toggle() -> void:
	match environment:
		EnvType.DEV:
			environment = EnvType.PRODUCTION
		EnvType.PRODUCTION:
			environment = EnvType.DEV
