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
  constructor({ server, db, requireAuth, mqtt = null, logger = console }) {
    this.db = db;
    this.requireAuth = requireAuth;
    this.mqtt = mqtt;
    this.logger = logger;
    this.wss = new WebSocketServer({ server, path: '/ws' });
    this.clients = new Map();
  }

  // The MQTT broker is created after the hub, so it is attached afterwards.
  attachMqtt(mqtt) {
    this.mqtt = mqtt;
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
      this.sendInitialDeviceState(socket, deviceId).catch((error) => {
        this.logger.warn(`[ws] initial stream snapshot failed: ${error.message || error}`);
      });

      const heartbeat = setInterval(() => {
        if (socket.readyState !== WebSocket.OPEN) return;
        socket.send(
          JSON.stringify({
            type: 'stream_heartbeat',
            payload: {
              deviceId: deviceId || null,
              serverTime: new Date().toISOString(),
              localBackend: true,
            },
          }),
        );
      }, 5000);

      socket.on('message', (raw) => this.handleClientMessage(socket, raw));
      socket.on('close', () => {
        clearInterval(heartbeat);
        this.clients.delete(socket);
      });
      socket.on('error', () => {
        clearInterval(heartbeat);
        this.clients.delete(socket);
      });
    });
  }

  async sendInitialDeviceState(socket, deviceId) {
    if (!deviceId || socket.readyState !== WebSocket.OPEN) return;
    const device = await this.db.getDevice(deviceId);
    if (!device || socket.readyState !== WebSocket.OPEN) return;

    socket.send(
      JSON.stringify({
        type: 'device_status',
        payload: {
          deviceId,
          online: device.online,
          espStatus: device.espStatus,
          lastSeen: device.lastSeen,
        },
      }),
    );

    const lastPayload =
      device.lastPayload && typeof device.lastPayload === 'object' ? device.lastPayload : {};
    if (Object.keys(lastPayload).length === 0) return;

    socket.send(
      JSON.stringify({
        type: 'telemetry',
        payload: {
          ...lastPayload,
          deviceId,
          streamReplay: true,
          streamedAt: new Date().toISOString(),
        },
      }),
    );
  }

  async handleClientMessage(socket, raw) {
    const message = parseJsonMessage(raw.toString());
    if (!message) return;

    if (message.type === 'ping') {
      socket.send(JSON.stringify({ type: 'pong', ts: new Date().toISOString() }));
      return;
    }

    if (message.type === 'command') {
      await this.handleCommandMessage(socket, message);
    }
  }

  // Accept device commands over the WebSocket so the app can send them on the
  // already-open connection (no per-press HTTP handshake). Same path as the
  // HTTP endpoint: persist -> publish to MQTT -> broadcast.
  async handleCommandMessage(socket, message) {
    const meta = this.clients.get(socket) || {};
    const requestId = message.requestId != null ? message.requestId : null;
    const deviceId = String(message.deviceId || meta.deviceId || '');
    const commandBody =
      message.payload && typeof message.payload === 'object' ? message.payload : message;

    try {
      if (!deviceId) throw new Error('deviceId is required');
      const command = await this.db.createCommand(deviceId, commandBody, meta.user || null);
      if (this.mqtt) this.mqtt.publishCommand(command);
      this.broadcast('command', command);
      socket.send(
        JSON.stringify({ type: 'command_result', requestId, ok: true, command }),
      );
    } catch (error) {
      this.logger.warn(`[ws] command failed: ${error.message || error}`);
      socket.send(
        JSON.stringify({
          type: 'command_result',
          requestId,
          ok: false,
          error: error.message || String(error),
        }),
      );
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
