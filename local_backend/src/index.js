const http = require('http');
const config = require('./config');
const { LocalDatabase } = require('./db');
const { FirebaseBackup, runFirebaseSyncLoop } = require('./firebase_backup');
const { createHttpApi } = require('./http_api');
const { LocalMqttBroker } = require('./mqtt_broker');
const { WsHub } = require('./ws_hub');

async function main() {
  const db = new LocalDatabase({ databaseUrl: config.databaseUrl });
  await db.migrate();

  const firebase = new FirebaseBackup({
    enabled: config.firebaseBackupEnabled,
    projectId: config.firebaseProjectId,
    webApiKey: config.firebaseWebApiKey,
    backupEmail: config.firebaseBackupEmail,
    backupPassword: config.firebaseBackupPassword,
  });
  firebase.init();

  const server = http.createServer();
  const hub = new WsHub({
    server,
    db,
    requireAuth: config.requireFirebaseAuth,
  });
  hub.start();

  const mqtt = new LocalMqttBroker({
    db,
    hub,
    port: config.mqttPort,
  });
  mqtt.start();
  // Let the WebSocket hub publish app commands straight to MQTT.
  hub.attachMqtt(mqtt);

  const app = createHttpApi({
    db,
    hub,
    mqtt,
    requireAuth: config.requireFirebaseAuth,
  });
  server.on('request', app);
  server.listen(config.httpPort, () => {
    console.log(`[http] listening on http://0.0.0.0:${config.httpPort}`);
    console.log(`[ws] listening on ws://0.0.0.0:${config.httpPort}/ws`);
  });

  await runFirebaseSyncLoop({
    db,
    firebase,
    intervalMs: config.firebaseSyncIntervalMs,
    batchSize: config.firebaseSyncBatchSize,
  });

  setInterval(async () => {
    try {
      const stale = await db.markStaleDevicesOffline(config.deviceOfflineAfterMs);
      for (const device of stale) {
        hub.broadcast('device_status', {
          deviceId: device.deviceId,
          online: false,
          espStatus: 'offline',
          lastSeen: device.lastSeen,
        });
      }
    } catch (error) {
      console.warn(`[devices] stale scan failed: ${error.message || error}`);
    }
  }, 5000);

  const shutdown = async () => {
    console.log('[shutdown] stopping local backend');
    server.close();
    mqtt.server.close();
    await db.close();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
