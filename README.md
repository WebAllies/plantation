# Plantation (IoT Aqua App)

Flutter + Firebase + ESP32 telemetry system using managed MQTT for global realtime access.

## What This Repo Uses

- Realtime live stream: MQTT
- App transport to broker: `wss` (HiveMQ Cloud port `8884`, path `/mqtt`)
- Device transport to broker: `mqtts` (HiveMQ Cloud port `8883`)
- Commands: Firestore (`devices/{deviceId}/commands`)
- Alerting and automation: Firestore-triggered Cloud Functions
- Fallback when live stream is down: latest Firestore snapshot

Legacy LAN WebSocket (`wsUrl`) is still supported as fallback during migration, but MQTT is the primary path.

## Architecture

1. Device (ESP32 / `esp32sim`) publishes telemetry to:
   `plantation/{deviceId}/telemetry/live`
2. Device publishes retained status (`online` / LWT `offline`) to:
   `plantation/{deviceId}/status`
3. Flutter app reads `devices/{deviceId}` and, when MQTT is enabled, calls callable function:
   `issueMqttCredentials`
4. Cloud Function `evaluateDeviceAlerts` runs on `devices/{deviceId}` updates, evaluates thresholds, writes:
   - `devices/{deviceId}/alert_state/current`
   - `devices/{deviceId}/alerts/*`
5. If low TDS automation is enabled and breached, backend writes pump commands to:
   `devices/{deviceId}/commands`
6. Dashboard + Analytics show active alerts and in-app reminders every 15 seconds while alerts are active.
7. Scheduled Function `cleanupOldAlerts` deletes alert history older than 3 days.

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

## 3) Deploy Backend

From project root:

```bash
npx firebase-tools@latest deploy --only functions,firestore:rules --project iotaquaapp
```

Deployed backend entries:

- `issueMqttCredentials` (callable, `us-central1`)
- `evaluateDeviceAlerts` (Firestore trigger on `devices/{deviceId}`)
- `cleanupOldAlerts` (scheduled daily retention cleanup)

If asked about Artifact Registry cleanup policy, choose a retention (for example `1` day) to avoid image buildup cost.

## 4) Required Firestore Device Fields

Each `devices/{deviceId}` doc should include:

- `realtimeTransport: "mqtt"`
- `mqttEnabled: true`
- `mqttTopicLive: "plantation/{deviceId}/telemetry/live"`
- `mqttStatusTopic: "plantation/{deviceId}/status"`

Optional legacy fallback:

- `wsUrl`

## 5) Sensor Thresholds and Alerts Schema

Global defaults:

- Doc: `settings/sensors`
- Fields:
  - `thresholds.temperatureMinC`
  - `thresholds.temperatureMaxC`
  - `thresholds.phMin`
  - `thresholds.phMax`
  - `thresholds.waterLevelLowPct`
  - `thresholds.tdsMinPpm`
  - `thresholds.tdsMaxPpm`
  - `automation.lowTdsAutoDoseEnabled`
  - `automation.pumpMaxRunSec`
  - `automation.stopTarget` (`tds_max`)
  - `reminders.inAppIntervalSec` (`15`)

Per-device override:

- Doc: `devices/{deviceId}/configs/sensors`
- Fields:
  - `overrideEnabled`
  - `thresholds.*` (same shape as global)
  - `automation.lowTdsAutoDoseEnabled`

Runtime alert state:

- Doc: `devices/{deviceId}/alert_state/current`
- Fields:
  - `activeMetrics`
  - `metrics.temperature.state`
  - `metrics.ph.state`
  - `metrics.waterLevel.state`
  - `metrics.tds.state`
  - `latestValues.*`
  - `effectiveSource` (`global` or `override`)

Alert history:

- Collection: `devices/{deviceId}/alerts`
- Typical fields:
  - `eventType` (`breach_started`, `recovered`, `auto_dose_started`, `auto_dose_completed`, `auto_dose_timeout`)
  - `metric`, `state`, `value`, `message`, `thresholdSnapshot`, `source`, `createdAt`
- Retention: 3 days via scheduled cleanup.

Automation state:

- Doc: `devices/{deviceId}/automation/tds`
- Fields: `active`, `startedAt`, `targetTdsMax`, `timeoutSec`, `lastAction`, `updatedAt`

## 6) Quick Start: Sensor Thresholds (First Run)

Use this when you set up threshold logic for the first time.

1. Deploy backend and rules:

```bash
npx firebase-tools@latest deploy --only functions,firestore:rules --project iotaquaapp
```

