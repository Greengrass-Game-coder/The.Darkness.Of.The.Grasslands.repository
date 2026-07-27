FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Download & extract Godot 4.7.1 standard linux build (no headless binary released for 4.7.1)
ADD https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip /tmp/godot.zip
RUN unzip -j /tmp/godot.zip -d /usr/bin/ && rm /tmp/godot.zip && chmod +x /usr/bin/Godot_v4.7.1-stable_linux.x86_64

# Copy only the PCK — no massive ~70MB binary needed in the repo
COPY Server/TheDarknessServer.pck .

# Render sets PORT env var — server reads it in dedicated_server.gd

CMD ["Godot_v4.7.1-stable_linux.x86_64", "--headless", "--main-pack", "TheDarknessServer.pck"]
