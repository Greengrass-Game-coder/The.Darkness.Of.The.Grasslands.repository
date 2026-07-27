FROM debian:bookworm-slim

WORKDIR /app

# Only copy the server binary + pck — no game assets needed
COPY Server/TheDarknessServer.x86_64 .
COPY Server/TheDarknessServer.pck .

RUN chmod +x ./TheDarknessServer.x86_64

# Render routes via PORT env var (default 10000) — no EXPOSE needed
# Server reads PORT from environment in dedicated_server.gd

CMD ["./TheDarknessServer.x86_64", "--headless"]
