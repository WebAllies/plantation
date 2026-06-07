const { WebSocket, WebSocketServer } = require('ws');
const { authenticateWebSocket } = require('./auth');

function parseJsonMessage(raw) {
  if (typeof raw !== 'string') return null;
  try {
    const decoded = JSON.parse(raw);
    return decoded && typeof decoded === 'object' ? decoded : null;
  } catch (_) {
    return null;
  }
}

class WsHub {
  constructor({ server, db, requireAuth, logger = console }) {
    this.db = db;
    this.requireAuth = requireAuth;
    this.logger = logger;
    this.wss = new WebSocketServer({ server, path: '/ws' });
    this.clients = new Map();
  }

  start() {
    this.wss.on('connection', async (socket, req) => {
      const url = new URL(req.url, 'http://localhost');
      const deviceId = url.searchParams.get('deviceId') || '';
      let user = null;

      try {
        user = await authenticateWebSocket(req, { requireAuth: this.requireAuth });
      } catch (error) {
        socket.close(1008, error.message);
        return;
      }

      this.clients.set(socket, { deviceId, user });
      socket.send(
        JSON.stringify({
          type: 'hello',
          deviceId: deviceId || null,
          serverTime: new Date().toISOString(),
          localBackend: true,
          firebaseLoginUser: user,
        }),
      );

      socket.on('message', (raw) => this.handleClientMessage(socket, raw));
      socket.on('close', () => this.clients.delete(socket));
      socket.on('error', () => this.clients.delete(socket));
    });
  }

  async handleClientMessage(socket, raw) {
    const message = parseJsonMessage(raw.toString());
    if (!message) return;

    if (message.type === 'ping') {
      socket.send(JSON.stringify({ type: 'pong', ts: new Date().toISOString() }));
    }
  }

  broadcast(type, payload) {
    const deviceId = payload && payload.deviceId ? String(payload.deviceId) : '';
    const encoded = JSON.stringify({ type, payload });

    for (const [socket, meta] of this.clients.entries()) {
      if (socket.readyState !== WebSocket.OPEN) continue;
      if (meta.deviceId && deviceId && meta.deviceId !== deviceId) continue;
      socket.send(encoded);
    }
  }
}

module.exports = { WsHub };
