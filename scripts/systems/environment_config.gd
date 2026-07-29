extends Node
## EnvironmentConfig — autoload that provides a single flag to switch
## between Dev (local/ngrok) and Production (Render/Live) server endpoints.
##
## Usage: EnvironmentConfig.environment = EnvironmentConfig.Environment.DEV
## The connect_url property returns the correct WebSocket URL automatically.

signal environment_changed(new_environment: int)

enum Environment {
	PRODUCTION,  # Render live server
	DEV          # Local/ngrok tunnel
}

## Toggle this to switch environments
@export var environment: int = Environment.PRODUCTION:
	set(v):
		environment = v
		environment_changed.emit(v)
		print("EnvironmentConfig: Switched to ", get_environment_name(v))

## Dev WebSocket URL — change this to your ngrok subdomain
const DEV_WS_URL: String = "ws://localhost:8080"
## Production WebSocket URL
const PROD_WS_URL: String = "wss://the-darkness-server.onrender.com"

## Dev HTTP URL (for Render wake-up equivalent — not needed for ngrok)
const DEV_HTTP_URL: String = "http://localhost:8080"
## Production HTTP URL (for Render wake-up)
const PROD_HTTP_URL: String = "https://the-darkness-server.onrender.com"


func get_environment_name(env: int) -> String:
	match env:
		Environment.DEV:
			return "DEV"
		Environment.PRODUCTION:
			return "PRODUCTION"
	return "UNKNOWN"


func get_ws_url() -> String:
	"""Get the active WebSocket URL based on current environment."""
	match environment:
		Environment.DEV:
			return DEV_WS_URL
		Environment.PRODUCTION:
			return PROD_WS_URL
	return PROD_WS_URL


func get_http_url() -> String:
	"""Get the active HTTP URL (for wake-up or health checks)."""
	match environment:
		Environment.DEV:
			return DEV_HTTP_URL
		Environment.PRODUCTION:
			return PROD_HTTP_URL
	return PROD_HTTP_URL


func is_dev() -> bool:
	return environment == Environment.DEV


func is_prod() -> bool:
	return environment == Environment.PRODUCTION


func set_dev() -> void:
	environment = Environment.DEV


func set_prod() -> void:
	environment = Environment.PRODUCTION


## Toggle between dev and prod
func toggle() -> void:
	match environment:
		Environment.DEV:
			environment = Environment.PRODUCTION
		Environment.PRODUCTION:
			environment = Environment.DEV
