# Smart IoT Aquaponics (AquaFarm)

Flutter app for monitoring and controlling an aquaponics setup with Firebase, ESP32 devices, live WebSocket telemetry, and AI-based lettuce leaf scans.

## What This App Includes

- Firebase Auth login (email/password and Google sign-in)
- Role-based access using Firestore `users/{uid}`:
  - `super_admin`: user management + AI report export
  - `admin`: device control + sensor settings tab
  - `employee`: monitoring + AI scan/history
- Multi-device picker from Firestore `devices` collection
- Live dashboard:
  - WebSocket streaming from `devices/{deviceId}.wsUrl`
  - Automatic fallback to Firestore snapshot fields when socket is down
- Device control tab (admin/super_admin): sends pending commands to Firestore
- AI leaf scan (camera + TFLite model) and scan history
- Super admin AI reports with filtering and PDF/CSV export

## Tech Stack

- Flutter (Dart SDK `^3.8.1`)
- Firebase:
  - Authentication
  - Cloud Firestore
- ESP32 firmware (Arduino C++ sketches in root files `esp32` and `esp32sim`)
- WebSocket telemetry via `web_socket_channel`
- On-device image inference with `tflite_flutter`

## Project Layout

- `lib/main.dart`: app bootstrap, Firebase init, theme loading
- `lib/features/auth/`: login flow
- `lib/features/shell/main_shell.dart`: role-based tabs and device picker
- `lib/dashboard/dashboard_page.dart`: live telemetry UI (WebSocket + Firestore fallback)
- `lib/control/control_page.dart`: command dispatch for pump/valve
- `lib/ai/`: camera scan, TFLite service, history, super admin reports
- `firestore.rules`: Firestore security rules
- `esp32`: ESP32 hardware firmware sketch
- `esp32sim`: ESP32 simulator firmware sketch (includes WebSocket server)

## Prerequisites

- Flutter SDK installed
- Android/iOS/Web build tooling as needed
- Firebase project with:
  - Authentication enabled (Email/Password, Google if used)
  - Cloud Firestore enabled
- Firebase CLI (to deploy rules)
- Arduino IDE or PlatformIO (if building ESP32 firmware)

## Quick Start

1. Install dependencies:

```bash
flutter pub get
```

2. Configure Firebase:

- This repo currently includes Firebase config files for project `iotaquaapp`.
- If you are using a different Firebase project:
  - regenerate `lib/firebase_options.dart` with FlutterFire
  - replace `android/app/google-services.json`
  - add iOS config (`GoogleService-Info.plist`) if building iOS

3. Deploy Firestore rules:

```bash
firebase deploy --only firestore:rules
```

4. Run the app:

```bash
flutter run
```

## First Login and Roles

- Super admin email is hardcoded in `AuthService` as:
  - `superadmin@iot.com`
- On successful login, `users/{uid}` is auto-created if missing.
- If the email is `superadmin@iot.com`, role is set to `super_admin`; otherwise default role is `employee`.

Practical setup:

1. Create Firebase Auth user `superadmin@iot.com` manually in Firebase Console.
2. Sign in once from the app to auto-create `users/{uid}` with `super_admin` role.
3. Use Settings -> System -> User Management to create admin/employee users.

## Firestore Data Model Used by the App

### `users/{uid}`

- `uid`, `email`, `name`, `role`, `createdAt`

### `devices/{deviceId}`

Common fields used in UI:

- `name`, `online`, `lastSeen`, `rssi`
- `pumpState`, `valveState`
- `temperatureC`, `ph`, `waterLevelPct`, `tdsPpm`
- `wsUrl` (required for live WebSocket dashboard mode)
- `simulator`

Subcollections:

- `commands/{commandId}`: `type`, `targetState`, `status`, `requestedAt`, `executedAt`, `message`, etc.
- `logs/{logId}`: device log events
- `readings/{readingId}`: periodic snapshots

### `ai_scans/{scanId}`

- `userId`, `email`, `role`, `label`, `confidence`, `createdAt`

## Live Telemetry Contract

Dashboard expects WebSocket JSON messages with fields like:

```json
{
  "deviceId": "esp32_sim_01",
  "tsMs": 1234567,
  "temperatureC": 24.5,
  "ph": 6.8,
  "waterLevelPct": 82.0,
  "tdsPpm": 900.0,
  "pumpState": false,
  "valveState": false,
  "rssi": -45
}
```

If WebSocket disconnects or `wsUrl` is missing, dashboard falls back to Firestore device document values.

## ESP32 and Simulator Notes

- `esp32`: real hardware-oriented firmware (pump/valve GPIO control, Firestore heartbeat + command polling)
- `esp32sim`: simulated telemetry + embedded WebSocket server on port `81`

Both sketches:

- Authenticate to Firebase using email/password
- Write device state to `devices/{deviceId}`
- Poll `devices/{deviceId}/commands` for `pending` commands
- Patch command status to `executed` or `failed`

Important:

- Wi-Fi and Firebase credentials are currently hardcoded in firmware files.
- Rotate/remove sensitive credentials before sharing or production use.

## Useful Commands

```bash
flutter analyze
flutter test
```

## Known Gaps

- `AnalyticsPage` is currently a placeholder.
- Sensor threshold settings UI exists but persistence/alert logic is not yet wired.
