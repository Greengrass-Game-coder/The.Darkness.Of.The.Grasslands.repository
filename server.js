const WebSocket = require('ws');
const wss = new WebSocket.Server({ port: 8080 });

console.log('Master server running on port 8080');

wss.on('connection', (ws) => {
  console.log('Client connected');
  ws.on('message', (message) => {
    console.log('Received:', message);
  });
});
