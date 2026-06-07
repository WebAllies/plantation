const net = require('net');
const aedes = require('aedes');

function topicDevice(topic, suffix) {
  const parts = topic.split('/');
  if (parts.length < 3 || parts[0] !== 'plantation') return null;
  if (!topic.endsWith(suffix)) return null;
  return parts[1];
}

function decodePayload(packet) {
  const raw = packet.payload ? packet.payload.toString('utf8') : '';
  if (!raw) return {};
  try {
    const decoded = JSON.parse(raw);
    return decoded && typeof decoded === 'object' ? decoded : {};
  } catch (_) {
    return {};
  }
}

class LocalMqttBroker {
  constructor({ db, hub, port, logger = console }) {
    this.db = db;
    this.hub = hub;
    this.port = port;
    this.logger = logger;
    this.broker = aedes();
    this.server = net.createServer(this.broker.handle);
  }

  start() {
    this.broker.on('client', (client) => {
      this.logger.log(`[mqtt] client connected ${client ? client.id : 'unknown'}`);
    });

    this.broker.on('clientDisconnect', (client) => {
      this.logger.log(`[mqtt] client disconnected ${client ? client.id : 'unknown'}`);
    });

    this.broker.on('publish', (packet, client) => {
      if (!client) return;
      this.handlePublish(packet).catch((error) => {
        this.logger.warn(`[mqtt] publish handler failed: ${error.message || error}`);
      });
    });

    this.server.listen(this.port, () => {
      this.logger.log(`[mqtt] broker listening on mqtt://0.0.0.0:${this.port}`);
    });
  }

  async handlePublish(packet) {
    const topic = packet.topic || '';
    const telemetryDeviceId = topicDevice(topic, '/telemetry/live');
    if (telemetryDeviceId) {
      const payload = decodePayload(packet);
      const stored = await this.db.storeTelemetry(telemetryDeviceId, payload);
      this.hub.broadcast('telemetry', stored.payload);
      return;
    }

    const statusDeviceId = topicDevice(topic, '/status');
    if (statusDeviceId) {
      const payload = decodePayload(packet);
      const device = await this.db.updateDeviceStatus(statusDeviceId, payload);
      this.hub.broadcast('device_status', {
        deviceId: statusDeviceId,
        online: device.online,
        espStatus: device.espStatus,
        lastSeen: device.lastSeen,
      });
      return;
    }

    const ackDeviceId = topicDevice(topic, '/commands/ack');
    if (ackDeviceId) {
      const payload = decodePayload(packet);
      const command = await this.db.updateCommandFromAck(ackDeviceId, payload);
      if (command) this.hub.broadcast('command', command);
    }
  }

  publishCommand(command) {
    const topic = `plantation/${command.deviceId}/commands`;
    const cleanCommand = {};
    for (const [key, value] of Object.entries(command)) {
      if (value !== null && value !== undefined) cleanCommand[key] = value;
    }
    const payload = JSON.stringify(cleanCommand);
    this.broker.publish(
      {
        topic,
        payload,
        qos: 1,
        retain: false,
      },
      (error) => {
        if (error) {
          this.logger.warn(`[mqtt] command publish failed: ${error.message || error}`);
        }
      },
    );
  }
}

module.exports = { LocalMqttBroker };
