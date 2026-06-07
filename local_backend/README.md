# Local Backend

This branch adds a local-first backend for the aquaponics system:

- MQTT broker on the LAN for ESP32 telemetry and commands.
- PostgreSQL as the primary local database.
- WebSocket stream for the Flutter dashboard.
- HTTP API for app commands/settings.
- Firebase Auth remains the login identity.
- Firebase Firestore becomes backup/sync, not the first write path.

## Run Locally

```bash
cd local_backend
npm install
copy .env.example .env
docker compose up -d postgres
npm run migrate
npm start
```

Default endpoints:

- MQTT: `mqtt://<laptop-lan-ip>:1883`
- HTTP: `http://<laptop-lan-ip>:8080`
- WebSocket: `ws://<laptop-lan-ip>:8080/ws`

Build the Flutter app against the local backend:

```bash
flutter build apk --debug ^
  --dart-define=LOCAL_BACKEND_ENABLED=true ^
  --dart-define=LOCAL_BACKEND_HTTP_URL=http://<laptop-lan-ip>:8080 ^
  --dart-define=LOCAL_BACKEND_WS_URL=ws://<laptop-lan-ip>:8080/ws
```

## MQTT Topics

- ESP32 publishes telemetry: `plantation/<deviceId>/telemetry/live`
- ESP32 publishes status: `plantation/<deviceId>/status`
- Backend publishes commands: `plantation/<deviceId>/commands`
- ESP32 publishes command acknowledgements: `plantation/<deviceId>/commands/ack`

In `final_esp32_aquaponics`, set `MQTT_BROKER_HOST` to the LAN IP of the
machine running this backend before uploading the ESP32. This branch uses plain
local MQTT on port `1883` by default.

## Firebase Backup

When `FIREBASE_BACKUP_ENABLED=true`, every local write is inserted into
`firebase_sync_queue`. The worker backs up:

- latest device snapshot to `devices/{deviceId}`
- telemetry history to `devices/{deviceId}/readings/{readingId}`
- commands to `devices/{deviceId}/commands/{commandId}`
- events to `devices/{deviceId}/logs/{eventId}`

Use a Firebase service account via `GOOGLE_APPLICATION_CREDENTIALS`, or run with
Application Default Credentials on a trusted machine.
