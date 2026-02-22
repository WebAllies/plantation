# Plantation (IoT Aqua App)

Flutter + Firebase + ESP32 telemetry system using managed MQTT for global realtime access.

## What This Repo Uses

- Realtime live stream: MQTT
- App transport to broker: `wss` (HiveMQ Cloud port `8884`, path `/mqtt`)
- Device transport to broker: `mqtts` (HiveMQ Cloud port `8883`)
- Commands: Firestore (`devices/{deviceId}/commands`)
- Fallback when live stream is down: latest Firestore snapshot

Legacy LAN WebSocket (`wsUrl`) is still supported as fallback during migration, but MQTT is the primary path.

## Architecture

1. Device (ESP32 / `esp32sim`) publishes telemetry to:
   `plantation/{deviceId}/telemetry/live`
2. Device publishes retained status (`online` / LWT `offline`) to:
   `plantation/{deviceId}/status`
3. Flutter app reads `devices/{deviceId}` and, when MQTT is enabled, calls callable function:
   `issueMqttCredentials`
4. Cloud Function returns broker endpoint + auth + topics.
5. Flutter subscribes and renders realtime values.
6. If MQTT fails, dashboard still renders Firestore snapshot data.

## Prerequisites

- Flutter SDK
- Firebase project (Firestore + Auth + Functions enabled)
- Node.js + npm
- Arduino IDE / PlatformIO for ESP32 firmware
- HiveMQ Cloud cluster

## 1) HiveMQ Cloud Setup

From your HiveMQ cluster details page:

- Broker host: `<cluster-id>.<region>.hivemq.cloud`
- TLS MQTT port (device): `8883`
- TLS WebSocket port (app/web): `8884`
- TLS WebSocket path: `/mqtt`

Create at least one credential in HiveMQ Access Management.

Quick test permission (wide open, for first verification only):

- allow publish/subscribe on `#`

After verification, tighten ACLs:

- Device credential:
  - publish `plantation/{deviceId}/telemetry/live`
  - publish retained `plantation/{deviceId}/status`
- App credential:
  - subscribe `plantation/+/telemetry/live`
  - subscribe `plantation/+/status`

## 2) Configure Firebase Functions

This project is currently Spark-plan compatible and uses `functions/.env` params instead of Secret Manager.

Create `functions/.env`:

```env
# Broker endpoint
MQTT_BROKER_URL=wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt
MQTT_BROKER_HOST=YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud
MQTT_BROKER_PORT=8884
MQTT_WS_PATH=/mqtt
MQTT_USE_TLS=true
MQTT_USE_WEBSOCKET=true

# Auth returned to Flutter app by issueMqttCredentials
MQTT_USERNAME_STATIC=YOUR_HIVEMQ_APP_USERNAME
MQTT_PASSWORD_STATIC=YOUR_HIVEMQ_APP_PASSWORD

# Keep empty for HiveMQ username/password mode
MQTT_JWT_SECRET=
MQTT_USERNAME_PREFIX=app
```

Important:

- Every key above is defined in `functions/index.js`.
- If any key is missing, deploy can prompt interactively.
- `functions/.env` is gitignored.

## 3) Deploy Functions

From project root:

```bash
npx firebase-tools@latest deploy --only functions --project iotaquaapp
```

Deployed callable:

- `issueMqttCredentials` (`us-central1`)

If asked about Artifact Registry cleanup policy, choose a retention (for example `1` day) to avoid image buildup cost.

## 4) Required Firestore Device Fields

Each `devices/{deviceId}` doc should include:

- `realtimeTransport: "mqtt"`
- `mqttEnabled: true`
- `mqttTopicLive: "plantation/{deviceId}/telemetry/live"`
- `mqttStatusTopic: "plantation/{deviceId}/status"`

Optional legacy fallback:

- `wsUrl`

## 5) ESP32 / ESP32 Simulator Setup

Files:

- `esp32`
- `esp32sim`

Set these values before upload:

- `WIFI_SSID`, `WIFI_PASS`
- Firebase config (`API_KEY`, `FIREBASE_PROJECT_ID`, device auth email/password)
- MQTT config:
  - `MQTT_BROKER_HOST=YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud`
  - `MQTT_BROKER_PORT=8883`
  - `MQTT_USERNAME=...`
  - `MQTT_PASSWORD=...`

The sketches already publish:

- live telemetry to `plantation/{deviceId}/telemetry/live`
- retained status/LWT to `plantation/{deviceId}/status`

## 6) Run Flutter App

```bash
flutter pub get
flutter run
```

Dashboard behavior:

- Uses MQTT when `realtimeTransport == "mqtt"` and `mqttEnabled == true`.
- Falls back to Firestore/legacy transport if MQTT is unavailable.

## Telemetry Payload Contract

Expected live payload fields:

- `deviceId` (string)
- `tsEpochMs` (int, UTC epoch milliseconds)
- `temperatureC` (double)
- `ph` (double)
- `waterLevelPct` (double)
- `tdsPpm` (double)
- `pumpState` (bool)
- `valveState` (bool)
- `rssi` (int)

## Troubleshooting

### `firebase` command not found

Use `npx`:

```bash
npx firebase-tools@latest <command>
```

### `functions:secrets:set` requires Blaze

Correct. Secret Manager requires Blaze. This repo avoids it by using `functions/.env`.

### Deploy keeps asking for values

Your `functions/.env` is missing one or more required keys. Add all keys listed above.

### Flutter analyzer error: `websocketPath` setter not defined

Use current implementation in `lib/core/realtime/mqtt_client_factory_io.dart` that builds the full websocket URL in constructor and does not set `client.websocketPath`.

### Dashboard shows fallback only (no live stream)

Check:

- `devices/{deviceId}` contains MQTT fields above
- HiveMQ credential/ACL is correct
- Function `issueMqttCredentials` deployed successfully
- App user is signed in (callable is authenticated)

### ESP32 compile error: sketch too big

In Arduino IDE:

- `Tools > Partition Scheme > Huge APP (3MB No OTA/1MB SPIFFS)`
- `Tools > Core Debug Level > None`

Then compile/upload again.

## Security Checklist

- Never commit real MQTT passwords in `esp32`, `esp32sim`, or docs.
- Rotate credentials immediately if they were exposed.
- Prefer separate credentials for app and devices.
- Prefer strict ACLs per topic/device.
- For production, replace `setInsecure()` in ESP with proper CA validation.
