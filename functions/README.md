# Firebase Functions (MQTT Credentials)

This folder contains backend callable functions for issuing short-lived MQTT credentials to authenticated app users.

## Deploy

1. Install dependencies:
   npm install
2. Configure non-secret params in `functions/.env`:
   MQTT_BROKER_URL=wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt
   MQTT_WS_PATH=/mqtt
   MQTT_USE_TLS=true
   MQTT_USE_WEBSOCKET=true
   MQTT_USERNAME_STATIC=YOUR_HIVEMQ_APP_USERNAME
   MQTT_PASSWORD_STATIC=YOUR_HIVEMQ_APP_PASSWORD
   MQTT_USERNAME_PREFIX=app
3. Deploy:
   npm run deploy

## HiveMQ Cloud Values

- TLS MQTT for ESP/device publish: port `8883`
- Secure WebSocket for Flutter app: port `8884`
- WebSocket path: `/mqtt`
- Username/password: use HiveMQ credentials you created in the HiveMQ console

Recommended split:

- Device credential:
  - publish: `plantation/<deviceId>/telemetry/live`
  - publish retained: `plantation/<deviceId>/status`
- App credential:
  - subscribe: `plantation/+/telemetry/live` (or per-device if stricter)
  - subscribe: `plantation/+/status`

## Quick Param/Secret Commands

```bash
cd functions
npm install

# Non-secret params are loaded from functions/.env
cat > .env <<'EOF'
MQTT_BROKER_URL=wss://YOUR_CLUSTER_HOST.s1.eu.hivemq.cloud:8884/mqtt
MQTT_WS_PATH=/mqtt
MQTT_USE_TLS=true
MQTT_USE_WEBSOCKET=true
MQTT_USERNAME_STATIC=YOUR_HIVEMQ_APP_USERNAME
EOF

# Deploy callable
npm run deploy
```

## Required Params

- `MQTT_BROKER_URL` or (`MQTT_BROKER_HOST` + `MQTT_BROKER_PORT`)
- `MQTT_PASSWORD_STATIC` for username/password brokers like HiveMQ
- `MQTT_USERNAME_STATIC` for fixed broker username
- optional: `MQTT_JWT_SECRET` if your broker validates JWT tokens

Optional:
- `MQTT_WS_PATH` (default `/mqtt`)
- `MQTT_USE_TLS` (default `true`)
- `MQTT_USE_WEBSOCKET` (default `true`)
- `MQTT_USERNAME_PREFIX` (default `app`)

## Notes

- Commands remain Firestore-based.
- This function only issues broker auth material; it does not proxy telemetry.
