# iot_aqua_app

Global realtime telemetry migration is now implemented with MQTT as the primary transport and Firestore as fallback/history.

## What Changed

- `DashboardPage` now supports transport selection from Firestore device fields:
  - `realtimeTransport: "mqtt"`
  - `mqttEnabled: true`
  - `mqttTopicLive`
  - `mqttStatusTopic`
- If MQTT is enabled, the app subscribes to MQTT live topic.
- If MQTT is not enabled, the app falls back to legacy `wsUrl` WebSocket behavior.
- Firestore commands are unchanged.

## Device Document Fields

For each `devices/{deviceId}` document, set:

- `realtimeTransport` = `"mqtt"`
- `mqttEnabled` = `true`
- `mqttTopicLive` = `"plantation/{deviceId}/telemetry/live"`
- `mqttStatusTopic` = `"plantation/{deviceId}/status"`

`wsUrl` remains optional as legacy fallback.

## Backend: MQTT Credential Issuance

A callable Firebase Function is added:

- `issueMqttCredentials`

Path: `functions/index.js`

It validates Firebase Auth, verifies device existence, then returns short-lived MQTT auth data.

### Deploy Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

### Required Function Params

Configure one of these broker settings:

- `MQTT_BROKER_URL` (e.g. `wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt`)
- OR `MQTT_BROKER_HOST` + `MQTT_BROKER_PORT`

Configure auth:

- HiveMQ username/password mode:
  - `MQTT_USERNAME_STATIC`
  - `MQTT_PASSWORD_STATIC`
- Alternative token mode:
  - `MQTT_JWT_SECRET`

Optional:

- `MQTT_WS_PATH` (default `/mqtt`)
- `MQTT_USE_TLS` (default `true`)
- `MQTT_USE_WEBSOCKET` (default `true`)
- `MQTT_USERNAME_PREFIX` (default `app`)

## Flutter MQTT Notes

Added dependencies:

- `mqtt_client`
- `cloud_functions`

Runtime flow:

1. App reads selected device document.
2. If MQTT is enabled, app calls `issueMqttCredentials`.
3. App connects via MQTT and subscribes to `mqttTopicLive`.
4. If stream is unavailable, dashboard still shows Firestore snapshot fallback.

### Optional Local Fallback (No Function)

You can also provide compile-time values for development:

- `MQTT_BROKER_URL`
- `MQTT_BROKER_HOST`
- `MQTT_BROKER_PORT`
- `MQTT_WS_PATH`
- `MQTT_USE_TLS`
- `MQTT_USE_WEBSOCKET`
- `MQTT_USERNAME`
- `MQTT_PASSWORD`

## HiveMQ Cloud Setup (Recommended)

1. In HiveMQ Cloud, create credentials:
   - one for app subscribers
   - one for device publishers
2. Use these ports:
   - app via WSS: `8884`, path `/mqtt`
   - ESP/device via TLS MQTT: `8883`
3. Configure Firebase Function for app credentials:

```bash
cd functions
npm install

cat > .env <<'EOF'
MQTT_BROKER_URL=wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt
MQTT_WS_PATH=/mqtt
MQTT_USE_TLS=true
MQTT_USE_WEBSOCKET=true
MQTT_USERNAME_STATIC=YOUR_HIVEMQ_APP_USERNAME
MQTT_PASSWORD_STATIC=YOUR_HIVEMQ_APP_PASSWORD
EOF

firebase deploy --only functions
```

4. Set firmware credentials for device publish:
   - in `esp32` and `esp32sim`, set:
     - `MQTT_BROKER_HOST`
     - `MQTT_BROKER_PORT` = `8883`
     - `MQTT_USERNAME`
     - `MQTT_PASSWORD`

## ESP / Simulator

Both `esp32` and `esp32sim` now:

- publish live telemetry to MQTT topic `plantation/{deviceId}/telemetry/live`
- publish online/offline status to `plantation/{deviceId}/status` (LWT)
- write MQTT metadata fields to Firestore device document
- keep Firestore command polling flow unchanged

Set these in firmware before flashing:

- `MQTT_BROKER_HOST`
- `MQTT_BROKER_PORT`
- `MQTT_USERNAME`
- `MQTT_PASSWORD`

## Legacy Relay

No local relay service is required for realtime telemetry after this migration.
