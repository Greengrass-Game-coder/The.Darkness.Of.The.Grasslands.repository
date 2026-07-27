FROM debian:bookworm-slim

WORKDIR /app

# Download Godot headless runtime (same version as the export)
ADD https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux_headless.x86_64 /usr/bin/godot
RUN chmod +x /usr/bin/godot

# Copy only the PCK — no massive 70MB binary needed in the repo
COPY Server/TheDarknessServer.pck .

# Render sets PORT env var — server reads it in dedicated_server.gd

CMD ["godot", "--headless", "--main-pack", "TheDarknessServer.pck"]
