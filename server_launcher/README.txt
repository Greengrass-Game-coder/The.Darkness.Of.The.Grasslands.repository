THE DARKNESS OF THE GRASSLANDS - SERVER LAUNCHER
=================================================

WHAT THIS DOES:
  Starts both the Godot dedicated server AND ngrok tunnel
  with a single double-click. The batch file:
  1. Launches the Godot server (--headless, no window)
  2. Waits for it to be ready on port 8080
  3. Launches ngrok to expose it to the internet

SETUP:

  1. Export the server:
     - Open Godot -> Project -> Export -> Add Windows Desktop
     - Export the executable as:
       server_launcher/server/TheDarknessServer.exe
     - Make sure "Export With Debug" is OFF for smaller size

  2. Install ngrok:
     - Download from https://ngrok.com/download
     - Extract to C:\tools\ngrok\ngrok.exe
     - Login and run: ngrok config add-authtoken YOUR_TOKEN
     - Or update NGROK_PATH in run_server.bat if you put it elsewhere

  3. (Optional) Update ngrok domain:
     - Open run_server.bat in Notepad
     - Change NGROK_DOMAIN to your reserved domain
     - Or remove --domain=... to use a random URL each time

HOW TO USE:

  Double-click "run_server.bat"
  
  It will:
    - Show a console window with progress
    - Start the server (no visible window, runs in background)
    - Wait ~2-5 seconds for the server to be ready
    - Launch ngrok (opens in same window)
  
  Check ngrok dashboard at: http://localhost:4040

  To stop everything, just close the console window.

  The ngrok URL is already set in your game code:
    DEV_WS_URL in environment_config.gd

TROUBLESHOOTING:

  "Server executable not found"
    -> Export the server first (see SETUP step 1)
  
  "ngrok not found"
    -> Install ngrok or update NGROK_PATH in run_server.bat
  
  "Error 8012" when connecting:
    -> Server isn't ready yet. Check http://localhost:4040
    -> Make sure no other program is using port 8080
  
  Port 8080 already in use:
    -> Change SERVER_PORT in run_server.bat and
       update PORT env or server code accordingly

WINDOWS SERVICE (optional):
  To run this as a real Windows service that auto-starts on boot:
  1. Download nssm from https://nssm.cc
  2. Run as Admin: nssm install "DarknessServer"
  3. Path: C:\Windows\System32\cmd.exe
  4. Arguments: /c "C:\full\path\to\server_launcher\run_server.bat"
  5. Startup dir: C:\full\path\to\server_launcher\
