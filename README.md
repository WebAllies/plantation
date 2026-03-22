# Plantation (IoT Aqua App)

Production-ready Flutter + Firebase project for hydroponics monitoring and lettuce health AI scanning.

This README is deployment-focused. If you follow it in order, a new machine can run staging and production safely.

## What This Project Includes
- Flutter mobile app (`lib/`)
- Firebase backend (Cloud Functions + Firestore + Storage rules) (`functions/`, `firestore.rules`, `storage.rules`)
- On-device lettuce classifier (TensorFlow Lite assets in `assets/models/`)
- Local ML training pipeline (`ml/`)
- ESP32 firmware/simulator sketches (`esp32`, `esp32sim`)

Hardware wiring for the current Uno + ESP32 aquaponics setup:
- [WIRING_README.md](/mnt/e/shuaib/plantation/WIRING_README.md)

## Current AI Classes
- `healthy`
- `nitrogen_deficiency`
- `phosphorus_deficiency`
- `potassium_deficiency`
- `fungal_mildew`

Binary mapping in app/reports:
- `healthy -> Healthy`
- all others -> `Unhealthy`

## Architecture At A Glance
- App runtime env switch:
  - `lib/firebase_environment.dart`
  - `lib/firebase_bootstrap.dart`
- Firebase options files:
  - `lib/firebase_options_production.dart`
  - `lib/firebase_options_staging.dart`
- Android google services file used at build time:
  - `android/app/google-services.json`
- AI assets loaded by app:
  - `assets/models/lettuce_model.tflite`
  - `assets/models/labels.txt`
  - `assets/models/model_config.json`

## 1. Prerequisites
Install these first:
- Flutter SDK (stable)
- Android Studio + Android SDK
- Java 17 (required by modern Android Gradle Plugin)
- Node.js 20.x (for Firebase Functions)
- Python 3.10+ (for ML pipeline)
- Git

Check versions:

```bash
flutter --version
node --version
npm --version
python --version
java -version
```

Windows-only requirement:
- Enable Developer Mode (required for Flutter plugin symlinks)

```powershell
start ms-settings:developers
```

## 2. Install Firebase CLI + FlutterFire CLI (Permanent)

Important:
- `firebase` comes from npm (`firebase-tools`)
- `flutterfire` comes from Dart (`flutterfire_cli`)
- `npx flutterfire` is wrong and will fail

Install Firebase CLI:

```bash
npm install -g firebase-tools
firebase --version
```

