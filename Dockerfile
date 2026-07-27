FROM debian:bookworm-slim

WORKDIR /app

# Only copy the server binary + pck — no game assets needed
COPY Server/TheDarknessServer.x86_64 .
COPY Server/TheDarknessServer.pck .

RUN chmod +x ./TheDarknessServer.x86_64

EXPOSE 8080

CMD ["./TheDarknessServer.x86_64", "--headless"]
