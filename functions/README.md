# Firebase Functions

Backend services for MQTT credentials, alert evaluation, automation commands, and cleanup jobs.

## Exported Functions

- `issueMqttCredentials` (callable)
  - Returns broker connection/auth payload for app MQTT subscription.
- `evaluateDeviceAlerts` (Firestore trigger)
  - Trigger: writes to `devices/{deviceId}`
  - Evaluates sensor thresholds and writes alert state/history.
  - Handles low-TDS automation command lifecycle.
- `recomputeAlertsOnGlobalThresholdsWrite` (Firestore trigger)
  - Trigger: writes to `settings/sensors`
  - Recomputes alert state for all devices after global settings update.
- `recomputeAlertsOnDeviceOverrideWrite` (Firestore trigger)
  - Trigger: writes to `devices/{deviceId}/configs/sensors`
  - Recomputes alert state for that device after override changes.
- `cleanupOldAlerts` (scheduled)
  - Deletes `devices/{deviceId}/alerts` docs older than retention window.

## Runtime + Dependencies

- Node.js: `20` (see `functions/package.json`)
- Main entry: `functions/index.js`

Install dependencies:

```bash
cd functions
npm install
cd ..
```

## Configuration

Create `functions/.env` with MQTT params:

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

Required for broker connection/auth:
- `MQTT_BROKER_URL` or (`MQTT_BROKER_HOST` + `MQTT_BROKER_PORT`)
- `MQTT_USERNAME_STATIC`
- `MQTT_PASSWORD_STATIC`

## Deploy

From repo root:

```bash
firebase deploy --only functions --project <project-id>
```

Deploy with rules at the same time:

```bash
firebase deploy --only functions,firestore:rules,storage --project <project-id>
```

## Local Emulator

```bash
cd functions
npm run serve
```

## Firestore Paths Used

Read:
- `settings/sensors`
- `devices/{deviceId}`
- `devices/{deviceId}/configs/sensors`
- `devices/{deviceId}/alert_state/current`
- `devices/{deviceId}/automation/tds`

Write:
- `devices/{deviceId}/alert_state/current`
- `devices/{deviceId}/alerts/{alertId}`
- `devices/{deviceId}/automation/tds`
- `devices/{deviceId}/commands/{commandId}`

## Expected Device Metrics in `devices/{deviceId}`

- `temperatureC`
- `ph`
- `waterLevelPct`
- `tdsPpm`

## Alert / Automation Behavior

- Threshold source can be global or per-device override.
- Transition-only alert history events are appended.
- Low-TDS automation can issue pump commands when enabled.
- Alert history retention cleanup runs on schedule.

## Post-Deploy Verification

1. Confirm `settings/sensors` exists.
2. Confirm telemetry updates in `devices/{deviceId}`.
3. Force a breach and check:
   - `devices/{deviceId}/alert_state/current`
   - `devices/{deviceId}/alerts`
4. If low-TDS automation enabled, confirm command writes in `devices/{deviceId}/commands`.