Install FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire --version
```

If command is "not recognized" on Windows, add both folders to user PATH:
- `%APPDATA%\\npm`
- `%LOCALAPPDATA%\\Pub\\Cache\\bin`

Then restart terminal and re-check:

```bash
firebase --version
flutterfire --version
```

Login once:

```bash
firebase login
firebase projects:list
```

## 3. Clone And Install Dependencies
From repo root:

```bash
flutter pub get
cd functions && npm install && cd ..
```

Optional ML setup:

```bash
python -m venv ml/.venv
# Linux/macOS
source ml/.venv/bin/activate
# Windows PowerShell
# .\\ml\\.venv\\Scripts\\Activate.ps1
pip install -r ml/requirements.txt
```

## 4. Firebase Project Setup (Staging + Production)
Use separate projects so staging can never overwrite production.

Recommended:
- Production project id: `iotaquaapp`
- Staging project id: `iotaquaapp-staging`

For each Firebase project:
1. Create project in Firebase Console.
2. Add Android app with package id `com.example.iot_aqua_app`.
3. Enable Authentication providers you use:
   - Email/Password
   - Google
4. Enable Firestore Database.
5. Enable Storage.

## 5. Generate Firebase Options Files
From repo root:

```bash
flutterfire configure --project iotaquaapp --out lib/firebase_options_production.dart
flutterfire configure --project iotaquaapp-staging --out lib/firebase_options_staging.dart
```

If `flutterfire` says it cannot fetch projects, Firebase CLI is not installed or not in PATH. Fix Section 2 first.

## 6. Manage Android `google-services.json` Per Environment
Android build reads only one file: `android/app/google-services.json`.

Keep two source files locally:
- `android/app/google-services.production.json`
- `android/app/google-services.staging.json`

Before each run/build, copy the right one to the active name:

PowerShell:

```powershell
Copy-Item android/app/google-services.staging.json android/app/google-services.json -Force
# or for prod
Copy-Item android/app/google-services.production.json android/app/google-services.json -Force
```

Bash:

```bash
cp android/app/google-services.staging.json android/app/google-services.json
# or for prod
cp android/app/google-services.production.json android/app/google-services.json
```

If this file and `FIREBASE_ENV` mismatch, startup/auth issues are expected.

## 7. Configure Functions Environment Variables
Create `functions/.env` (base values used in all environments):

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

When deploying to a project, Firebase CLI may create per-project files like:
- `functions/.env.iotaquaapp`
- `functions/.env.iotaquaapp-staging`

These are already git-ignored.

## 8. Deploy Staging Backend First
From repo root:

```bash
npx firebase-tools deploy --only "functions,firestore:rules,storage" --project iotaquaapp-staging
```

PowerShell note:
- Keep the `--only` list in quotes exactly like above.

If this is your first Gen2 functions deploy and you get Eventarc permission errors:
1. Wait 3-10 minutes (service agent IAM propagation).
2. Re-run only failed functions:

```bash
npx firebase-tools deploy --only "functions:evaluateDeviceAlerts,functions:recomputeAlertsOnGlobalThresholdsWrite,functions:recomputeAlertsOnDeviceOverrideWrite" --project iotaquaapp-staging
```

## 9. Run App Against Staging
1. Put staging `google-services.json` in place (Section 6).
2. Run app:

```bash
flutter run --dart-define=FIREBASE_ENV=staging
```

## 10. First Login / Bootstrap Flow
The app login page does not expose public self-registration.

Do this once per Firebase project:
1. In Firebase Console -> Authentication, create first user:
   - email: `superadmin@iot.com`
   - password: your secure password
2. Login in app using that account.
3. App auto-creates `/users/{uid}` and assigns role `super_admin` for that email.
4. Use super admin UI to create admin/employee users.

Firestore collections are document-based and created on first write.
There are no SQL "tables" to pre-create.

Common first-write collections:
- `users`
- `devices`
- `ai_scans`

## 11. Deploy To Production
After staging validation:

1. Copy production `google-services.json` into active path.
2. Deploy backend to production project:

```bash
npx firebase-tools deploy --only "functions,firestore:rules,storage" --project iotaquaapp
```

3. Run app in production mode:

```bash
flutter run --dart-define=FIREBASE_ENV=production
```

## 12. Verification Checklist
After each deploy:
1. App launches and reaches login page.
2. Email login works for super admin account.
3. `/users/{uid}` doc exists and role is correct.
4. Device telemetry writes appear in `devices/{deviceId}`.
5. Alert trigger writes `devices/{deviceId}/alert_state/current`.
6. AI scan writes `ai_scans/{scanId}` with:
   - `predictedClass`
   - `predictedBinary`
   - `topK`
   - `modelVersion`
   - `imagePath`
7. Storage contains uploaded scan image under `ai_scans/<uid>/<scanId>.jpg`.

## 13. Known Errors And Exact Fixes

`flutterfire: The term 'flutterfire' is not recognized`
- Install with `dart pub global activate flutterfire_cli`.
- Add Dart pub cache bin to PATH.

`firebase: The term 'firebase' is not recognized`
- Install with `npm install -g firebase-tools`.
- Add npm global bin to PATH.
- Use `npx firebase-tools ...` as fallback.

`Cannot understand what targets to deploy/serve`
- In PowerShell, quote comma-separated `--only` values:
  - `--only "functions,firestore:rules,storage"`

`Build with plugins requires symlink support`
- Enable Windows Developer Mode, then rerun build.

`AAR metadata requires Android Gradle plugin 8.9.1+`
- Already fixed in `android/settings.gradle.kts` (AGP 8.9.1).
- If you downgraded locally, restore AGP 8.9.1.

Kotlin incremental cache root errors (`different roots ... could not close incremental caches`)
- Already mitigated in `android/gradle.properties` by disabling Kotlin incremental.
- Clean and rebuild:

```bash
flutter clean
rm -rf build .dart_tool
flutter pub get
```

Windows PowerShell equivalent for delete:

```powershell
flutter clean
Remove-Item -Recurse -Force build,.dart_tool
flutter pub get
```

App appears stuck on splash when switching env
- Most common cause: wrong `google-services.json` for selected `FIREBASE_ENV`.
- Re-copy correct file (Section 6) and rerun.

## 14. ML Training / Model Replacement
See `ml/README.md` for the full local GPU training pipeline.

Pipeline updates these assets (unless skipped):
- `assets/models/lettuce_model.tflite`
- `assets/models/labels.txt`
- `assets/models/model_config.json`

## 15. Repo Structure
- `lib/`: Flutter app code
- `functions/`: Firebase Functions backend
- `ml/`: Training, calibration, TFLite export scripts
- `assets/models/`: Shipped model artifacts
- `dataset/`: Local dataset (git-ignored)
- `firebase.json`: Firebase deploy config
- `firestore.rules`, `storage.rules`: security rules

