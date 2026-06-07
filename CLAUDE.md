# Claude Code Handoff: Local MQTT/PostgreSQL Backend

## Current Branch

- Branch: `local-mqtt-postgres-backend`
- Base branch before this work: `new`
- Current local changes are not committed yet.

## Goal

Move the aquaponics app to a local/server-first architecture:

- Firebase remains for login/auth.
- Local backend becomes the primary write path.
- PostgreSQL stores device state, telemetry history, commands, and events.
- MQTT is used for ESP32 telemetry and commands.
- WebSocket streams live telemetry to the Flutter app.
- Firebase Firestore is used as backup/sync for local PostgreSQL writes.

## Files Added/Changed

- `local_backend/`
  - Node.js backend.
  - Embedded MQTT broker via `aedes`.
  - PostgreSQL schema/migrations.
  - HTTP API.
  - WebSocket hub.
  - Firebase backup worker.
- `lib/core/local/local_backend_config.dart`
  - Dart defines for local backend URLs.
- `lib/core/local/local_backend_command_service.dart`
  - Sends commands/settings to the local backend first.
- `lib/control/control_page.dart`
  - Sends feed/relay/settings to local backend first, Firestore fallback second.
- `lib/dashboard/dashboard_page.dart`
  - Prefers local backend WebSocket when enabled, then existing MQTT/Firestore fallback.
- `final_esp32_aquaponics`
  - Uses local MQTT by default.
  - Subscribes to `plantation/<deviceId>/commands`.
  - Publishes acknowledgements to `plantation/<deviceId>/commands/ack`.
- `.gitignore`
  - Ignores `local_backend/node_modules/` and local backend `.env` files.

## Hetzner Deployment

Server:

- IP: `116.203.96.119`
- SSH user: `root`
- SSH key on this machine: `~/.ssh/plantation_hetzner_ed25519`
- App directory: `/opt/plantation-local-backend`
- Systemd service: `plantation-local-backend`

Public endpoints:

- Health: `http://116.203.96.119:8080/health`
- HTTP API: `http://116.203.96.119:8080/api`
- WebSocket: `ws://116.203.96.119:8080/ws`
- MQTT: `mqtt://116.203.96.119:1883`

Server commands:

```bash
ssh -i ~/.ssh/plantation_hetzner_ed25519 root@116.203.96.119
systemctl status plantation-local-backend
journalctl -u plantation-local-backend -f
cd /opt/plantation-local-backend
npm run check
npm run migrate
systemctl restart plantation-local-backend
```

PostgreSQL:

- Database: `plantation`
- Role: `plantation`
- Password is only in `/opt/plantation-local-backend/.env` on the server.

Useful DB checks:

```bash
sudo -u postgres psql -d plantation
select id, online, esp_status, last_seen from devices;
select status, count(*) from firebase_sync_queue group by status order by status;
```

Firewall:

- UFW is enabled.
- Allowed inbound: `22/tcp`, `8080/tcp`, `1883/tcp`.

## Firebase Backup Status

Firebase backup initially failed because Hetzner had no Google service-account credentials.
This was fixed by adding a Firestore REST fallback using the existing Firebase device login.

Config keys used by the backend:

- `FIREBASE_WEB_API_KEY`
- `FIREBASE_BACKUP_EMAIL`
- `FIREBASE_BACKUP_PASSWORD`
- `FIREBASE_PROJECT_ID=iotaquaapp`

The server `.env` has those values. Do not print or commit it.

Validation already done:

- `POST /api/devices/esp32_deploy_test/telemetry` returned `{"readingId":"1"}`.
- PostgreSQL received the device and telemetry.
- `firebase_sync_queue` moved the test rows to `synced`.

## Build App For Hetzner Backend

Use these Dart defines:

```bash
flutter build apk --debug \
  --dart-define=LOCAL_BACKEND_ENABLED=true \
  --dart-define=LOCAL_BACKEND_HTTP_URL=http://116.203.96.119:8080 \
  --dart-define=LOCAL_BACKEND_WS_URL=ws://116.203.96.119:8080/ws
```

Windows command style:

```bat
%USERPROFILE%\develop\flutter\bin\flutter.bat build apk --debug ^
  --dart-define=LOCAL_BACKEND_ENABLED=true ^
  --dart-define=LOCAL_BACKEND_HTTP_URL=http://116.203.96.119:8080 ^
  --dart-define=LOCAL_BACKEND_WS_URL=ws://116.203.96.119:8080/ws
```

## ESP32 Firmware Note

`final_esp32_aquaponics` currently has:

```cpp
#define MQTT_BROKER_HOST "192.168.1.100"
#define MQTT_BROKER_PORT 1883
#define MQTT_USE_TLS 0
```

Before uploading for Hetzner, change `MQTT_BROKER_HOST` to:

```cpp
#define MQTT_BROKER_HOST "116.203.96.119"
```

Then compile/upload the ESP32 with:

```bat
%USERPROFILE%\.local\arduino-cli\arduino-cli.exe compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app %TEMP%\final_esp32_aquaponics
%USERPROFILE%\.local\arduino-cli\arduino-cli.exe upload -p COM10 --fqbn esp32:esp32:esp32:PartitionScheme=huge_app %TEMP%\final_esp32_aquaponics
```

The Nano code does not need backend changes.

## Validation Commands Already Run Locally

```bash
cd local_backend
npm run check
```

Targeted Dart analysis passed:

```bat
%USERPROFILE%\develop\flutter\bin\cache\dart-sdk\bin\dart.exe analyze ^
  E:\shuaib\plantation\lib\core\local\local_backend_config.dart ^
  E:\shuaib\plantation\lib\core\local\local_backend_command_service.dart ^
  E:\shuaib\plantation\lib\control\control_page.dart ^
  E:\shuaib\plantation\lib\dashboard\dashboard_page.dart
```

Firmware compiles passed before Hetzner deployment:

- ESP32 `final_esp32_aquaponics`
- Nano `uno_aquaponics`

## Important Security Follow-Ups

Current Hetzner deployment is functional but not hardened:

- MQTT on `1883` is plain and unauthenticated.
- HTTP/WebSocket are plain `http/ws`.
- `LOCAL_BACKEND_REQUIRE_AUTH=false`, because the current app WebSocket does not attach a Firebase token yet.

Recommended next hardening:

1. Add Firebase token query/header to app WebSocket connection.
2. Set `LOCAL_BACKEND_REQUIRE_AUTH=true`.
3. Put Caddy/Nginx in front of HTTP/WebSocket for TLS.
4. Add MQTT username/password or move MQTT behind TLS/VPN.
5. Consider deleting the test device `esp32_deploy_test` from local PostgreSQL and Firebase.

## Next Practical Steps

1. Change ESP32 `MQTT_BROKER_HOST` to `116.203.96.119`.
2. Build the APK with the Hetzner Dart defines.
3. Install the APK on the phones.
4. Upload ESP32 firmware.
5. Watch live server logs:

```bash
journalctl -u plantation-local-backend -f
```

6. Confirm telemetry arrives:

```sql
select id, online, esp_status, last_seen from devices;
select device_id, ts, ph, tds_ppm, water_level_pct from telemetry_readings order by id desc limit 10;
```
