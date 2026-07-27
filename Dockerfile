FROM debian:bookworm-slim

WORKDIR /app

# Copy all project files
COPY . .

# Make server binary executable
RUN chmod +x ./Server/TheDarknessServer.x86_64

# Expose server port
EXPOSE 8080

# Run the dedicated server
CMD ["./Server/TheDarknessServer.x86_64", "--headless"]
