# Nano USB Bridge

Use this when the Arduino Nano cannot talk to the ESP32 through GPIO serial.

## What It Does

The laptop becomes the bridge:

```text
Arduino Nano USB -> Windows laptop -> Realtime server -> Flutter UI
                                         |
                                         +-> MQTT -> ESP32
```

This lets the UI receive Nano readings even when Nano TX to ESP32 RX16 is not wired.
The ESP32 also subscribes to the bridged readings on MQTT so it can still use the sensor values.

## Required

- Nano connected to the laptop by USB.
- Nano running `uno_aquaponics`.
- Realtime server reachable.
- Node dependencies installed in `local_backend`.

## Start The Bridge

From the project root:

```bat
cd local_backend
set NANO_SERIAL_PORT=COM11
set NANO_SERIAL_BAUD=115200
set DEVICE_ID=esp32_aquaponics_01
set LOCAL_BACKEND_HTTP_URL=http://116.203.96.119:8080
npm run bridge:nano
```

Expected output:

```text
[nano-bridge] serial open COM11
[nano] PH:...
[nano] TDS:...
[nano] PHUP:...
[nano-bridge] published esp32_aquaponics_01: ...
```

## Run The Flutter Windows App

```bat
C:\Users\baich\develop\flutter\bin\flutter.bat run -d windows ^
  --dart-define=LOCAL_BACKEND_ENABLED=true ^
  --dart-define=LOCAL_BACKEND_HTTP_URL=http://116.203.96.119:8080 ^
  --dart-define=LOCAL_BACKEND_WS_URL=ws://116.203.96.119:8080/ws
```

## Data Sent To The UI

The bridge sends these fields:

- `ph`
- `tdsPpm`
- `phUpTankLevelPct`
- `phDownTankLevelPct`
- `nutrientTankLevelPct`
- `nanoOnline`
- `nanoError`
- `sensorStatus`

## MQTT Topic For ESP32

The server republishes the bridged readings to:

```text
plantation/esp32_aquaponics_01/nano/telemetry
```

The ESP32 subscribes to that topic and updates its local sensor values from it.
