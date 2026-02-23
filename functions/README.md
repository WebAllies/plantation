# Firebase Functions (MQTT + Alerts + Automation)

This folder contains backend functions for:

- issuing short-lived MQTT credentials to authenticated app users
- evaluating device telemetry against sensor thresholds
- writing alert state/history and optional low-TDS automation commands
- cleaning up old alerts (3-day retention)

## Deploy

1. Install dependencies:
   `npm install`
2. Configure non-secret params in `functions/.env`:
   - `MQTT_BROKER_URL=wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt`
   - `MQTT_WS_PATH=/mqtt`
   - `MQTT_USE_TLS=true`
   - `MQTT_USE_WEBSOCKET=true`
   - `MQTT_USERNAME_STATIC=YOUR_HIVEMQ_APP_USERNAME`
   - `MQTT_PASSWORD_STATIC=YOUR_HIVEMQ_APP_PASSWORD`
   - `MQTT_USERNAME_PREFIX=app`
3. Deploy:
   `npm run deploy`

## Exported Functions

- `issueMqttCredentials` (callable)
  - returns broker/auth details for app MQTT subscription
- `evaluateDeviceAlerts` (Firestore trigger on `devices/{deviceId}`)
  - loads global + override thresholds
  - evaluates metrics (`temperature`, `ph`, `waterLevel`, `tds`)
  - writes `devices/{deviceId}/alert_state/current`
  - appends transition events to `devices/{deviceId}/alerts`
  - performs low-TDS auto-dose command flow using `pump` commands
- `cleanupOldAlerts` (scheduled every 24 hours)
  - deletes `alerts` docs older than 3 days

## Firestore Data Paths Used

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
- `devices/{deviceId}/commands/{commandId}` (`type: "pump"`)

## Alert and Automation Notes

- Alert transition events are written only on state changes.
- Auto-dose is low-TDS only:
  - starts when TDS is below min and automation is enabled
  - stops when TDS reaches configured max (`stopTarget: tds_max`) or timeout
- Default timeout is 300 seconds.
- Cleanup keeps only 3 days of alert history.

## Quick Verification (After Deploy)

1. Ensure `settings/sensors` exists (or save from app Settings -> Sensors).
2. Confirm device doc `devices/{deviceId}` is receiving telemetry fields:
   - `temperatureC`, `ph`, `waterLevelPct`, `tdsPpm`
3. Trigger a breach (for example low TDS) and confirm:
   - `devices/{deviceId}/alert_state/current.activeMetrics` updates
   - new docs appear in `devices/{deviceId}/alerts`
4. If low-TDS auto-dose is enabled, confirm:
   - pending command is written to `devices/{deviceId}/commands` with `type: pump`
   - `devices/{deviceId}/automation/tds.active` toggles true/false through lifecycle
5. After recovery/normalization, confirm:
   - recovery/completion events are appended to `devices/{deviceId}/alerts`

## Required Params

- `MQTT_BROKER_URL` or (`MQTT_BROKER_HOST` + `MQTT_BROKER_PORT`)
- `MQTT_PASSWORD_STATIC` for username/password brokers like HiveMQ
- `MQTT_USERNAME_STATIC` for fixed broker username
- Optional: `MQTT_JWT_SECRET` if your broker validates JWT tokens

Optional:

- `MQTT_WS_PATH` (default `/mqtt`)
- `MQTT_USE_TLS` (default `true`)
- `MQTT_USE_WEBSOCKET` (default `true`)
- `MQTT_USERNAME_PREFIX` (default `app`)

## HiveMQ Cloud Values

- TLS MQTT for ESP/device publish: port `8883`
- Secure WebSocket for Flutter app: port `8884`
- WebSocket path: `/mqtt`
- Username/password: use HiveMQ credentials created in HiveMQ console

Recommended split:

- Device credential:
  - publish: `plantation/<deviceId>/telemetry/live`
  - publish retained: `plantation/<deviceId>/status`
- App credential:
  - subscribe: `plantation/+/telemetry/live` (or per-device if stricter)
  - subscribe: `plantation/+/status`
