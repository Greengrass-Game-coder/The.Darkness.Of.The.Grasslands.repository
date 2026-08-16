extends SceneTree
## P2P two-client handshake test.
## Launches a real host (ENet server) and a real client (ENet client) in one
## process, drives both through the handshake, and verifies:
##   1. create_server succeeds on the host
##   2. create_client succeeds on the client
##   3. both reach CONNECTION_CONNECTED
##   4. the host sees the client peer connect (via peer_connected signal)
## Run:  godot --headless --script res://tests/p2p_handshake_test.gd

var _test_port := 7792
var _host_peer_connected := false

func _init() -> void:
	_run_test()


func _run_test() -> void:
	var failures: int = 0

	# --- Host side ---
	var host: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var host_err: int = host.create_server(_test_port, 4)
	print("[T1] host create_server -> err ", host_err)
	if host_err != OK:
		failures += 1
		print("[FAIL] server could not start")
	host.peer_connected.connect(func(_id: int) -> void:
		_host_peer_connected = true
	)

	# --- Client side ---
	var client: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var client_err: int = client.create_client("127.0.0.1", _test_port)
	print("[T2] client create_client -> err ", client_err)
	if client_err != OK:
		failures += 1
		print("[FAIL] client could not start")

	# Drive both peers until handshake completes.
	var host_connected := false
	var client_connected := false
	for i in range(120):
		host.poll()
		client.poll()
		if host.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			host_connected = true
		if client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			client_connected = true
		if host_connected and client_connected and _host_peer_connected:
			break
		await process_frame

	print("[T3] host -> connected: ", host_connected, " | unique_id: ", host.get_unique_id())
	print("[T4] client -> connected: ", client_connected, " | unique_id: ", client.get_unique_id())
	if not host_connected:
		failures += 1
		print("[FAIL] host never reached CONNECTION_CONNECTED")
	if not client_connected:
		failures += 1
		print("[FAIL] client never reached CONNECTION_CONNECTED")
	if not _host_peer_connected:
		failures += 1
		print("[FAIL] host never received peer_connected for the client")

	print("")
	if failures == 0:
		print("P2P HANDSHAKE TEST: PASS (host+client connected, host saw the peer join)")
	else:
		print("P2P HANDSHAKE TEST: FAIL (%d check(s) failed)" % failures)

	host.close()
	client.close()
	quit(failures)
