#!/usr/bin/env python3
"""
The Darkness of the Grasslands - Automatic Server Waker
======================================================
Detects whether the coordination server (port 8080) is running, and if not,
launches it in the background. Optionally keeps watching it and restarts it
if it ever stops.

This coordination server is what the in-game PUBLIC SERVER BROWSER queries.
It is NOT the P2P transport itself (that is direct ENet between players).
Without it, "localhost not responding" appears when you try to browse/find a
match. Hosting a private room works without it.

USAGE
-----
  python server_waker.py            # start if missing, then keep it alive
  python server_waker.py --once     # start if missing, then exit
  python server_waker.py --just-check  # exit 0 if running, exit 1 if not

CONFIG
------
  PORT      coordination server port (default 8080)
  GODOT     path to the Godot binary that runs the server scene
"""
import os
import socket
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PORT = int(os.environ.get("DOTG_SERVER_PORT", "8080"))
GODOT = os.environ.get(
    "DOTG_GODOT",
    r"C:/Users/misfer/Downloads/Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe",
)
# The project folder (folder above this script's tools/ directory).
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_SCENE = "res://scenes/server.tscn"
LOG_FILE = os.path.join(PROJECT_DIR, "server_waker.log")


def log(msg: str) -> None:
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def port_open(port: int) -> bool:
    """Return True if something is listening on the given port."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1.0)
            return s.connect_ex(("127.0.0.1", port)) == 0
    except OSError:
        return False


def start_server() -> subprocess.Popen:
    """Launch the Godot server scene headless in the background."""
    if not os.path.exists(GODOT):
        raise FileNotFoundError("Godot binary not found at %s" % GODOT)
    log("Launching coordination server: %s %s" % (GODOT, SERVER_SCENE))
    # Redirect output to a dedicated log file so the console stays clean.
    server_log = open(os.path.join(PROJECT_DIR, "server_output.log"), "a", encoding="utf-8")
    proc = subprocess.Popen(
        [GODOT, "--headless", "--path", PROJECT_DIR, SERVER_SCENE],
        stdout=server_log,
        stderr=subprocess.STDOUT,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    return proc


def wait_for_port(port: int, timeout: float = 15.0) -> bool:
    """Wait up to `timeout` seconds for the port to open."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_open(port):
            return True
        time.sleep(0.5)
    return False


def main() -> int:
    args = sys.argv[1:]
    just_check = "--just-check" in args
    once = "--once" in args

    if port_open(PORT):
        log("Coordination server already running on port %d. Nothing to do." % PORT)
        return 0

    if just_check:
        log("Coordination server is NOT running on port %d." % PORT)
        return 1

    try:
        proc = start_server()
    except FileNotFoundError as e:
        log("ERROR: %s" % e)
        log("Set the DOTG_GODOT env var to your Godot binary path.")
        return 2

    log("Waiting for server to come online on port %d..." % PORT)
    if wait_for_port(PORT):
        log("Server is UP on port %d." % PORT)
    else:
        log("Server did not open port %d in time. Check server_output.log" % PORT)

    if once:
        return 0

    # Keep-alive loop: restart if the server dies.
    log("Watching server (Ctrl+C to stop).")
    try:
        while True:
            time.sleep(3.0)
            if not port_open(PORT):
                log("Server went down. Restarting...")
                try:
                    proc = start_server()
                except FileNotFoundError as e:
                    log("ERROR restarting: %s" % e)
                    return 2
                wait_for_port(PORT)
    except KeyboardInterrupt:
        log("Stopped by user.")
    return 0


if __name__ == "__main__":
    sys.exit(main())