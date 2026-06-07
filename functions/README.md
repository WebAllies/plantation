# Firebase Functions (Backend)

This folder contains Firebase Cloud Functions (Gen2) for MQTT credential issuance, sensor alert evaluation, and automation workflows.

## Functions In This Codebase
- `issueMqttCredentials` (callable HTTPS)
  - Returns MQTT broker connection/auth payload for app clients.
- `evaluateDeviceAlerts` (Firestore trigger)
  - Trigger: writes on `devices/{deviceId}`
  - Evaluates sensor thresholds and updates alert state/history.
- `recomputeAlertsOnGlobalThresholdsWrite` (Firestore trigger)
  - Trigger: writes on `settings/sensors`
  - Recomputes alerts for all devices after global threshold changes.
- `recomputeAlertsOnDeviceOverrideWrite` (Firestore trigger)
  - Trigger: writes on `devices/{deviceId}/configs/sensors`
  - Recomputes alerts for one device after override changes.
- `cleanupOldAlerts` (scheduled)
  - Deletes old alert history docs.
- `markStaleDevicesOffline` (scheduled)
  - Marks devices offline when their `lastSeen` heartbeat becomes stale.
- `dispatchFeedingSchedules` (scheduled)
  - Creates fish feeder commands from device feeding schedules.

Global options from code:
- Region: `us-central1`
- Max instances: `10`

Source file:
- `functions/index.js`

## Runtime And Versions
- Node.js runtime: `20` (`functions/package.json`)
- Firebase Functions SDK: `^5.1.1`
- Firebase Admin SDK: `^12.7.0`

Note from Firebase CLI:
- Node 20 deprecation starts April 30, 2026, with decommission on October 30, 2026.
- Plan runtime upgrade to Node 22 before those dates.

## Prerequisites
From project root machine:
- `firebase` CLI available (`firebase --version`)
- Node.js 20+ available (`node --version`)

Install dependencies:

```bash
cd functions
npm install
cd ..
```

## Environment Variables
Functions use parameterized env values (defined in code via `defineString`).

Create base file: `functions/.env`

```env
MQTT_BROKER_URL=wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt
MQTT_BROKER_HOST=YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud
MQTT_BROKER_PORT=8884
MQTT_WS_PATH=/mqtt
MQTT_USE_TLS=true
MQTT_USE_WEBSOCKET=true

MQTT_USERNAME_STATIC=YOUR_HIVEMQ_APP_USERNAME
MQTT_PASSWORD_STATIC=YOUR_HIVEMQ_APP_PASSWORD
MQTT_USERNAME_PREFIX=app
MQTT_JWT_SECRET=
```

Variables read by functions:
- `MQTT_BROKER_URL`
- `MQTT_BROKER_HOST`
- `MQTT_BROKER_PORT`
- `MQTT_WS_PATH`
- `MQTT_USE_TLS`
- `MQTT_USE_WEBSOCKET`
- `MQTT_JWT_SECRET`
- `MQTT_PASSWORD_STATIC`
- `MQTT_USERNAME_STATIC`
- `MQTT_USERNAME_PREFIX`

During deploy, Firebase may create per-project files automatically:
- `functions/.env.<project-id>`

Use these to keep staging and production values separate.

## Deploy Commands
Run from repository root.

Deploy functions only:

```bash
npx firebase-tools deploy --only "functions" --project <project-id>
```

Deploy functions + Firestore rules + Storage rules:

```bash
npx firebase-tools deploy --only "functions,firestore:rules,storage" --project <project-id>
```

PowerShell requirement:
- Keep comma-separated `--only` list inside quotes.

Deploy specific functions only:

```bash
npx firebase-tools deploy --only "functions:evaluateDeviceAlerts,functions:recomputeAlertsOnGlobalThresholdsWrite,functions:recomputeAlertsOnDeviceOverrideWrite" --project <project-id>
```

## First Gen2 Deploy: Common Eventarc Error
If this project has never deployed Gen2 functions before, you may get:
- Eventarc Service Agent permission errors (HTTP 400 validation failure)

Fix:
1. Wait 3-10 minutes for API/service-agent IAM propagation.
2. Re-run deploy for failed functions only.

This is normal on first-time setup.

## Firestore Paths Used By Functions
Read paths:
- `settings/sensors`
- `devices/{deviceId}`
- `devices/{deviceId}/configs/sensors`
- `devices/{deviceId}/alert_state/current`
- `devices/{deviceId}/automation/tds`

Write paths:
- `devices/{deviceId}/alert_state/current`
- `devices/{deviceId}/alerts/{alertId}`
- `devices/{deviceId}/automation/tds`
- `devices/{deviceId}/commands/{commandId}`
- `devices/{deviceId}`

Expected telemetry fields in `devices/{deviceId}`:
- `temperatureC`
- `ph`
- `waterLevelPct`
- `tdsPpm`
- `online`
- `espStatus`
- `lastSeen`
- `heartbeatSeq`

Optional monitoring-only telemetry fields that may also be present:
- `phUpTankLevelPct`
- `phDownTankLevelPct`
- `nutrientTankLevelPct`
- `sensorStatus`
- `lastReadOk`
- `sampleCount`
- `offlineDetectedAt`

These extra fields are allowed on device documents and reading snapshots but are not part of the current alert evaluation logic.
The app treats a device as live only while MQTT/WebSocket telemetry or the Firestore `lastSeen` heartbeat is recent. The scheduled Firebase job also sets `online: false` and `espStatus: offline` for stale devices so dashboards recover correctly after the ESP32 loses WiFi or power.

## Post-Deploy Verification
1. Confirm deploy succeeded in Firebase Console -> Functions.
2. Confirm `settings/sensors` exists in Firestore.
3. Write/update a device document in `devices/{deviceId}`.
4. Verify function updates:
   - `devices/{deviceId}/alert_state/current`
   - `devices/{deviceId}/alerts/*`
5. If low-TDS automation is enabled, verify command writes:
   - `devices/{deviceId}/commands/*`
6. Confirm scheduled cleanup, feeder dispatch, and stale-device functions exist and are enabled.

## Local Emulator (Optional)
From `functions/`:

```bash
npm run serve
```

Or from root:

```bash
npx firebase-tools emulators:start --only functions
```

## Troubleshooting

`firebase: not recognized`
- Install CLI: `npm install -g firebase-tools`
- If still failing, use `npx firebase-tools ...`
- Add npm global bin to PATH on Windows (`%APPDATA%\\npm`).

Deploy prompts for env values every time
- Ensure `functions/.env.<project-id>` exists and has values.
- Commit policy: keep env files out of git (already ignored).

`functions: package.json indicates outdated firebase-functions`
- Current code works on `^5.1.1`, but plan an upgrade window.
- Test in staging before upgrading major SDK versions.

Need to remove a function

```bash
npx firebase-tools functions:delete <functionName> --region us-central1 --project <project-id>
```