2. Open the app and go to `Settings -> Sensors`.

3. In `Global Defaults`, set and save:
   - Temperature Min/Max: `22` / `28`
   - pH Min/Max: `6.0` / `7.2`
   - Water Level Low: `30`
   - TDS Min/Max: `800` / `1200`
   - Auto-dose for low TDS: `OFF` (default first run)

4. Optional per-device override:
   - Select a greenhouse/device from the header selector
   - Enable `Device Override`
   - Set override values and save to `devices/{deviceId}/configs/sensors`

5. Verify Firestore writes:
   - `settings/sensors` exists and has `thresholds.*`, `automation.*`, `reminders.inAppIntervalSec`
   - `devices/{deviceId}/configs/sensors` exists when override is saved

6. Verify alert pipeline:
   - Open `Dashboard` and `Analytics` for the same device
   - If telemetry goes out of range, expect:
     - `devices/{deviceId}/alert_state/current.activeMetrics` contains breached metric(s)
     - New docs in `devices/{deviceId}/alerts` with `eventType: breach_started`
     - In-app reminder SnackBar every ~15 seconds while alerts remain active

7. Verify low-TDS automation (only when enabled):
   - Turn ON low-TDS auto-dose in effective settings (global or override)
   - Cause low TDS condition (`tdsPpm < tdsMinPpm`)
   - Expect:
     - Pending command in `devices/{deviceId}/commands` with `type: pump`, `targetState: true`
     - `devices/{deviceId}/automation/tds.active == true`
     - `auto_dose_started` event in `devices/{deviceId}/alerts`
   - When `tdsPpm >= tdsMaxPpm` (or timeout), expect pump stop command + completion/timeout event

## 7) App Behavior

Dashboard:

- Uses MQTT when `realtimeTransport == "mqtt"` and `mqttEnabled == true`
- Falls back to Firestore/legacy transport if MQTT is unavailable
- Shows active alert card from `alert_state/current`
- Shows in-app alert reminder every 15 seconds while alerts are active

Analytics:

- Contains an Alerts section
- Shows active alerts from `alert_state/current`
- Shows alert history for the last 3 days from `devices/{deviceId}/alerts`
- Runs same 15-second in-app reminder while alerts are active

Settings -> Sensors:

- Global threshold editor (`settings/sensors`)
- Device override editor (`devices/{deviceId}/configs/sensors`)
- Validation for ranges and numeric values

## 8) ESP32 / ESP32 Simulator Setup

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

## 9) Run Flutter App

```bash
flutter pub get
flutter run
```

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

### Dashboard shows fallback only (no live stream)

Check:

- `devices/{deviceId}` contains MQTT fields above
- HiveMQ credential/ACL is correct
- Function `issueMqttCredentials` deployed successfully
- App user is signed in (callable is authenticated)

### Alerts are not being generated

Check:

- `evaluateDeviceAlerts` is deployed
- Firestore rules are deployed
- Telemetry fields are present on `devices/{deviceId}` (`temperatureC`, `ph`, `waterLevelPct`, `tdsPpm`)
- Threshold docs exist or defaults are being used

### Auto-dose is not triggering

Check:

- Effective settings have `lowTdsAutoDoseEnabled == true`
- Current `tdsPpm` is below configured `tdsMinPpm`
- Device command polling is working for `devices/{deviceId}/commands`

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

## AI Model Pipeline (Lettuce v2)

### App model assets

- `assets/models/lettuce_model.tflite`
- `assets/models/labels.txt` (6 classes)
- `assets/models/model_config.json` (thresholds + binary map + version)

### Firestore AI scan schema

`ai_scans/{scanId}` now stores:

- `predictedClass`
- `predictedBinary`
- `label` (legacy binary compatibility field)
- `confidence`
- `topK`
- `modelVersion`
- `imagePath`
- `verificationStatus` (`pending|verified|rejected`)
- `verifiedLabel`
- `verifiedBy`
- `verifiedAt`
- `captureMetadata.farmId`
- `captureMetadata.deviceId`
- `captureMetadata.captureSessionId`
- `captureMetadata.timeOfDay`
- `createdAt`

### Verification feedback loop

- Super admins can verify/correct labels from `AI Scan Reports`.
- Verified scans can be exported for retraining using:
  - `node ml/export_verified_dataset.js ...`

### Local training workspace

Training scripts are in `ml/`:

- `ml/train.py`
- `ml/evaluate.py`
- `ml/calibrate_thresholds.py`
- `ml/export_tflite.py`
- `ml/configs/v1.yaml`

See `ml/README.md` for exact commands.
