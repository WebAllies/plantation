# Plantation (IoT Aqua App)

Plantation is a Flutter + Firebase system for hydroponic monitoring and AI lettuce diagnostics.

It has two core parts:
- IoT telemetry and automation (MQTT + Firestore + Cloud Functions)
- On-device lettuce image classification (TensorFlow Lite)

## Features

- Realtime telemetry from ESP32 over MQTT (`plantation/{deviceId}/telemetry/live`)
- Device online/offline status topic with retained/LWT state (`plantation/{deviceId}/status`)
- Firestore-backed alerting and low-TDS automation
- AI scan for lettuce classes:
  - `healthy`
  - `nitrogen_deficiency`
  - `phosphorus_deficiency`
  - `potassium_deficiency`
  - `fungal_mildew`
- Binary compatibility in app/reporting:
  - `healthy -> Healthy`
  - all other classes -> `Unhealthy`
- Scan history in Firestore with image upload to Firebase Storage
- Admin verification fields for retraining loop

## Repo Layout

- `lib/`: Flutter app
- `functions/`: Firebase Cloud Functions
- `ml/`: local model training/export pipeline
- `dataset/`: local dataset and metadata CSV
- `assets/models/`: shipped TFLite model + labels + model config
- `esp32`, `esp32sim`: firmware/simulator sketches

## Prerequisites

- Flutter SDK
- Firebase CLI (`firebase-tools`)
- FlutterFire CLI (`flutterfire_cli`)
- Node.js 20+ (for `functions/`)
- Python 3.10+ (for `ml/`)

## Quick Start

1. Install app dependencies:

```bash
flutter pub get
```

2. Install Functions dependencies:

```bash
cd functions
npm install
cd ..
```

3. Configure Firebase for production (safe output path):

```bash
flutterfire configure --project iotaquaapp --out lib/firebase_options_production.dart
```

4. Configure Functions env file:

Create `functions/.env`:

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

5. Deploy backend and rules:

```bash
firebase deploy --only functions,firestore:rules,storage --project <your-project-id>
```

6. Run the app:

```bash
flutter run
```

## Firebase Environments (Production + Staging)

This repo now uses separate files so staging cannot overwrite production config:

- Production: `lib/firebase_options_production.dart`
- Staging: `lib/firebase_options_staging.dart`
- Selector: `lib/firebase_bootstrap.dart`
- Environment flag: `--dart-define=FIREBASE_ENV=production|staging`
- Legacy default output file `lib/firebase_options.dart` is no longer used by `main.dart`.

Generate/update staging config:

```bash
flutterfire configure --project iotaquaapp-staging --out lib/firebase_options_staging.dart
```

Generate/update production config:

```bash
flutterfire configure --project iotaquaapp --out lib/firebase_options_production.dart
```

Run production:

```bash
flutter run --dart-define=FIREBASE_ENV=production
```

Run staging:

```bash
flutter run --dart-define=FIREBASE_ENV=staging
```

If `FIREBASE_ENV` is omitted, app defaults to production.

## Firebase Staging Workflow

Use this before production releases.

1. Create staging project (example: `iotaquaapp-staging`)
2. Register Android app with same package name
3. Generate staging options file:

```bash
flutterfire configure --project iotaquaapp-staging --out lib/firebase_options_staging.dart
```

4. Add CLI aliases:

```bash
firebase use --add
# add alias: staging
# add alias: prod
```

5. Deploy to staging:

```bash
firebase deploy --only functions,firestore:rules,storage --project staging
```

6. Test on phone against staging Firestore/Storage, then deploy to prod.

## AI Model Files Used by App

- `assets/models/lettuce_model.tflite`
- `assets/models/labels.txt`
- `assets/models/model_config.json`

`model_config.json` controls:
- `modelVersion`
- `inputSize`
- `normalization`
- `classThresholds`
- `binaryMap`

Current pipeline uses `normalization: "[0,255]"`.

## Retraining the Model

See `ml/README.md` for full details.

Minimum run commands:

```bash
source ml/.venv/bin/activate
python ml/quality_audit.py \
  --metadata dataset/metadata.csv \
  --image-root dataset/images \
  --output-report ml/artifacts/quality_report.csv \
  --output-metadata dataset/metadata.cleaned.csv \
  --drop-exact-duplicates
python ml/run_pipeline.py --config ml/configs/v1.yaml --python python
```

This updates shipped model assets automatically (unless `--skip-asset-copy` is used).

## Firestore Paths (Important)

- Device state: `devices/{deviceId}`
- Commands: `devices/{deviceId}/commands/{commandId}`
- Alert state: `devices/{deviceId}/alert_state/current`
- Alert history: `devices/{deviceId}/alerts/{alertId}`
- AI scans: `ai_scans/{scanId}`

AI scan documents include:
- `predictedClass`, `predictedBinary`, `confidence`, `topK`
- `modelVersion`, `imagePath`
- `verificationStatus`, `verifiedLabel`, `verifiedBy`, `verifiedAt`

## Notes

- If TensorFlow cannot load CUDA, ML training runs on CPU.
- App environment is selected by `FIREBASE_ENV` (`production` default, `staging` optional).
